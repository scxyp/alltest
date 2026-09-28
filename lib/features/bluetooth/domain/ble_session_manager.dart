import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../../core/ui/quick_command.dart';
import '../../../core/ui/send_contracts.dart';
import '../data/ble_store.dart';
import 'ble_device_info.dart';
import 'ble_session.dart';

/// 管理多个并行 BLE 会话、扫描状态以及跨会话共享的快捷指令 / 发送历史。
class BleSessionManager extends ChangeNotifier implements QuickCommandStore {
  BleSessionManager._(this._store);

  final BleStore _store;

  static const int historyLimit = 30;

  /// 最多同时打开的 BLE 会话数。
  static const int maxSessions = 4;

  final List<BleSession> sessions = [];
  String? activeSessionId;

  // --- 扫描状态 ---
  bool isScanning = false;
  List<BleDeviceInfo> scanResults = [];
  StreamSubscription<BleDevice>? _scanSub;

  @override
  List<QuickCommand> quickCommands = [];
  @override
  List<SendHistoryItem> history = [];

  int _sessionSeq = 0;

  static Future<BleSessionManager> create() async {
    final store = await BleStore.create();
    final manager = BleSessionManager._(store);
    manager.quickCommands = store.loadQuickCommands();
    manager.history = store.loadSendHistory();
    return manager;
  }

  BleSession? get activeSession {
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return sessions.isEmpty ? null : sessions.first;
  }

  /// 当前已被会话占用的 deviceId。
  Set<String> get busyDeviceIds =>
      sessions.map((s) => s.deviceId).toSet();

  /// 上次连接的 deviceId（用于 UI 默认选中 / 一键重连）。
  String? get lastDeviceId => _store.loadLastDeviceId();

  // --- 扫描 ---

  /// 开始扫描 BLE 设备。扫描结果通过 [scanResults] 暴露并自动去重。
  Future<void> startScan() async {
    if (isScanning) return;
    scanResults = [];
    isScanning = true;
    notifyListeners();

    _scanSub = UniversalBle.scanStream.listen(
      _onScanResult,
      onError: (Object e) {
        _appendScanLog('扫描异常：${friendlyError(e)}');
      },
    );

    try {
      await UniversalBle.startScan();
    } catch (e) {
      isScanning = false;
      _scanSub?.cancel();
      _scanSub = null;
      _appendScanLog('启动扫描失败：${friendlyError(e)}');
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    if (!isScanning) return;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    isScanning = false;
    notifyListeners();
  }

  void _onScanResult(BleDevice device) {
    final info = BleDeviceInfo(
      deviceId: device.deviceId,
      name: device.name,
      rssi: device.rssi,
    );
    final index = scanResults.indexWhere((d) => d.deviceId == info.deviceId);
    if (index >= 0) {
      // 已存在则更新（信号强度 / 名称可能变化）。
      scanResults[index] = info.copyWith(
        name: info.name ?? scanResults[index].name,
        rssi: info.rssi ?? scanResults[index].rssi,
      );
    } else {
      scanResults.add(info);
    }
    notifyListeners();
  }

  void _appendScanLog(String message) {
    final session = activeSession;
    if (session != null) {
      session.logs.add(DebugLogEntry.system(message));
      session.notifyListeners();
    }
  }

  // --- 会话管理 ---

  /// 创建会话并立即连接。
  ///
  /// 设备已被占用或会话数达到上限时抛出 [StateError]。
  Future<BleSession> openSession(BleDeviceInfo device) async {
    if (sessions.length >= maxSessions) {
      throw StateError('最多支持同时打开 $maxSessions 个 BLE 会话');
    }
    if (busyDeviceIds.contains(device.deviceId)) {
      throw StateError('${device.displayName} 已在另一个会话中打开');
    }

    _sessionSeq++;
    final session = BleSession(
      id: 'ble_session_${DateTime.now().microsecondsSinceEpoch}_$_sessionSeq',
      deviceId: device.deviceId,
      name: device.name,
    );
    session.onSent = _recordHistory;

    sessions.add(session);
    activeSessionId = session.id;
    notifyListeners();

    unawaited(_store.saveLastDeviceId(device.deviceId));

    try {
      await session.connect();
    } catch (_) {
      // 失败的会话也保留在标签页中，错误信息展示在日志区，用户可重试。
    }
    return session;
  }

  void selectSession(String id) {
    if (activeSessionId == id) return;
    activeSessionId = id;
    notifyListeners();
  }

  Future<void> closeSession(String id) async {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final session = sessions.removeAt(index);
    await session.disconnect();
    session.dispose();

    if (activeSessionId == id) {
      activeSessionId = sessions.isEmpty ? null : sessions.last.id;
    }
    notifyListeners();
  }

  // --- 发送历史 ---

  void _recordHistory(String content, bool asHex) {
    if (content.isEmpty) return;
    history.removeWhere((h) => h.content == content && h.asHex == asHex);
    history.insert(
      0,
      SendHistoryItem(content: content, asHex: asHex, time: DateTime.now()),
    );
    if (history.length > historyLimit) {
      history = history.sublist(0, historyLimit);
    }
    final snapshot = List<SendHistoryItem>.from(history);
    unawaited(_store.saveSendHistory(snapshot));
    notifyListeners();
  }

  @override
  void clearHistory() {
    history.clear();
    unawaited(_store.saveSendHistory(const []));
    notifyListeners();
  }

  // --- 快捷指令 ---

  @override
  Future<void> addQuickCommand(QuickCommand command) async {
    quickCommands.add(command);
    await _persistQuickCommands();
  }

  @override
  Future<void> updateQuickCommand(QuickCommand command) async {
    final index = quickCommands.indexWhere((c) => c.id == command.id);
    if (index >= 0) quickCommands[index] = command;
    await _persistQuickCommands();
  }

  @override
  Future<void> removeQuickCommand(String id) async {
    quickCommands.removeWhere((c) => c.id == id);
    await _persistQuickCommands();
  }

  @override
  String newCommandId() =>
      'cmd_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _persistQuickCommands() async {
    final snapshot = List<QuickCommand>.from(quickCommands);
    await _store.saveQuickCommands(snapshot);
    notifyListeners();
  }
}
