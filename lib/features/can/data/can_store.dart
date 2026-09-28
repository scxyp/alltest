import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ui/quick_command.dart';
import '../domain/can_config.dart';

/// CAN 模块的本地持久化（快捷指令、发送历史、上次连接参数）。
class CanStore {
  CanStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _keyQuickCommands = 'can_quick_commands';
  static const _keySendHistory = 'can_send_history';
  static const _keyLastConfig = 'can_last_config';

  static Future<CanStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return CanStore._(prefs);
  }

  // --- 快捷指令 ---

  List<QuickCommand> loadQuickCommands() {
    return _decodeList(_keyQuickCommands)
        .map((e) => QuickCommand.fromJson(e))
        .toList();
  }

  Future<void> saveQuickCommands(List<QuickCommand> commands) =>
      _encodeAndSave(
        _keyQuickCommands,
        commands.map((c) => c.toJson()).toList(),
      );

  // --- 发送历史 ---

  List<SendHistoryItem> loadSendHistory() {
    return _decodeList(_keySendHistory)
        .map((e) => SendHistoryItem.fromJson(e))
        .toList();
  }

  Future<void> saveSendHistory(List<SendHistoryItem> history) =>
      _encodeAndSave(
        _keySendHistory,
        history.map((h) => h.toJson()).toList(),
      );

  // --- 上次连接参数 ---

  CanConfig? loadLastConfig() {
    final raw = _prefs.getString(_keyLastConfig);
    if (raw == null || raw.isEmpty) return null;
    try {
      return CanConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastConfig(CanConfig config) =>
      _prefs.setString(_keyLastConfig, jsonEncode(config.toJson()));

  // --- 内部工具 ---

  List<Map<String, dynamic>> _decodeList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _encodeAndSave(String key, Object value) =>
      _prefs.setString(key, jsonEncode(value));
}
