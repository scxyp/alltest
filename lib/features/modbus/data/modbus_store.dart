import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/modbus_master_controller.dart';
import '../domain/modbus_register_bank.dart';
import '../domain/modbus_slave_controller.dart';

/// Modbus 模块本地持久化：主 / 从连接参数、主机轮询表、从机寄存器。
class ModbusStore {
  ModbusStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _keyMasterConfig = 'modbus_master_config';
  static const _keyPollItems = 'modbus_poll_items';
  static const _keySlaveConfig = 'modbus_slave_config';
  static const _keySlaveBank = 'modbus_slave_bank';

  static Future<ModbusStore> create() async {
    return ModbusStore._(await SharedPreferences.getInstance());
  }

  // --- 主机 ---

  MasterConfig? loadMasterConfig() =>
      _loadJson(_keyMasterConfig, MasterConfig.fromJson);

  Future<void> saveMasterConfig(MasterConfig config) =>
      _saveJson(_keyMasterConfig, config.toJson());

  List<MasterPollItem> loadPollItems() {
    final raw = _prefs.getString(_keyPollItems);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) =>
              MasterPollItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePollItems(List<MasterPollItem> items) =>
      _prefs.setString(
        _keyPollItems,
        jsonEncode(items.map((i) => i.toJson()).toList()),
      );

  // --- 从机 ---

  SlaveConfig? loadSlaveConfig() =>
      _loadJson(_keySlaveConfig, SlaveConfig.fromJson);

  Future<void> saveSlaveConfig(SlaveConfig config) =>
      _saveJson(_keySlaveConfig, config.toJson());

  ModbusRegisterBank? loadSlaveBank() {
    final raw = _prefs.getString(_keySlaveBank);
    if (raw == null || raw.isEmpty) return null;
    try {
      return ModbusRegisterBank.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSlaveBank(ModbusRegisterBank bank) =>
      _saveJson(_keySlaveBank, bank.toJson());

  T? _loadJson<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveJson(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));
}
