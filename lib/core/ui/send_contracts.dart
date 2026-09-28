import 'package:flutter/foundation.dart';

import 'line_ending.dart';
import 'quick_command.dart';

/// 发送面板对外部会话的控制接口（由各调试模块的会话类实现）。
abstract interface class SendPanelController implements Listenable {
  /// 会话是否已连接（未连接时发送控件禁用）。
  bool get isConnected;

  bool get sendAsHex;
  set sendAsHex(bool value);

  LineEnding get lineEnding;
  set lineEnding(LineEnding value);

  int get loopIntervalMs;
  set loopIntervalMs(int ms);

  bool get loopSending;

  /// 发送内容（[asHex] 指定 HEX / 文本编码模式）。
  void sendContent(String raw, {required bool asHex});

  /// 开始按固定间隔循环发送输入内容。
  void startLoopSend(String raw);

  /// 停止循环发送。
  void stopLoopSend();
}

/// 发送面板对外部指令 / 历史存储的接口（由各调试模块的管理器实现）。
abstract interface class QuickCommandStore implements Listenable {
  List<QuickCommand> get quickCommands;

  List<SendHistoryItem> get history;

  String newCommandId();

  Future<void> addQuickCommand(QuickCommand command);

  Future<void> updateQuickCommand(QuickCommand command);

  Future<void> removeQuickCommand(String id);

  void clearHistory();
}
