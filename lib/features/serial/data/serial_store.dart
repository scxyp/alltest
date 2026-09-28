import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ui/quick_command.dart';
import '../domain/serial_config.dart';

/// 串口模块的本地持久化（快捷指令、发送历史、上次连接参数）。
class SerialStore {
  SerialStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _keyQuickCommands = 'serial_quick_commands';
  static const _keySendHistory = 'serial_send_history';
  static const _keyLastConfig = 'serial_last_config';

  static Future<SerialStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SerialStore._(prefs);
  }

  // --- 快捷指令 ---

  List<QuickCommand> loadQuickCommands() {
    final raw = _prefs.getString(_keyQuickCommands);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => QuickCommand.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveQuickCommands(List<QuickCommand> commands) {
    final raw = jsonEncode(commands.map((c) => c.toJson()).toList());
    return _prefs.setString(_keyQuickCommands, raw);
  }

  // --- 发送历史 ---

  List<SendHistoryItem> loadSendHistory() {
    final raw = _prefs.getString(_keySendHistory);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SendHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSendHistory(List<SendHistoryItem> history) {
    final raw = jsonEncode(history.map((h) => h.toJson()).toList());
    return _prefs.setString(_keySendHistory, raw);
  }

  // --- 上次连接参数 ---

  SerialConfig? loadLastConfig() {
    final raw = _prefs.getString(_keyLastConfig);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SerialConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastConfig(SerialConfig config) {
    return _prefs.setString(_keyLastConfig, jsonEncode(config.toJson()));
  }
}
