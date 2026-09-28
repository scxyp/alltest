import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../serial/data/serial_port_service.dart';
import '../../serial/domain/serial_config.dart';
import '../data/modbus_channels.dart';
import '../domain/modbus_crc.dart';
import '../domain/modbus_pdu.dart';

export '../../../core/ui/debug_log_entry.dart' show friendlyError;

/// 主机轮询表中的一条请求项。
class MasterPollItem {
  MasterPollItem({
    required this.id,
    required this.name,
    required this.unitId,
    required this.function,
    required this.startAddress,
    this.quantity = 1,
    this.values = const [],
    this.enabled = true,
    this.lastResult,
    this.lastError,
    this.lastTime,
  });

  final String id;
  String name;
  int unitId;
  ModbusFunction function;
  int startAddress;
  int quantity;

  /// 写操作的数据（FC5/6 取首个；FC15/16 用全部）。
  List<int> values;

  bool enabled;

  ModbusResponse? lastResult;
  String? lastError;
  DateTime? lastTime;

  ModbusRequest toRequest() => ModbusRequest(
        unitId: unitId,
        function: function,
        startAddress: startAddress,
        quantity: quantity,
        values: values,
      );

  /// 最近一次结果的简短文本（用于轮询表预览）。
  String get resultPreview {
    if (lastError != null) return lastError!;
    final r = lastResult;
    if (r == null || lastTime == null) return '—';
    if (r.isException) {
      return '异常：${ModbusExceptionCode.labelOf(r.exceptionCode ?? 0)}';
    }
    if (r.bits.isNotEmpty) {
      return r.bits.map((b) => b == 0 ? '0' : '1').join();
    }
    if (r.registers.isNotEmpty) {
      return r.registers
          .map((v) => v.toRadixString(16).padLeft(4, '0'))
          .join(' ');
    }
    return 'OK';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'unitId': unitId,
        'function': function.code,
        'startAddress': startAddress,
        'quantity': quantity,
        'values': values,
        'enabled': enabled,
      };

  factory MasterPollItem.fromJson(Map<String, dynamic> json) => MasterPollItem(
        id: json['id'] as String,
        name: json['name'] as String? ?? '请求',
        unitId: (json['unitId'] as num?)?.toInt() ?? 1,
        function:
            ModbusFunction.fromCode((json['function'] as num?)?.toInt() ?? 3) ??
                ModbusFunction.readHoldingRegisters,
        startAddress: (json['startAddress'] as num?)?.toInt() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        values:
            (json['values'] as List?)?.map((e) => (e as num).toInt()).toList() ??
                const [],
        enabled: json['enabled'] as bool? ?? true,
      );
}

/// 主机连接参数。
class MasterConfig {
  const MasterConfig({
    this.mode = ModbusTransportMode.tcp,
    this.serialConfig,
    this.host = '127.0.0.1',
    this.port = 502,
    this.timeoutMs = 1000,
    this.pollIntervalMs = 1000,
  });

  final ModbusTransportMode mode;
  final SerialConfig? serialConfig;
  final String host;
  final int port;
  final int timeoutMs;
  final int pollIntervalMs;

  MasterConfig copyWith({
    ModbusTransportMode? mode,
    SerialConfig? serialConfig,
    String? host,
    int? port,
    int? timeoutMs,
    int? pollIntervalMs,
  }) =>
      MasterConfig(
        mode: mode ?? this.mode,
        serialConfig: serialConfig ?? this.serialConfig,
        host: host ?? this.host,
        port: port ?? this.port,
        timeoutMs: timeoutMs ?? this.timeoutMs,
        pollIntervalMs: pollIntervalMs ?? this.pollIntervalMs,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'serialConfig': serialConfig?.toJson(),
        'host': host,
        'port': port,
        'timeoutMs': timeoutMs,
        'pollIntervalMs': pollIntervalMs,
      };

  factory MasterConfig.fromJson(Map<String, dynamic> json) => MasterConfig(
        mode: ModbusTransportMode.values.firstWhere(
          (e) => e.name == json['mode'],
          orElse: () => ModbusTransportMode.tcp,
        ),
        serialConfig: json['serialConfig'] is Map
            ? SerialConfig.fromJson(
                (json['serialConfig'] as Map).cast<String, dynamic>())
            : null,
        host: json['host'] as String? ?? '127.0.0.1',
        port: (json['port'] as num?)?.toInt() ?? 502,
        timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 1000,
        pollIntervalMs: (json['pollIntervalMs'] as num?)?.toInt() ?? 1000,
      );
}

class _PendingRequest {
  _PendingRequest({required this.matcher, required this.completer});

  final bool Function(Uint8List frame) matcher;
  final Completer<Uint8List> completer;
  Timer? timer;
}

/// Modbus 主机控制器：连接管理、请求执行（事务匹配 + 超时）、轮询调度。
class ModbusMasterController extends ChangeNotifier {
  ModbusMasterController({MasterConfig? config})
      : _config = config ?? const MasterConfig();

  MasterConfig _config;
  MasterConfig get config => _config;

  bool _connected = false;
  bool get isConnected => _connected;
  String? lastError;

  final List<DebugLogEntry> logs = [];
  int txFrames = 0;
  int rxFrames = 0;

  final List<MasterPollItem> pollItems = [];
  bool polling = false;

  ModbusChannel? _channel;
  StreamSubscription<Uint8List>? _frameSub;
  _PendingRequest? _pending;
  Timer? _pollTimer;
  int _pollCursor = 0;
  int _tcpTxnId = 1;
  bool _executing = false;

  static const int _maxLogEntries = 5000;

  void updateConfig(MasterConfig config) {
    if (_connected) return;
    _config = config;
    notifyListeners();
  }

  Future<void> connect() async {
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
        _channel = channel;
      } else {
        _channel = await ModbusTcpChannel.connect(_config.host, _config.port);
      }
      _frameSub = _channel!.frames.listen(
        _onFrame,
        onDone: _onTransportClosed,
        onError: (Object e) => _onTransportClosed(),
      );
      _connected = true;
      _appendLog(DebugLogEntry.system(_connectionSummary));
      notifyListeners();
    } catch (e) {
      lastError = friendlyError(e);
      _appendLog(DebugLogEntry.system('连接失败：${friendlyError(e)}'));
      notifyListeners();
      rethrow;
    }
  }

  String get _connectionSummary => _config.mode == ModbusTransportMode.rtu
      ? 'RTU 已打开 ${_config.serialConfig?.portName} '
          '(${_config.serialConfig?.baudRate})'
      : 'TCP 已连接 ${_config.host}:${_config.port}';

  Future<void> disconnect() async {
    stopPolling();
    _pending?.timer?.cancel();
    if (_pending != null && !_pending!.completer.isCompleted) {
      _pending!.completer.completeError(StateError('连接已断开'));
    }
    _pending = null;
    await _frameSub?.cancel();
    await _channel?.close();
    _channel = null;
    _connected = false;
    _appendLog(DebugLogEntry.system('连接已断开'));
    notifyListeners();
  }

  // --- 单次请求执行 ---

  Future<void> execute(MasterPollItem item) async {
    if (!_connected || _channel == null) {
      throw StateError('主机未连接');
    }
    if (_executing) return; // 串行化，避免事务交叉。
    _executing = true;
    final request = item.toRequest();
    final pdu = request.encodePdu();
    final isBroadcast =
        _config.mode == ModbusTransportMode.rtu &&
        item.unitId == 0 &&
        item.function.isWrite;

    try {
      final responseCompleter = Completer<Uint8List>();
      final Uint8List adu;
      final int? tcpTxn;
      if (_config.mode == ModbusTransportMode.rtu) {
        adu = ModbusCrc.append([item.unitId, ...pdu]);
        tcpTxn = null;
      } else {
        final txn = _tcpTxnId++ & 0xFFFF;
        tcpTxn = txn;
        adu = ModbusTcpFrame.build(
          transactionId: txn,
          unitId: item.unitId,
          pdu: pdu,
        );
      }

      if (!isBroadcast) {
        final matcher = _config.mode == ModbusTransportMode.rtu
            ? (Uint8List f) =>
                (f.isNotEmpty &&
                    f[0] == item.unitId &&
                    f.length >= 3 &&
                    ((f[1] & 0x7F) == item.function.code))
            : (Uint8List f) =>
                f.length >= 7 &&
                (((f[0] & 0xFF) << 8) | (f[1] & 0xFF)) == tcpTxn;
        final pending =
            _PendingRequest(matcher: matcher, completer: responseCompleter);
        pending.timer = Timer(
          Duration(milliseconds: _config.timeoutMs),
          () {
            if (!responseCompleter.isCompleted) {
              responseCompleter.completeError(
                  TimeoutException('响应超时（${_config.timeoutMs}ms）'));
            }
          },
        );
        _pending = pending;
      }

      _channel!.send(adu);
      txFrames++;
      _appendLog(DebugLogEntry.transmit(adu));

      if (isBroadcast) {
        item
          ..lastError = null
          ..lastResult = null
          ..lastTime = DateTime.now();
        notifyListeners();
        return;
      }

      final respAdu = await responseCompleter.future.whenComplete(() {
        _pending?.timer?.cancel();
        _pending = null;
      });
      rxFrames++;
      _appendLog(DebugLogEntry.receive(respAdu));

      final Uint8List respPdu;
      if (_config.mode == ModbusTransportMode.rtu) {
        respPdu = Uint8List.sublistView(respAdu, 1, respAdu.length - 2);
      } else {
        respPdu = ModbusTcpFrame.parse(respAdu).pdu;
      }
      final response = ModbusResponse.decode(request, respPdu);
      item
        ..lastResult = response
        ..lastError = response.isException
            ? '异常：${ModbusExceptionCode.labelOf(response.exceptionCode ?? 0)}'
            : null
        ..lastTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      final message = friendlyError(e);
      item
        ..lastError = message
        ..lastTime = DateTime.now();
      _appendLog(DebugLogEntry.system('${item.name}：$message'));
      notifyListeners();
      rethrow;
    } finally {
      _executing = false;
    }
  }

  void _onFrame(Uint8List frame) {
    final pending = _pending;
    if (pending != null &&
        !pending.completer.isCompleted &&
        pending.matcher(frame)) {
      pending.timer?.cancel();
      pending.completer.complete(frame);
    }
  }

  /// TCP 对端断开 / 传输异常时自动转为未连接状态。
  void _onTransportClosed() {
    if (!_connected) return;
    stopPolling();
    if (_pending != null && !_pending!.completer.isCompleted) {
      _pending!.completer
          .completeError(StateError('连接已被远端关闭'));
    }
    _pending?.timer?.cancel();
    _pending = null;
    _connected = false;
    _executing = false;
    unawaited(_frameSub?.cancel());
    unawaited(_channel?.close());
    _channel = null;
    _appendLog(DebugLogEntry.system('连接已被远端关闭'));
    notifyListeners();
  }

  // --- 轮询调度 ---

  void startPolling() {
    if (polling || !_connected) return;
    if (pollItems.every((i) => !i.enabled)) return;
    polling = true;
    _pollCursor = 0;
    _pollTimer = Timer.periodic(
      Duration(
          milliseconds: _config.pollIntervalMs <= 0
              ? 1000
              : _config.pollIntervalMs),
      (_) => _pollTick(),
    );
    notifyListeners();
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (polling) {
      polling = false;
      notifyListeners();
    }
  }

  Future<void> _pollTick() async {
    if (_executing) return;
    final enabled = pollItems.where((i) => i.enabled).toList();
    if (enabled.isEmpty) {
      stopPolling();
      return;
    }
    if (_pollCursor >= enabled.length) _pollCursor = 0;
    final item = enabled[_pollCursor++];
    try {
      await execute(item);
    } catch (_) {
      // 错误已记录在条目上；连续失败时继续轮询下一条。
    }
  }

  // --- 轮询表增删改 ---

  void addPollItem(MasterPollItem item) {
    pollItems.add(item);
    notifyListeners();
  }

  void updatePollItem(MasterPollItem item) {
    notifyListeners();
  }

  void removePollItem(String id) {
    pollItems.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  String newItemId() => 'mbi_${DateTime.now().microsecondsSinceEpoch}';

  void clearLogs() {
    logs.clear();
    txFrames = 0;
    rxFrames = 0;
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
    _pollTimer?.cancel();
    _pending?.timer?.cancel();
    unawaited(_frameSub?.cancel());
    unawaited(_channel?.close());
    super.dispose();
  }
}
