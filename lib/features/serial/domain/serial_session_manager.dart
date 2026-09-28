import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/quick_command.dart';
import '../../../core/ui/send_contracts.dart';
import '../data/serial_port_service.dart';
import '../data/serial_store.dart';
import 'serial_config.dart';
import 'serial_session.dart';

/// 管理多个并行串口会话、可用端口列表以及跨会话共享的快捷指令 / 发送历史。
class SerialSessionManager extends ChangeNotifier
    implements QuickCommandStore {
  SerialSessionManager._(this._store);

  final SerialStore _store;

  static const int historyLimit = 30;

  /// 最多同时打开的串口会话数。
  static const int maxSessions = 4;

  final List<SerialSession> sessions = [];
  String? activeSessionId;

  List<String> availablePorts = const [];

  @override
  List<QuickCommand> quickCommands = [];
  @override
  List<SendHistoryItem> history = [];

  int _sessionSeq = 0;

  static Future<SerialSessionManager> create() async {
    final store = await SerialStore.create();
    final manager = SerialSessionManager._(store);
    manager.quickCommands = store.loadQuickCommands();
    manager.history = store.loadSendHistory();
    manager.refreshPorts();
    return manager;
  }

  SerialSession? get activeSession {
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return sessions.isEmpty ? null : sessions.first;
  }

  /// 当前已被会话占用的端口名。
  Set<String> get busyPorts =>
      sessions.map((s) => s.config.portName).toSet();

  SerialConfig? get lastConfig => _store.loadLastConfig();

  void refreshPorts() {
    List<String>? ports;
    try {
      ports = SerialPortService.availablePorts;
    } catch (_) {
      // 枚举失败：保留旧列表，不做拔出判定，避免误断开所有会话。
      ports = null;
    }
    if (ports == null) return;
    final changed = !listEquals(ports, availablePorts);
    availablePorts = ports;

    // 检测已连接会话的设备是否被外部拔出。
    // 拔线后 Windows 的 ClearCommError 往往仍返回"成功"（0 字节），
    // 轮询收不到任何异常，只能以"端口从系统枚举中消失"作为拔出信号。
    for (final session in List<SerialSession>.of(sessions)) {
      if (session.isConnected && !ports.contains(session.config.portName)) {
        session.onDeviceRemoved();
      }
    }
    if (changed) notifyListeners();
  }

  /// 创建会话并立即连接。
  ///
  /// 端口已被占用或会话数达到上限时抛出 [StateError]。
  Future<SerialSession> openSession(SerialConfig config) async {
    if (sessions.length >= maxSessions) {
      throw StateError('最多支持同时打开 $maxSessions 个串口会话');
    }
    if (busyPorts.contains(config.portName)) {
      throw StateError('${config.portName} 已在另一个会话中打开');
    }

    _sessionSeq++;
    final session = SerialSession(
      id: 'session_${DateTime.now().microsecondsSinceEpoch}_$_sessionSeq',
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
      'cmd_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _persistQuickCommands() async {
    final snapshot = List<QuickCommand>.from(quickCommands);
    await _store.saveQuickCommands(snapshot);
    notifyListeners();
  }
}
