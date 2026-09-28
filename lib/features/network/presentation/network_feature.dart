import 'package:flutter/material.dart';

import '../../../core/feature/debug_feature.dart';
import '../domain/net_session_manager.dart';
import 'network_page.dart';

/// 网络调试功能 —— 注册到 FeatureRegistry 的功能入口。
class NetworkFeature implements DebugFeature {
  NetworkFeature();

  late final Future<NetSessionManager> managerFuture =
      NetSessionManager.create();

  @override
  String get id => 'network';

  @override
  String get title => '网络调试';

  @override
  String get description => 'TCP 客户端/服务端、UDP 收发，自动识别网卡 IP';

  @override
  IconData get icon => Icons.lan_outlined;

  @override
  Color get color => const Color(0xFF3A7BD5);

  @override
  Widget buildPage(BuildContext context) {
    return FutureBuilder<NetSessionManager>(
      future: managerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('网络调试')),
            body: Center(child: Text('初始化失败：${snapshot.error}')),
          );
        }
        return NetworkPage(manager: snapshot.data!);
      },
    );
  }
}
