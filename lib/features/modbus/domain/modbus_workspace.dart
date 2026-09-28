import 'dart:async';

import '../data/modbus_store.dart';
import 'modbus_master_controller.dart';
import 'modbus_slave_controller.dart';

/// Modbus 模块工作台：持有主机 / 从机控制器，并负责状态持久化。
class ModbusWorkspace {
  ModbusWorkspace._(this._store, this.master, this.slave);

  final ModbusStore _store;
  final ModbusMasterController master;
  final ModbusSlaveController slave;

  Timer? _bankSaveTimer;

  static Future<ModbusWorkspace> create() async {
    final store = await ModbusStore.create();
    final master = ModbusMasterController(config: store.loadMasterConfig());
    for (final item in store.loadPollItems()) {
      master.pollItems.add(item);
    }
    final slave = ModbusSlaveController(
      config: store.loadSlaveConfig(),
      bank: store.loadSlaveBank(),
    );
    return ModbusWorkspace._(store, master, slave).._attachPersistence();
  }

  void _attachPersistence() {
    // 主机：轮询表 / 连接参数变更即存（数据量小）。
    master.addListener(_saveMasterState);
    slave.addListener(_scheduleSlaveBankSave);
  }

  void _saveMasterState() {
    unawaited(_store.saveMasterConfig(master.config));
    unawaited(_store.savePollItems(master.pollItems));
  }

  void _scheduleSlaveBankSave() {
    unawaited(_store.saveSlaveConfig(slave.config));
    // 寄存器可达数千点，编辑时做 500ms 防抖后再写盘。
    _bankSaveTimer?.cancel();
    _bankSaveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_store.saveSlaveBank(slave.bank));
    });
  }

  void dispose() {
    _bankSaveTimer?.cancel();
    master.removeListener(_saveMasterState);
    slave.removeListener(_scheduleSlaveBankSave);
    master.dispose();
    slave.dispose();
  }
}
