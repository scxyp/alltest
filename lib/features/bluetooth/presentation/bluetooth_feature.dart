import 'package:flutter/material.dart';

import '../../../core/feature/debug_feature.dart';
import '../domain/ble_session_manager.dart';
import 'bluetooth_page.dart';

/// 蓝牙调试功能 —— 注册到 [FeatureRegistry] 的功能入口。
class BluetoothFeature implements DebugFeature {
  BluetoothFeature();

  /// 管理器在应用生命周期内只创建一次。
  late final Future<BleSessionManager> managerFuture =
      BleSessionManager.create();

  @override
  String get id => 'bluetooth';

  @override
  String get title => '蓝牙调试';

  @override
  String get description => 'BLE 设备扫描、连接、GATT 读写与 Notify 订阅';

  @override
  IconData get icon => Icons.bluetooth;

  @override
  Color get color => const Color(0xFF4A90D9);

  @override
  Widget buildPage(BuildContext context) {
    return FutureBuilder<BleSessionManager>(
      future: managerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('蓝牙调试')),
            body: Center(child: Text('初始化失败：${snapshot.error}')),
          );
        }
        return BluetoothPage(manager: snapshot.data!);
      },
    );
  }
}
