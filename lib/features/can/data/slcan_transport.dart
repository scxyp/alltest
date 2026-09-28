import 'dart:async';
import 'dart:typed_data';

import 'package:libserialport/libserialport.dart';

import '../domain/can_frame.dart';
import '../domain/can_transport.dart';

/// 基于 SLCAN（Lawicel）ASCII 协议的 CAN 传输层实现。
///
/// 适配 CANable / Lawicel CANUSB / ESP32 等通过虚拟串口暴露 CAN 接口的适配器。
/// 内部保留原 [CanPortService] 的健壮轮询 + CR 分帧逻辑，
/// 但对外暴露 [CanTransport] 接口，与上层 CAN / CANopen 会话解耦。
class SlcanTransport implements CanTransport {
  SlcanTransport();

  SerialPort? _port;
  Timer? _pollTimer;
  bool _dead = false;
  final List<int> _lineBuffer = [];

  /// SLCAN 初始化序列的完成标志（适配器返回任何响应后视为就绪）。
  bool _initialized = false;

  static const Duration _pollInterval = Duration(milliseconds: 15);

  @override
  String get transportType => 'slcan';

  @override
  String get transportLabel => 'SLCAN 串口（Lawicel 协议）';

  @override
  bool get isOpen => _port?.isOpen ?? false;

  /// 系统当前可用的串口名列表（供 [CanTransportRegistry] 注册使用）。
  static List<String> get availableAdapters {
    try {
      return SerialPort.availablePorts;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> open({
    required CanTransportConfig config,
    required void Function(CanFrame frame) onFrame,
    required void Function(Object error) onError,
  }) async {
    final port = SerialPort(config.portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw StateError(
        '打开 ${config.portName} 失败：${error?.toString() ?? '未知错误'}',
      );
    }

    final cfg = SerialPortConfig()
      ..baudRate = (config.rawConfig['baudRate'] as num?)?.toInt() ?? 115200
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 0
      ..setFlowControl(SerialPortFlowControl.none);

    try {
      port.config = cfg;
    } catch (e) {
      try {
        port.close();
      } catch (_) {}
      port.dispose();
      throw StateError('应用串口参数失败：$e');
    }

    _port = port;
    _dead = false;
    _initialized = false;
    _lineBuffer.clear();

    // SLCAN 初始化序列
    await Future.delayed(const Duration(milliseconds: 30));
    _writeRaw('C\r');
    await Future.delayed(const Duration(milliseconds: 30));
    _writeRaw('S${config.canBitrate.slcanCode}\r');
    await Future.delayed(const Duration(milliseconds: 30));
    _writeRaw('O\r');
    await Future.delayed(const Duration(milliseconds: 50));
    _initialized = true;

    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => _pollOnce(onFrame, onError),
    );
  }

  void _writeRaw(String command) {
    final port = _port;
    if (port == null || !port.isOpen) {
      throw StateError('串口未打开');
    }
    try {
      port.write(Uint8List.fromList(command.codeUnits));
    } catch (e) {
      throw StateError('写入失败（${_describeError(e)}）');
    }
  }

  String _describeError(Object e) {
    if (e is SerialPortError) {
      return '串口错误（errno=${e.errorCode}）';
    }
    return '$e';
  }

  void _pollOnce(
    void Function(CanFrame) onFrame,
    void Function(Object) onError,
  ) {
    if (_dead) return;
    final port = _port;
    if (port == null || !port.isOpen) return;

    try {
      port.signals;
    } catch (e) {
      _handleFatal(e, onError);
      return;
    }

    final int available;
    try {
      available = port.bytesAvailable;
    } catch (e) {
      _handleFatal(e, onError);
      return;
    }
    if (available <= 0) return;

    final Uint8List data;
    try {
      data = port.read(available, timeout: 0);
    } catch (e) {
      _handleFatal(e, onError);
      return;
    }
    if (data.isNotEmpty) {
      _processBytes(data, onFrame);
    }
  }

  void _processBytes(
    Uint8List data,
    void Function(CanFrame) onFrame,
  ) {
    for (final byte in data) {
      if (byte == 0x0D) {
        if (_lineBuffer.isNotEmpty) {
          final line = String.fromCharCodes(_lineBuffer);
          _lineBuffer.clear();
          // BLE (0x07) = 适配器错误
          if (line.codeUnitAt(0) == 0x07) continue;
          final frame = CanFrame.fromSlcan(line);
          if (frame != null) onFrame(frame);
        }
      } else if (byte == 0x0A) {
        continue;
      } else {
        _lineBuffer.add(byte);
      }
    }
  }

  void _handleFatal(Object error, void Function(Object) onError) {
    if (_dead) return;
    _dead = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _releasePort();
    onError(StateError(_describeError(error)));
  }

  @override
  Future<int> sendFrame(CanFrame frame) async {
    final slcan = frame.toSlcanCommand();
    _writeRaw(slcan);
    return slcan.length;
  }

  @override
  Future<void> close() async {
    if (_port != null && _initialized) {
      try {
        _writeRaw('C\r');
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 20));
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    _dead = true;
    _initialized = false;
    _lineBuffer.clear();
    _releasePort();
  }

  void _releasePort() {
    try {
      if (_port?.isOpen ?? false) _port?.close();
    } catch (_) {}
    try {
      _port?.dispose();
    } catch (_) {}
    _port = null;
  }

  @override
  Future<void> dispose() async {
    await close();
  }
}
