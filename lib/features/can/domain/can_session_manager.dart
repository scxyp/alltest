import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/quick_command.dart';
import '../../../core/ui/send_contracts.dart';
import '../data/can_port_service.dart';
import '../data/can_store.dart';
import 'can_config.dart';
import 'can_session.dart';

/// 管理多个并行 CAN 会话以及跨会话共享的快捷指令 / 发送历史。
class CanSessionManager extends ChangeNotifier implements QuickCommandStore {
  CanSessionManager._(this._store);

  final CanStore _store;

  static const int historyLimit = 30;

  /// 最多同时打开的 CAN 会话数（与其它模块一致）。
  static const int maxSessions = 4;

  final List<CanSession> sessions = [];
  String? activeSessionId;

  List<String> availablePorts = const [];

  @override
  List<QuickCommand> quickCommands = [];
  @override
  List<SendHistoryItem> history = [];

  int _sessionSeq = 0;

  static Future<CanSessionManager> create() async {
    final store = await CanStore.create();
    final manager = CanSessionManager._(store);
    manager.quickCommands = store.loadQuickCommands();
    manager.history = store.loadSendHistory();
    manager.refreshPorts();
    return manager;
  }

  CanSession? get activeSession {
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return sessions.isEmpty ? null : sessions.first;
  }

  /// 当前已被会话占用的端口名。
  Set<String> get busyPorts =>
      sessions.map((s) => s.config.portName).toSet();

  CanConfig? get lastConfig => _store.loadLastConfig();

  void refreshPorts() {
    List<String>? ports;
    try {
      ports = CanPortService.availablePorts;
    } catch (_) {
      ports = null;
    }
    if (ports == null) return;
    final changed = !listEquals(ports, availablePorts);
    availablePorts = ports;

    // 检测已连接会话的设备是否被外部拔出。
    for (final session in List<CanSession>.of(sessions)) {
      if (session.isConnected && !ports.contains(session.config.portName)) {
        session.onDeviceRemoved();
      }
    }
    if (changed) notifyListeners();
  }

  /// 创建会话并立即连接。
  ///
  /// 端口已被占用或会话数达到上限时抛出 [StateError]。
  Future<CanSession> openSession(CanConfig config) async {
    if (sessions.length >= maxSessions) {
      throw StateError('最多支持同时打开 $maxSessions 个 CAN 会话');
    }
    if (busyPorts.contains(config.portName)) {
      throw StateError('${config.portName} 已在另一个会话中打开');
    }

    _sessionSeq++;
    final session = CanSession(
      id: 'can_${DateTime.now().microsecondsSinceEpoch}_$_sessionSeq',
      config: config,
    );
    session.onSent = _recordHistory;

    sessions.add(session);
    activeSessionId = session.id;
    notifyListeners();

    unawaited(_store.saveLastConfig(config));

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
      'cancmd_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _persistQuickCommands() async {
    final snapshot = List<QuickCommand>.from(quickCommands);
    await _store.saveQuickCommands(snapshot);
    notifyListeners();
  }
}
