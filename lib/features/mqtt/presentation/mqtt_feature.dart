import 'package:flutter/material.dart';

import '../../../core/feature/debug_feature.dart';
import '../domain/mqtt_session_manager.dart';
import 'mqtt_page.dart';

/// MQTT 调试功能 —— 注册到 FeatureRegistry 的功能入口。
class MqttFeature implements DebugFeature {
  MqttFeature();

  late final Future<MqttSessionManager> managerFuture =
      MqttSessionManager.create();

  @override
  String get id => 'mqtt';

  @override
  String get title => 'MQTT 调试';

  @override
  String get description => 'MQTT 客户端，支持订阅/发布/QoS/遗嘱，最多 4 个连接';

  @override
  IconData get icon => Icons.hub_outlined;

  @override
  Color get color => const Color(0xFF00B894);

  @override
  Widget buildPage(BuildContext context) {
    return FutureBuilder<MqttSessionManager>(
      future: managerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('MQTT 调试')),
            body: Center(child: Text('初始化失败：${snapshot.error}')),
          );
        }
        return MqttPage(manager: snapshot.data!);
      },
    );
  }
}
