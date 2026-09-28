import 'dart:async';
import 'dart:typed_data';

import 'package:libserialport/libserialport.dart';

import '../domain/can_config.dart';

/// 对 libserialport 的薄封装，专用于 SLCAN 协议。
///
/// 与串口模块的 `SerialPortService` 采用相同的健壮轮询模式
/// （15ms 非阻塞轮询 + 严格释放顺序：停轮询 → 关端口 → 释放内存），
/// 但接收侧按 CR（`\r`，0x0D）分帧：SLCAN 命令以 `\r` 结尾，
/// 适配器返回的帧也是 CR 终止的 ASCII 行。每凑成一行回调 [onLine]。
///
/// 不使用库自带的 `SerialPortReader`：它会启动一个持有端口原始指针的
/// isolate，关闭 / 拔线时若 isolate 仍阻塞在原生调用中而我们释放了端口，
/// 会造成原生层 use-after-free 崩溃。
///
/// 资源释放规则（重要）：
/// `SerialPort.dispose()` 内部会先释放它持有的 `SerialPortConfig` 再释放
/// 端口结构，而 `SerialPortConfig.dispose()` 没有二次释放防护。因此配置
/// 对象一旦通过 `port.config = ...` 交给端口，就绝不能再单独调用其
/// `dispose()`，否则同一块原生内存被 free 两次。
class CanPortService {
  SerialPort? _port;
  Timer? _pollTimer;
  bool _dead = false;

  /// 行缓冲：SLCAN 以 CR（0x0D）分帧。
  final List<int> _lineBuffer = [];

  /// 轮询周期。15ms 足够低延迟。
  static const Duration _pollInterval = Duration(milliseconds: 15);

  bool get isOpen => _port?.isOpen ?? false;

  /// 打开串口并开始轮询接收。
  ///
  /// [onLine] 在每凑成一行（以 CR 结尾）时回调，传入不含 CR 的行文本。
  /// [onError] 在连接致命错误（如设备拔出）时回调。
  void open(
    CanConfig config, {
    required void Function(String line) onLine,
    required void Function(Object error) onError,
  }) {
    final port = SerialPort(config.portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw StateError(
        '打开 ${config.portName} 失败：${error?.toString() ?? '未知错误'}',
      );
    }

    // SLCAN 适配器串口固定 8N1，仅波特率可配。
    final cfg = SerialPortConfig()
      ..baudRate = config.baudRate
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 0 // 1 stop bit
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
    _lineBuffer.clear();
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => _pollOnce(onLine, onError),
    );
  }

  String _describeError(Object e) {
    if (e is SerialPortError) {
      return '串口错误（errno=${e.errorCode}）';
    }
    return '$e';
  }

  void _pollOnce(
    void Function(String) onLine,
    void Function(Object) onError,
  ) {
    if (_dead) return;
    final port = _port;
    if (port == null || !port.isOpen) return;

    // 拔线探针：读取调制解调器状态线（内部为 GetCommModemStatus）。
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
      _processBytes(data, onLine);
    }
  }

  /// 将原始字节按 CR 分帧，每凑成一行回调 [onLine]。
  void _processBytes(Uint8List data, void Function(String) onLine) {
    for (final byte in data) {
      if (byte == 0x0D) {
        // CR：一帧结束
        if (_lineBuffer.isNotEmpty) {
          final line = String.fromCharCodes(_lineBuffer);
          _lineBuffer.clear();
          onLine(line);
        }
        // 空行（纯 CR）是 SLCAN 成功 ACK，忽略。
      } else if (byte == 0x0A) {
        // LF：部分适配器会在 CR 后追加 LF，忽略。
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

  /// 同步写出数据（SLCAN 命令字符串的 ASCII 字节）。
  void write(String command) {
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

  /// 停止轮询并释放全部原生资源。可重复调用。
  Future<void> close() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _dead = true;
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

  /// 系统当前可用的串口名列表。
  static List<String> get availablePorts => SerialPort.availablePorts;
}
