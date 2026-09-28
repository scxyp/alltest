import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../serial/data/serial_port_service.dart';
import '../../serial/domain/serial_config.dart';
import '../data/modbus_channels.dart';
import '../domain/modbus_crc.dart';
import '../domain/modbus_pdu.dart';
import '../domain/modbus_register_bank.dart';

/// 从机连接参数。
class SlaveConfig {
  const SlaveConfig({
    this.mode = ModbusTransportMode.tcp,
    this.serialConfig,
    this.rtuAddress = 1,
    this.bindAddress = '',
    this.tcpPort = 502,
  });

  final ModbusTransportMode mode;
  final SerialConfig? serialConfig;

  /// RTU 从机地址（1-247）。
  final int rtuAddress;

  /// TCP 绑定网卡 IP（空为 0.0.0.0）与监听端口。
  final String bindAddress;
  final int tcpPort;

  SlaveConfig copyWith({
    ModbusTransportMode? mode,
    SerialConfig? serialConfig,
    int? rtuAddress,
    String? bindAddress,
    int? tcpPort,
  }) =>
      SlaveConfig(
        mode: mode ?? this.mode,
        serialConfig: serialConfig ?? this.serialConfig,
        rtuAddress: rtuAddress ?? this.rtuAddress,
        bindAddress: bindAddress ?? this.bindAddress,
        tcpPort: tcpPort ?? this.tcpPort,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'serialConfig': serialConfig?.toJson(),
        'rtuAddress': rtuAddress,
        'bindAddress': bindAddress,
        'tcpPort': tcpPort,
      };

  factory SlaveConfig.fromJson(Map<String, dynamic> json) => SlaveConfig(
        mode: ModbusTransportMode.values.firstWhere(
          (e) => e.name == json['mode'],
          orElse: () => ModbusTransportMode.tcp,
        ),
        serialConfig: json['serialConfig'] is Map
            ? SerialConfig.fromJson(
                (json['serialConfig'] as Map).cast<String, dynamic>())
            : null,
        rtuAddress: (json['rtuAddress'] as num?)?.toInt() ?? 1,
        bindAddress: json['bindAddress'] as String? ?? '',
        tcpPort: (json['tcpPort'] as num?)?.toInt() ?? 502,
      );
}

/// Modbus 从机控制器：接收请求 → 查寄存器库 → 回响应 / 异常。
class ModbusSlaveController extends ChangeNotifier {
  ModbusSlaveController({SlaveConfig? config, ModbusRegisterBank? bank})
      : _config = config ?? const SlaveConfig(),
        bank = bank ?? ModbusRegisterBank();

  SlaveConfig _config;
  SlaveConfig get config => _config;

  final ModbusRegisterBank bank;

  bool _running = false;
  bool get isRunning => _running;
  String? lastError;

  final List<DebugLogEntry> logs = [];
  int requestCount = 0;
  int responseCount = 0;

  ModbusRtuChannel? _rtuChannel;
  ModbusTcpServer? _tcpServer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  static const int _maxLogEntries = 5000;

  void updateConfig(SlaveConfig config) {
    if (_running) return;
    _config = config;
    notifyListeners();
  }

  Future<void> start() async {
    lastError = null;
    try {
      if (_config.mode == ModbusTransportMode.rtu) {
        final serialConfig = _config.serialConfig;
        if (serialConfig == null) {
          throw const FormatException('请选择串口参数');
        }
        final service = SerialPortService();
        final channel = ModbusRtuChannel(
          service: service,
          serialConfig: serialConfig,
        );
        channel.open();
        _rtuChannel = channel;
        _subscriptions.add(channel.frames.listen(_handleRtuFrame));
        _appendLog(DebugLogEntry.system(
            'RTU 从机已启动：地址 ${_config.rtuAddress}，'
            '${serialConfig.portName}（${serialConfig.baudRate}）'));
      } else {
        final server = await ModbusTcpServer.listen(
          bindAddress: _config.bindAddress,
          port: _config.tcpPort,
        );
        _tcpServer = server;
        _appendLog(DebugLogEntry.system(
            'TCP 从机已监听 ${_config.bindAddress.isEmpty ? '0.0.0.0' : _config.bindAddress}'
            ':${_config.tcpPort}'));
        _subscriptions.add(server.onChannel.listen(_handleTcpChannel));
      }
      _running = true;
      notifyListeners();
    } catch (e) {
      lastError = e is StateError ? e.message : '$e';
      _appendLog(DebugLogEntry.system('启动失败：$lastError'));
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _rtuChannel?.close();
    _rtuChannel = null;
    await _tcpServer?.close();
    _tcpServer = null;
    _running = false;
    _appendLog(DebugLogEntry.system('从机已停止'));
    notifyListeners();
  }

  void _handleTcpChannel(ModbusTcpChannel channel) {
    _appendLog(DebugLogEntry.system('TCP 客户端已接入'));
    _subscriptions.add(channel.frames.listen(
      (frame) => _handleTcpFrame(channel, frame),
      onDone: () => _appendLog(DebugLogEntry.system('TCP 客户端已断开')),
    ));
  }

  // --- RTU ---

  void _handleRtuFrame(Uint8List frame) {
    final address = frame[0] & 0xFF;
    final pdu = Uint8List.sublistView(frame, 1, frame.length - 2);

    // 地址不匹配（且非广播）：静默忽略。
    if (address != _config.rtuAddress && address != 0) return;
    final isBroadcast = address == 0;

    _appendLog(DebugLogEntry.receive(frame,
        source: isBroadcast ? '广播 addr 0' : 'addr $address'));
    final responsePdu = _serve(pdu, isBroadcast: isBroadcast);
    if (isBroadcast || responsePdu == null) return;

    final response = ModbusCrc.append([address, ...responsePdu]);
    _rtuChannel?.send(response);
    responseCount++;
    _appendLog(DebugLogEntry.transmit(response));
  }

  // --- TCP ---

  void _handleTcpFrame(ModbusTcpChannel channel, Uint8List frame) {
    final parsed = ModbusTcpFrame.parse(frame);
    _appendLog(DebugLogEntry.receive(frame,
        source: 'unit ${parsed.unitId}'));
    final responsePdu = _serve(parsed.pdu, isBroadcast: false);
    if (responsePdu == null) return;
    final response = ModbusTcpFrame.build(
      transactionId: parsed.transactionId,
      unitId: parsed.unitId,
      pdu: responsePdu,
    );
    channel.send(response);
    responseCount++;
    _appendLog(DebugLogEntry.transmit(response,
        source: 'unit ${parsed.unitId}'));
  }

  /// 处理 PDU 并返回响应 PDU；无法处理（如非法功能码且解析失败）时返回 null。
  Uint8List? _serve(Uint8List pdu, {required bool isBroadcast}) {
    if (pdu.isEmpty) return null;
    final functionCode = pdu[0] & 0xFF;
    final function = ModbusFunction.fromCode(functionCode);
    if (function == null) {
      return Uint8List.fromList([functionCode | 0x80, 0x01]);
    }

    ModbusRequest request;
    try {
      // unitId 仅用于请求对象承载，地址匹配已在传输层处理。
      request = ModbusRequest.decodePdu(0, pdu);
    } on ModbusException catch (e) {
      return Uint8List.fromList([functionCode | 0x80, e.code]);
    }

    // 广播仅允许写命令。
    if (isBroadcast && !function.isWrite) return null;

    requestCount++;

    try {
      final responsePdu = bank.handleRequest(request);
      notifyListeners();
      return responsePdu;
    } on ModbusException catch (e) {
      _appendLog(DebugLogEntry.system('返回异常：${e.message}'));
      return Uint8List.fromList([functionCode | 0x80, e.code]);
    }
  }

  // --- 寄存器编辑（UI 调用）---

  void setCoil(int address, bool value) {
    bank.setCoil(address, value);
    notifyListeners();
  }

  void setDiscreteInput(int address, bool value) {
    bank.setDiscreteInput(address, value);
    notifyListeners();
  }

  void setHoldingRegister(int address, int value) {
    bank.setHoldingRegister(address, value);
    notifyListeners();
  }

  void setInputRegister(int address, int value) {
    bank.setInputRegister(address, value);
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    requestCount = 0;
    responseCount = 0;
    notifyListeners();
  }

  void _appendLog(DebugLogEntry entry) {
    logs.add(entry);
    if (logs.length > _maxLogEntries) {
      logs.removeRange(0, logs.length - _maxLogEntries);
    }
  }

  @override
  void dispose() {
    unawaited(_rtuChannel?.close());
    unawaited(_tcpServer?.close());
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}
