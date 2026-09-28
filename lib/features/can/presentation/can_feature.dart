import 'package:flutter/material.dart';

import '../../../core/feature/debug_feature.dart';
import '../domain/can_session_manager.dart';
import 'can_page.dart';

/// CAN 调试功能 —— 注册到 [FeatureRegistry] 的功能入口。
///
/// 通过 SLCAN 串口协议与 CAN 适配器（CANable / Lawicel CANUSB / ESP32 等）
/// 通信，支持标准/扩展帧、数据/远程帧收发，最多 4 个适配器并行连接。
class CanFeature implements DebugFeature {
  CanFeature();

  /// 管理器在应用生命周期内只创建一次，离开页面再返回时会话保持不断开。
  late final Future<CanSessionManager> managerFuture =
      CanSessionManager.create();

  @override
  String get id => 'can';

  @override
  String get title => 'CAN 调试';

  @override
  String get description => 'SLCAN 协议，标准/扩展帧收发，最多 4 个适配器并行';

  @override
  IconData get icon => Icons.directions_car_outlined;

  @override
  Color get color => const Color(0xFFE84393);

  @override
  Widget buildPage(BuildContext context) {
    return FutureBuilder<CanSessionManager>(
      future: managerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('CAN 调试')),
            body: Center(child: Text('初始化失败：${snapshot.error}')),
          );
        }
        return CanPage(manager: snapshot.data!);
      },
    );
  }
}
