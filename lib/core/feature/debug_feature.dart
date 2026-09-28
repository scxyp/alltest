import 'package:flutter/material.dart';

/// 所有调试功能模块统一实现的扩展接口。
///
/// 新增一个调试工具（例如 TCP/UDP、蓝牙、MQTT 等）时，只需：
/// 1. 实现本接口；
/// 2. 在 `lib/core/bootstrap.dart` 中调用 `registry.register(...)`。
/// 主页会自动展示入口，无需改动框架代码。
abstract class DebugFeature {
  /// 全局唯一标识，例如 'serial'。
  String get id;

  /// 功能名称（主页卡片标题）。
  String get title;

  /// 一句话功能描述。
  String get description;

  /// 入口图标。
  IconData get icon;

  /// 主题色（卡片渐变 / 状态强调）。
  Color get color;

  /// 构建该功能的主页面。
  Widget buildPage(BuildContext context);
}
