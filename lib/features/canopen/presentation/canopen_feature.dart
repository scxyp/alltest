import 'package:flutter/material.dart';

import '../../../core/feature/debug_feature.dart';
import '../domain/canopen_session_manager.dart';
import 'canopen_page.dart';

/// CANopen 调试功能 —— 注册到 [FeatureRegistry] 的功能入口。
///
/// 通过 SLCAN 串口协议连接 CAN 适配器，在 CAN 之上实现 CANopen
/// 协议层（SDO/NMT/Heartbeat/EMCY/PDO），支持 Expedited SDO 读写
/// 和 NMT 节点状态控制，最多 4 个适配器并行。
class CanOpenFeature implements DebugFeature {
  CanOpenFeature();

  late final Future<CanOpenSessionManager> managerFuture =
      CanOpenSessionManager.create();

  @override
  String get id => 'canopen';

  @override
  String get title => 'CANopen 调试';

  @override
  String get description =>
      'CANopen SDO/NMT/Heartbeat，支持对象字典 Expedited 读写';

  @override
  IconData get icon => Icons.settings_input_component_outlined;

  @override
  Color get color => const Color(0xFFFD7E14);

  @override
  Widget buildPage(BuildContext context) {
    return FutureBuilder<CanOpenSessionManager>(
      future: managerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('CANopen 调试')),
            body: Center(child: Text('初始化失败：${snapshot.error}')),
          );
        }
        return CanOpenPage(manager: snapshot.data!);
      },
    );
  }
}
