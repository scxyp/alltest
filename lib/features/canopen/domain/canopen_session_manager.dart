import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/quick_command.dart';
import '../../../core/ui/send_contracts.dart';
import '../../can/data/can_port_service.dart';
import '../data/canopen_store.dart';
import 'canopen_config.dart';
import 'canopen_session.dart';

/// 管理多个并行 CANopen 会话以及跨会话共享的快捷指令 / 发送历史。
class CanOpenSessionManager extends ChangeNotifier implements QuickCommandStore {
  CanOpenSessionManager._(this._store);

  final CanOpenStore _store;

  static const int historyLimit = 30;
  static const int maxSessions = 4;

  final List<CanOpenSession> sessions = [];
  String? activeSessionId;

  List<String> availablePorts = const [];

  @override
  List<QuickCommand> quickCommands = [];
  @override
  List<SendHistoryItem> history = [];

  int _sessionSeq = 0;

  static Future<CanOpenSessionManager> create() async {
    final store = await CanOpenStore.create();
    final manager = CanOpenSessionManager._(store);
    manager.quickCommands = store.loadQuickCommands();
    manager.history = store.loadSendHistory();
    manager.refreshPorts();
    return manager;
  }

  CanOpenSession? get activeSession {
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return sessions.isEmpty ? null : sessions.first;
  }

  Set<String> get busyPorts =>
      sessions.map((s) => s.config.portName).toSet();

  CanOpenConfig? get lastConfig => _store.loadLastConfig();

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

    for (final session in List<CanOpenSession>.of(sessions)) {
      if (session.isConnected && !ports.contains(session.config.portName)) {
        session.onDeviceRemoved();
      }
    }
    if (changed) notifyListeners();
  }

  Future<CanOpenSession> openSession(CanOpenConfig config) async {
    if (sessions.length >= maxSessions) {
      throw StateError('最多支持同时打开 $maxSessions 个 CANopen 会话');
    }
    if (busyPorts.contains(config.portName)) {
      throw StateError('${config.portName} 已在另一个会话中打开');
    }

    _sessionSeq++;
    final session = CanOpenSession(
      id: 'canopen_${DateTime.now().microsecondsSinceEpoch}_$_sessionSeq',
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
      // 连接失败也保留会话（用户可改参数重连）。
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
      'canopencmd_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _persistQuickCommands() async {
    final snapshot = List<QuickCommand>.from(quickCommands);
    await _store.saveQuickCommands(snapshot);
    notifyListeners();
  }
}
