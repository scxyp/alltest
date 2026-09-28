import 'dart:typed_data';

import '../util/data_format.dart';

enum DebugDirection { transmit, receive, system }

/// 数据监视器中的一条记录（发送 / 接收 / 系统事件）。
class DebugLogEntry {
  DebugLogEntry._(
    this.timestamp,
    this.direction,
    this.data,
    this.message,
    this.source,
  );

  factory DebugLogEntry.receive(Uint8List data, {String? source}) =>
      DebugLogEntry._(
        DateTime.now(),
        DebugDirection.receive,
        data,
        null,
        source,
      );

  factory DebugLogEntry.transmit(Uint8List data, {String? source}) =>
      DebugLogEntry._(
        DateTime.now(),
        DebugDirection.transmit,
        data,
        null,
        source,
      );

  factory DebugLogEntry.system(String message) => DebugLogEntry._(
        DateTime.now(),
        DebugDirection.system,
        null,
        message,
        null,
      );

  final DateTime timestamp;
  final DebugDirection direction;

  /// 收发的原始字节；系统事件时为 null。
  final Uint8List? data;

  /// 系统事件文本。
  final String? message;

  /// 数据来源 / 目标对端（如 "192.168.1.5:5432"），单机连接时为 null。
  final String? source;

  bool get isSystem => direction == DebugDirection.system;

  String get tag {
    final base = switch (direction) {
      DebugDirection.receive => 'RX',
      DebugDirection.transmit => 'TX',
      DebugDirection.system => '系统',
    };
    return (source != null && source!.isNotEmpty) ? '$base|$source' : base;
  }

  /// 按当前显示模式渲染数据部分。
  String body({required bool asHex}) {
    if (isSystem) return message ?? '';
    final bytes = data!;
    return asHex ? DataFormat.bytesToHex(bytes) : DataFormat.bytesToText(bytes);
  }

  /// 导出 TXT 时的完整行。
  String toTextLine({required bool asHex, required bool withTimestamp}) {
    final ts = withTimestamp ? '[${DataFormat.fullTimestamp(timestamp)}] ' : '';
    return '$ts[$tag] ${body(asHex: asHex)}';
  }
}

/// 提取适合直接展示的错误文本（StateError 去掉 "Bad state: " 前缀）。
String friendlyError(Object error) =>
    error is StateError ? error.message : '$error';
