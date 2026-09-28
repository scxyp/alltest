import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ui/quick_command.dart';
import '../domain/mqtt_config.dart';

/// MQTT 模块的本地持久化（快捷指令、发送历史、上次连接参数）。
class MqttStore {
  MqttStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _keyQuickCommands = 'mqtt_quick_commands';
  static const _keySendHistory = 'mqtt_send_history';
  static const _keyLastConfig = 'mqtt_last_config';

  static Future<MqttStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return MqttStore._(prefs);
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

  MqttConfig? loadLastConfig() {
    final raw = _prefs.getString(_keyLastConfig);
    if (raw == null || raw.isEmpty) return null;
    try {
      return MqttConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastConfig(MqttConfig config) =>
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
