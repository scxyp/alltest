import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../serial/data/serial_port_service.dart';
import '../../serial/domain/serial_config.dart';
import '../domain/modbus_crc.dart';

/// 一条已完成分帧的 Modbus 报文通道（send/recv 均为完整 ADU）。
///
/// - RTU：[address, PDU..., crcLo, crcHi]
/// - TCP：[txnId(2), protoId(2), length(2), unitId(1), PDU...]
abstract class ModbusChannel {
  /// 完整帧数据流。
  Stream<Uint8List> get frames;

  /// 发送一帧完整 ADU。
  void send(Uint8List frame);

  Future<void> close();
}

// ---------------------------------------------------------------------------
// RTU（串口）
// ---------------------------------------------------------------------------

/// 基于串口的 RTU 通道：按 Modbus 3.5 字符静默间隔对字节流分帧。
class ModbusRtuChannel extends ModbusChannel {
  ModbusRtuChannel({
    required this.service,
    required this.serialConfig,
  });

  final SerialPortService service;
  final SerialConfig serialConfig;
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Timer? _gapTimer;

  @override
  Stream<Uint8List> get frames => _controller.stream;

  /// 3.5 字符帧间隔（每字符 11 bit）。规范在 >19200bps 时固定 1.75ms，
  /// 考虑桌面定时器精度，下限取 16ms，上限 100ms（低波特率时）。
  int get _frameGapMs {
    final t = 3.5 * 11 * 1000 / serialConfig.baudRate;
    return t.clamp(16, 100).round();
  }

  void open() {
    service.open(
      serialConfig,
      onData: _onData,
      onError: (e) {
        _controller.addError(e);
      },
    );
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    _gapTimer?.cancel();
    _gapTimer = Timer(Duration(milliseconds: _frameGapMs), _emitFrame);
  }

  void _emitFrame() {
    _gapTimer = null;
    if (_buffer.isEmpty) return;
    final frame = _buffer.toBytes();
    _buffer.takeBytes();
    // CRC 校验失败的帧静默丢弃（总线噪声 / 非本协议数据）。
    if (ModbusCrc.verify(frame)) {
      _controller.add(frame);
    }
  }

  @override
  void send(Uint8List frame) {
    service.write(frame);
  }

  @override
  Future<void> close() async {
    _gapTimer?.cancel();
    await service.close();
    await _controller.close();
  }
}

// ---------------------------------------------------------------------------
// TCP（MBAP）
// ---------------------------------------------------------------------------

/// TCP 上的一帧解析结果。
class TcpModbusFrame {
  const TcpModbusFrame({
    required this.transactionId,
    required this.unitId,
    required this.pdu,
  });

  final int transactionId;
  final int unitId;
  final Uint8List pdu;
}

/// MBAP 帧编解码工具。
class ModbusTcpFrame {
  const ModbusTcpFrame._();

  /// 组装完整 TCP ADU。
  static Uint8List build({
    required int transactionId,
    required int unitId,
    required Uint8List pdu,
  }) {
    final length = pdu.length + 1; // length 字段 = Unit ID + PDU
    final b = BytesBuilder()
      ..addByte((transactionId >> 8) & 0xFF)
      ..addByte(transactionId & 0xFF)
      ..addByte(0)
      ..addByte(0)
      ..addByte((length >> 8) & 0xFF)
      ..addByte(length & 0xFF)
      ..addByte(unitId & 0xFF)
      ..add(pdu);
    return b.toBytes();
  }

  /// 解析一帧完整 TCP ADU。
  static TcpModbusFrame parse(Uint8List frame) {
    final transactionId =
        ((frame[0] & 0xFF) << 8) | (frame[1] & 0xFF);
    final length = ((frame[4] & 0xFF) << 8) | (frame[5] & 0xFF);
    final unitId = frame[6] & 0xFF;
    return TcpModbusFrame(
      transactionId: transactionId,
      unitId: unitId,
      pdu: Uint8List.sublistView(frame, 7, 6 + length),
    );
  }
}

/// TCP 通道：对字节流按 MBAP length 字段精确分帧（自动处理粘包/半包）。
class ModbusTcpChannel extends ModbusChannel {
  ModbusTcpChannel(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: (Object e) {
        if (!_controller.isClosed) _controller.addError(e);
      },
      onDone: () {
        // 对端正常关闭：结束帧流，由主 / 从控制器各自处理断连逻辑。
        if (!_controller.isClosed) unawaited(_controller.close());
      },
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  late final StreamSubscription<Uint8List> _subscription;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  @override
  Stream<Uint8List> get frames => _controller.stream;

  static Future<ModbusTcpChannel> connect(String host, int port) async {
    final socket = await Socket.connect(host, port);
    return ModbusTcpChannel(socket);
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    var bytes = _buffer.toBytes();
    var consumed = 0;
    // MBAP 头固定 7 字节，length 字段位于偏移 4-5。
    while (bytes.length >= 7) {
      final length = ((bytes[4] & 0xFF) << 8) | (bytes[5] & 0xFF);
      final total = 6 + length;
      if (bytes.length < total) break; // 半包，等待更多数据。
      _controller.add(Uint8List.sublistView(bytes, 0, total));
      consumed += total;
      bytes = Uint8List.sublistView(bytes, total);
    }
    // 重建剩余字节缓冲。
    _buffer.takeBytes();
    if (consumed > 0) {
      _buffer.add(bytes);
    }
  }

  @override
  void send(Uint8List frame) {
    _socket.add(frame);
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    _socket.destroy();
    await _controller.close();
  }
}

/// Modbus TCP 从机监听服务：为每个接入连接产出一个 [ModbusTcpChannel]。
class ModbusTcpServer {
  ModbusTcpServer._(this._server);

  final ServerSocket _server;
  final List<ModbusTcpChannel> _channels = [];
  final StreamController<ModbusTcpChannel> _acceptController =
      StreamController<ModbusTcpChannel>.broadcast();

  Stream<ModbusTcpChannel> get onChannel => _acceptController.stream;

  static Future<ModbusTcpServer> listen({
    String? bindAddress,
    int port = 502,
  }) async {
    final server = await ServerSocket.bind(
      bindAddress == null || bindAddress.isEmpty
          ? InternetAddress.anyIPv4
          : InternetAddress(bindAddress),
      port,
    );
    final instance = ModbusTcpServer._(server);
    server.listen((socket) {
      final channel = ModbusTcpChannel(socket);
      instance._channels.add(channel);
      instance._acceptController.add(channel);
    });
    return instance;
  }

  Future<void> close() async {
    for (final c in List<ModbusTcpChannel>.from(_channels)) {
      await c.close();
    }
    _channels.clear();
    await _server.close();
    await _acceptController.close();
  }
}
