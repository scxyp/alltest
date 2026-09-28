import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../../core/ui/line_ending.dart';
import '../../../core/ui/send_contracts.dart';
import '../../../core/util/data_format.dart';

export '../../../core/ui/debug_log_entry.dart' show friendlyError;

enum BleSessionState { disconnected, connected }

/// 一个 BLE 连接对应一个会话：持有 GATT 服务 / 特征、数据日志、
/// 收发统计与发送选项，并实现 [SendPanelController] 以复用通用发送面板。
///
/// 接收数据采用与 [SerialSession] 一致的静默判帧（30ms 合并）：
/// 多个 notify 包到达时先进入 [_rxBuffer]，静默 [rxSettleMs] 后作为一帧上屏，
/// 避免一帧被拆成逐字节打印。
class BleSession extends ChangeNotifier implements SendPanelController {
  BleSession({required this.id, required this.deviceId, this.name});

  static const int maxLogEntries = 5000;

  // --- 接收合并（静默判帧，与 SerialSession 一致）---
  /// 收到数据后静默 [rxSettleMs] 毫秒再上屏，避免一帧数据被拆成
  /// 一两个字符逐条显示。
  static const int rxSettleMs = 30;
  /// 单条记录的最大合并字节数（连续流式数据时按此上限切分）。
  static const int rxMaxBatchBytes = 4096;
  /// 连续不断的数据流最长合并等待，防止缓冲无限增长。
  static const int rxMaxWaitMs = 200;

  final String id;

  /// 系统分配的设备唯一标识（mac/uuid 等，平台相关）。
  final String deviceId;

  /// 设备广播名（连接成功后由管理器注入，用于日志展示）。
  String? name;

  /// 成功发送后通知管理器记录历史。
  void Function(String content, bool asHex)? onSent;

  BleSessionState _state = BleSessionState.disconnected;
  BleSessionState get state => _state;
  @override
  bool get isConnected => _state == BleSessionState.connected;

  String? lastError;

  // --- GATT ---

  /// 最近一次服务发现得到的服务列表。
  List<BleService> _services = const [];
  List<BleService> get services => _services;

  /// 当前选定的可写特征所属服务 UUID。
  String? selectedServiceId;
  /// 当前选定的可写特征 UUID。
  String? selectedCharacteristicId;

  /// 发送时是否使用 withoutResponse 模式（根据所选特征属性自动判断，
  /// 也可由 UI 手动覆盖）。
  bool sendWithoutResponse = false;

  /// Notify / Indicate 订阅句柄，键为特征 UUID（与 universal_ble 内部
  /// CacheHandler 的键一致：同设备下特征 UUID 唯一标识订阅）。
  final Map<String, StreamSubscription<Uint8List>> _notifySubs = {};

  StreamSubscription<bool>? _connectionSub;

  // --- 日志 / 统计 ---

  final List<DebugLogEntry> logs = [];
  int rxBytes = 0;
  int txBytes = 0;

  final List<int> _rxBuffer = [];
  int? _rxFirstAtMs;
  Timer? _rxFlushTimer;

  // --- 发送选项（实现 SendPanelController）---
  @override
  bool sendAsHex = false;
  @override
  LineEnding lineEnding = LineEnding.crLf;
  @override
  int loopIntervalMs = 1000;
  @override
  bool loopSending = false;
  Timer? _loopTimer;

  /// 会话建立时间（用于导出文件命名等）。
  DateTime? openedAt;

  /// UI 显示名：优先广播名，否则退回 deviceId。
  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : deviceId;

  // --- 连接 ---

  Future<void> connect() async {
    if (isConnected) return;
    lastError = null;
    try {
      // 先订阅连接状态流，捕获对端主动断开等场景。
      _connectionSub = UniversalBle.connectionStream(deviceId).listen(
        _onConnectionChanged,
        onError: (Object e) {
          _markDisconnected('连接异常：${friendlyError(e)}');
        },
      );
      await UniversalBle.connect(deviceId);
      _state = BleSessionState.connected;
      openedAt = DateTime.now();
      _appendLog(DebugLogEntry.system('已连接 $displayName'));
      notifyListeners();
      // 连接成功后做服务发现，失败不致命（用户可手动重试）。
      await _discoverServices();
    } catch (e) {
      final message = friendlyError(e);
      lastError = message;
      _appendLog(DebugLogEntry.system(message));
      notifyListeners();
      rethrow;
    }
  }

  void _onConnectionChanged(bool connected) {
    if (!connected && _state == BleSessionState.connected) {
      _markDisconnected('对端已断开');
    }
  }

  Future<void> disconnect() async {
    if (!isConnected && _notifySubs.isEmpty && _connectionSub == null) {
      _state = BleSessionState.disconnected;
      return;
    }
    stopLoopSend();
    _flushRxBuffer();
    await _cancelAllNotifySubs();
    await _connectionSub?.cancel();
    _connectionSub = null;
    try {
      await UniversalBle.disconnect(deviceId);
    } catch (_) {
      // 主动断开时忽略底层异常。
    }
    _state = BleSessionState.disconnected;
    _appendLog(DebugLogEntry.system('已断开 $displayName'));
    notifyListeners();
  }

  // --- 服务发现 ---

  Future<void> _discoverServices() async {
    try {
      final discovered = await UniversalBle.discoverServices(deviceId);
      _services = discovered;
      _autoSelectWritableCharacteristic();
      _appendLog(DebugLogEntry.system(
        '发现 ${_services.length} 个 GATT 服务',
      ));
      notifyListeners();
    } catch (e) {
      _appendLog(DebugLogEntry.system('服务发现失败：${friendlyError(e)}'));
      notifyListeners();
    }
  }

  /// 自动选择第一个可写特征作为默认发送目标，方便用户直接发数。
  void _autoSelectWritableCharacteristic() {
    for (final svc in _services) {
      for (final ch in svc.characteristics) {
        if (_isWritable(ch)) {
          selectedServiceId = svc.uuid;
          selectedCharacteristicId = ch.uuid;
          sendWithoutResponse = _preferWithoutResponse(ch);
          return;
        }
      }
    }
  }

  bool _isWritable(BleCharacteristic ch) =>
      ch.properties.contains(CharacteristicProperty.write) ||
      ch.properties.contains(CharacteristicProperty.writeWithoutResponse);

  /// 同时支持 write / writeWithoutResponse 时优先 withResponse（更可靠）。
  bool _preferWithoutResponse(BleCharacteristic ch) =>
      ch.properties.contains(CharacteristicProperty.writeWithoutResponse) &&
      !ch.properties.contains(CharacteristicProperty.write);

  /// 手动选择发送特征，并根据其属性自动设置 withoutResponse。
  void selectCharacteristic(String serviceId, String charId) {
    selectedServiceId = serviceId;
    selectedCharacteristicId = charId;
    final ch = _findCharacteristic(serviceId, charId);
    if (ch != null) {
      sendWithoutResponse = _preferWithoutResponse(ch);
    }
    notifyListeners();
  }

  BleCharacteristic? _findCharacteristic(String serviceId, String charId) {
    for (final svc in _services) {
      if (svc.uuid == serviceId) {
        for (final ch in svc.characteristics) {
          if (ch.uuid == charId) return ch;
        }
      }
    }
    return null;
  }

  /// 当前选定的特征对象（可能为空）。
  BleCharacteristic? get selectedCharacteristic =>
      (selectedServiceId != null && selectedCharacteristicId != null)
          ? _findCharacteristic(selectedServiceId!, selectedCharacteristicId!)
          : null;

  // --- Notify 订阅 ---

  /// 订阅指定特征的通知（[indication] 为 true 时改用 indicate）。
  /// 订阅成功后通过 [characteristicValueStream] 接收数据，进入静默判帧。
  Future<void> subscribeNotify(
    String serviceId,
    String charId, {
    bool indication = false,
  }) async {
    final key = charId;
    if (_notifySubs.containsKey(key)) return;
    try {
      if (indication) {
        await UniversalBle.subscribeIndications(deviceId, serviceId, charId);
      } else {
        await UniversalBle.subscribeNotifications(deviceId, serviceId, charId);
      }
      final sub =
          UniversalBle.characteristicValueStream(deviceId, charId).listen(
        _onDataReceived,
        onError: (Object e) {
          _appendLog(DebugLogEntry.system('Notify 异常：${friendlyError(e)}'));
          notifyListeners();
        },
      );
      _notifySubs[key] = sub;
      _appendLog(DebugLogEntry.system(
        '已订阅 ${indication ? "Indicate" : "Notify"} $charId',
      ));
      notifyListeners();
    } catch (e) {
      _appendLog(DebugLogEntry.system('订阅 $charId 失败：${friendlyError(e)}'));
      notifyListeners();
    }
  }

  /// 取消订阅指定特征。
  Future<void> unsubscribeNotify(String serviceId, String charId) async {
    final key = charId;
    final sub = _notifySubs.remove(key);
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    try {
      await UniversalBle.unsubscribe(deviceId, serviceId, charId);
    } catch (_) {}
    _appendLog(DebugLogEntry.system('已取消订阅 $charId'));
    notifyListeners();
  }

  Future<void> _cancelAllNotifySubs() async {
    for (final sub in _notifySubs.values) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    _notifySubs.clear();
  }

  // --- 发送 ---

  /// 按当前发送模式（HEX / 文本 + 行结束符）发送输入内容。
  @override
  void sendContent(String raw, {required bool asHex}) {
    sendAsHex = asHex;
    final bytes = _encode(raw, asHex);
    if (bytes.isEmpty) {
      throw const FormatException('发送内容为空');
    }
    _ensureWritable();
    unawaited(_writeAndLog(bytes, raw: raw));
  }

  /// 开始按固定间隔循环发送当前输入内容。
  @override
  void startLoopSend(String raw) {
    if (loopSending || !isConnected) return;
    final bytes = _encode(raw, sendAsHex);
    if (bytes.isEmpty) throw const FormatException('发送内容为空');
    _ensureWritable();

    loopSending = true;
    onSent?.call(raw, sendAsHex);
    _loopTimer = Timer.periodic(
      Duration(milliseconds: loopIntervalMs <= 0 ? 1000 : loopIntervalMs),
      (_) async {
        try {
          await _writeAndLog(bytes);
        } catch (_) {
          // _writeAndLog 内部已标记断开，这里兜底停止循环。
          stopLoopSend();
        }
      },
    );
    notifyListeners();
  }

  @override
  void stopLoopSend() {
    _loopTimer?.cancel();
    _loopTimer = null;
    if (loopSending) {
      loopSending = false;
      notifyListeners();
    }
  }

  /// 抛出 [StateError] 提示未选择可写特征，统一前置校验。
  void _ensureWritable() {
    if (!isConnected) {
      throw StateError('BLE 未连接');
    }
    if (selectedServiceId == null || selectedCharacteristicId == null) {
      throw StateError('未选择可写特征');
    }
  }

  Uint8List _encode(String raw, bool asHex) {
    if (asHex) return DataFormat.hexToBytes(raw);
    return DataFormat.textToBytes(raw + lineEnding.suffix);
  }

  Future<void> _writeAndLog(Uint8List bytes, {String? raw}) async {
    if (!isConnected) {
      throw StateError('BLE 未连接');
    }
    final serviceId = selectedServiceId;
    final charId = selectedCharacteristicId;
    if (serviceId == null || charId == null) {
      throw StateError('未选择可写特征');
    }
    try {
      await UniversalBle.write(
        deviceId,
        serviceId,
        charId,
        bytes,
        withoutResponse: sendWithoutResponse,
      );
    } catch (e) {
      // 写入失败基本意味着底层连接已失效，标记断开避免状态错位。
      final message = friendlyError(e);
      _markDisconnected('连接已断开：$message');
      throw StateError(message);
    }
    txBytes += bytes.length;
    _appendLog(DebugLogEntry.transmit(bytes));
    if (raw != null) onSent?.call(raw, sendAsHex);
    notifyListeners();
  }

  // --- 接收 ---

  /// 原始数据先进入合并缓冲，静默 [rxSettleMs] 后作为一帧上屏。
  void _onDataReceived(Uint8List data) {
    if (data.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _rxFirstAtMs ??= now;
    _rxBuffer.addAll(data);

    final waited = now - _rxFirstAtMs!;
    if (_rxBuffer.length >= rxMaxBatchBytes || waited >= rxMaxWaitMs) {
      _flushRxBuffer();
    } else {
      // 每次收到新数据都重置静默计时器，实现"等最后一字节后再打印"。
      _rxFlushTimer?.cancel();
      _rxFlushTimer =
          Timer(const Duration(milliseconds: rxSettleMs), _flushRxBuffer);
    }
  }

  void _flushRxBuffer() {
    _rxFlushTimer?.cancel();
    _rxFlushTimer = null;
    if (_rxBuffer.isEmpty) {
      _rxFirstAtMs = null;
      return;
    }
    final bytes = Uint8List.fromList(_rxBuffer);
    _rxBuffer.clear();
    _rxFirstAtMs = null;
    rxBytes += bytes.length;
    _appendLog(DebugLogEntry.receive(bytes));
    notifyListeners();
  }

  /// 统一的"连接已中断"处理，幂等：重复调用不会产生重复日志。
  void _markDisconnected(String reason) {
    if (_state == BleSessionState.disconnected) return;
    stopLoopSend();
    _flushRxBuffer();
    unawaited(_cancelAllNotifySubs());
    unawaited(_connectionSub?.cancel());
    _connectionSub = null;
    try {
      unawaited(UniversalBle.disconnect(deviceId));
    } catch (_) {}
    lastError = reason;
    _appendLog(DebugLogEntry.system(reason));
    _state = BleSessionState.disconnected;
    notifyListeners();
  }

  // --- 日志 ---

  /// 向日志追加一条接收记录（供 UI 的读取特征操作调用）。
  void appendReceiveLog(Uint8List data, {String? source}) {
    rxBytes += data.length;
    _appendLog(DebugLogEntry.receive(data, source: source));
    notifyListeners();
  }

  /// 向日志追加一条系统记录。
  void appendSystemLog(String message) {
    _appendLog(DebugLogEntry.system(message));
    notifyListeners();
  }

  void _appendLog(DebugLogEntry entry) {
    logs.add(entry);
    if (logs.length > maxLogEntries) {
      logs.removeRange(0, logs.length - maxLogEntries);
    }
  }

  void clearLogs() {
    _rxFlushTimer?.cancel();
    _rxFlushTimer = null;
    _rxBuffer.clear();
    _rxFirstAtMs = null;
    logs.clear();
    rxBytes = 0;
    txBytes = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _rxFlushTimer?.cancel();
    unawaited(_cancelAllNotifySubs());
    unawaited(_connectionSub?.cancel());
    _connectionSub = null;
    try {
      unawaited(UniversalBle.disconnect(deviceId));
    } catch (_) {}
    super.dispose();
  }
}
