import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ui/quick_command.dart';

/// USB 模块的本地持久化（快捷指令、发送历史、上次打开的设备标识）。
class UsbStore {
  UsbStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _keyQuickCommands = 'usb_quick_commands';
  static const _keySendHistory = 'usb_send_history';
  static const _keyLastHidDevice = 'usb_last_hid_device';
  static const _keyLastRawDevice = 'usb_last_raw_device';

  static Future<UsbStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return UsbStore._(prefs);
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

  // --- 上次打开的设备 ---

  String? loadLastHidDeviceId() => _prefs.getString(_keyLastHidDevice);

  Future<void> saveLastHidDeviceId(String deviceId) =>
      _prefs.setString(_keyLastHidDevice, deviceId);

  String? loadLastRawDeviceId() => _prefs.getString(_keyLastRawDevice);

  Future<void> saveLastRawDeviceId(String deviceId) =>
      _prefs.setString(_keyLastRawDevice, deviceId);
}
