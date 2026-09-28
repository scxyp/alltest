import 'package:flutter/material.dart';

import '../../../core/feature/debug_feature.dart';
import '../domain/usb_session_manager.dart';
import 'usb_page.dart';

/// USB 调试功能 —— 注册到 [FeatureRegistry] 的功能入口。
class UsbFeature implements DebugFeature {
  UsbFeature();

  /// 管理器在应用生命周期内只创建一次。
  late final Future<UsbSessionManager> managerFuture =
      UsbSessionManager.create();

  @override
  String get id => 'usb';

  @override
  String get title => 'USB 调试';

  @override
  String get description => 'HID Report 收发与通用 USB（WinUSB/libusb）Bulk 传输';

  @override
  IconData get icon => Icons.usb;

  @override
  Color get color => const Color(0xFF6C5CE7);

  @override
  Widget buildPage(BuildContext context) {
    return FutureBuilder<UsbSessionManager>(
      future: managerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('USB 调试')),
            body: Center(child: Text('初始化失败：${snapshot.error}')),
          );
        }
        return UsbPage(manager: snapshot.data!);
      },
    );
  }
}
