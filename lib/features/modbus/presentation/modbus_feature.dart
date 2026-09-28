import 'package:flutter/material.dart';

import '../../../core/feature/debug_feature.dart';
import '../domain/modbus_workspace.dart';
import 'modbus_page.dart';

/// Modbus 主机 / 从机模拟器 —— 注册到 FeatureRegistry 的功能入口。
class ModbusFeature implements DebugFeature {
  ModbusFeature();

  late final Future<ModbusWorkspace> workspaceFuture =
      ModbusWorkspace.create();

  @override
  String get id => 'modbus';

  @override
  String get title => 'Modbus 模拟器';

  @override
  String get description => 'Modbus RTU/TCP 主机轮询与从机寄存器模拟（FC1-6/15/16）';

  @override
  IconData get icon => Icons.memory;

  @override
  Color get color => const Color(0xFFE07B39);

  @override
  Widget buildPage(BuildContext context) {
    return FutureBuilder<ModbusWorkspace>(
      future: workspaceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Modbus 模拟器')),
            body: Center(child: Text('初始化失败：${snapshot.error}')),
          );
        }
        return ModbusPage(workspace: snapshot.data!);
      },
    );
  }
}
