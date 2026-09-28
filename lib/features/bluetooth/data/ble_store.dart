import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ui/quick_command.dart';

/// BLE 模块的本地持久化（快捷指令、发送历史、上次连接设备 ID）。
///
/// 与串口模块 [SerialStore] 不同：BLE 不需要保存完整连接配置，
/// 只记录上次连接的 deviceId（系统分配的字符串标识）。
class BleStore {
  BleStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _keyQuickCommands = 'ble_quick_commands';
  static const _keySendHistory = 'ble_send_history';
  static const _keyLastDeviceId = 'ble_last_device_id';

  static Future<BleStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return BleStore._(prefs);
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

  // --- 上次连接设备 ID ---

  String? loadLastDeviceId() => _prefs.getString(_keyLastDeviceId);

  Future<void> saveLastDeviceId(String deviceId) =>
      _prefs.setString(_keyLastDeviceId, deviceId);
}
