import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ui/quick_command.dart';
import '../domain/net_config.dart';

/// 网络模块的本地持久化（快捷指令、发送历史、上次连接参数）。
class NetStore {
  NetStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _keyQuickCommands = 'net_quick_commands';
  static const _keySendHistory = 'net_send_history';
  static const _keyLastConfig = 'net_last_config';

  static Future<NetStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return NetStore._(prefs);
  }

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

  NetConfig? loadLastConfig() {
    final raw = _prefs.getString(_keyLastConfig);
    if (raw == null || raw.isEmpty) return null;
    try {
      return NetConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastConfig(NetConfig config) =>
      _prefs.setString(_keyLastConfig, jsonEncode(config.toJson()));

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
