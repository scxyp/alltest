import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/quick_command.dart';
import '../../../core/ui/send_contracts.dart';
import '../data/net_store.dart';
import '../data/network_info_service.dart';
import 'net_config.dart';
import 'net_session.dart';

/// 管理多个并行网络会话、网卡列表以及跨会话共享的快捷指令 / 发送历史。
class NetSessionManager extends ChangeNotifier implements QuickCommandStore {
  NetSessionManager._(this._store);

  final NetStore _store;

  static const int historyLimit = 30;

  /// 最多同时打开的网络会话数（与串口一致）。
  static const int maxSessions = 4;

  final List<NetSession> sessions = [];

  /// 当前枚举到的网卡（含 IPv4 地址）。
  List<NetInterfaceInfo> interfaces = const [];

  @override
  List<QuickCommand> quickCommands = [];
  @override
  List<SendHistoryItem> history = [];

  int _sessionSeq = 0;

  static Future<NetSessionManager> create() async {
    final store = await NetStore.create();
    final manager = NetSessionManager._(store);
    manager.quickCommands = store.loadQuickCommands();
    manager.history = store.loadSendHistory();
    await manager.refreshInterfaces();
    return manager;
  }

  /// 枚举本机网卡，供连接对话框选择网口 / 自动识别 IP。
  Future<void> refreshInterfaces() async {
    try {
      interfaces = await NetworkInfoService.list();
      notifyListeners();
    } catch (_) {
      // 枚举失败保留旧列表。
    }
  }

  NetConfig? get lastConfig => _store.loadLastConfig();

  /// 创建会话并立即连接；会话数达上限时抛出 [StateError]。
  Future<NetSession> openSession(NetConfig config) async {
    if (sessions.length >= maxSessions) {
      throw StateError('最多支持同时打开 $maxSessions 个网络会话');
    }
    final session = NetSession(
      config,
      id: 'net_${DateTime.now().microsecondsSinceEpoch}_${_sessionSeq++}',
    );
    session.onSent = _recordHistory;
    sessions.add(session);
    notifyListeners();
    try {
      await session.connect();
      unawaited(_store.saveLastConfig(config));
    } catch (_) {
      // 连接失败也保留会话（用户可改参数重连），不自动移除。
    }
    return session;
  }

  Future<void> closeSession(String id) async {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final session = sessions.removeAt(index);
    await session.disconnect();
    session.dispose();
    notifyListeners();
  }

  void _recordHistory(String content, bool asHex) {
    history.removeWhere(
      (item) => item.content == content && item.asHex == asHex,
    );
    history.insert(
      0,
      SendHistoryItem(content: content, asHex: asHex, time: DateTime.now()),
    );
    if (history.length > historyLimit) {
      history.removeRange(historyLimit, history.length);
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
      'netcmd_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _persistQuickCommands() async {
    final snapshot = List<QuickCommand>.from(quickCommands);
    await _store.saveQuickCommands(snapshot);
    notifyListeners();
  }
}
