import 'package:flutter/material.dart';

import '../../../core/feature/debug_feature.dart';
import '../domain/serial_session_manager.dart';
import 'serial_page.dart';

/// 串口调试功能 —— 注册到 [FeatureRegistry] 的功能入口。
class SerialFeature implements DebugFeature {
  SerialFeature();

  /// 管理器在应用生命周期内只创建一次，离开页面再返回时会话保持不断开。
  late final Future<SerialSessionManager> managerFuture =
      SerialSessionManager.create();

  @override
  String get id => 'serial';

  @override
  String get title => '串口调试';

  @override
  String get description => '多串口并行连接，HEX/文本收发、定时发送、日志导出';

  @override
  IconData get icon => Icons.cable_outlined;

  @override
  Color get color => const Color(0xFF2E9E6B);

  @override
  Widget buildPage(BuildContext context) {
    return FutureBuilder<SerialSessionManager>(
      future: managerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('串口调试')),
            body: Center(child: Text('初始化失败：${snapshot.error}')),
          );
        }
        return SerialPage(manager: snapshot.data!);
      },
    );
  }
}
