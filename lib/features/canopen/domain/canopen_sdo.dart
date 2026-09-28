import 'dart:typed_data';

import 'canopen_config.dart';

/// SDO 客户端请求类型（仅实现 Expedited 快速传输，≤4 字节单帧完成）。
enum SdoCommand {
  read(0x40),
  write4B(0x23),
  write3B(0x2B),
  write2B(0x2F),
  write1B(0x27);

  const SdoCommand(this.code);
  final int code;
}

/// SDO 服务器响应命令码。
enum SdoResponse {
  readOk(0x42),
  writeOk(0x43),
  abort(0x80);

  const SdoResponse(this.code);
  final int code;
}

/// SDO Abort 常用错误码（0x0601xxxx ~ 0x08xxxxxx 范围）。
const Map<int, String> kSdoAbortCodes = {
  0x05030000: 'Toggle bit 未改变（服务器忙）',
  0x05040000: 'SDO 协议超时',
  0x05040001: '未知块传输大小',
  0x05040002: '无效块序号',
  0x05040003: '无效块大小',
  0x05040004: '无效 CRC',
  0x05040005: '内存不足',
  0x06010000: '对象不支持访问',
  0x06010001: '尝试读取只写对象',
  0x06010002: '尝试写入只读对象',
  0x06020000: '对象不存在',
  0x06040000: '数据类型不匹配（长度错误）',
  0x06040001: '数据类型不匹配（值范围错误）',
  0x06040002: '无法理解参数',
  0x06040004: '无法分配资源',
  0x06060000: '访问失败',
  0x06070010: '数据类型不匹配（参数范围错误）',
  0x06070012: '数据类型不匹配（值太高）',
  0x06070013: '数据类型不匹配（值太低）',
  0x06090011: '子索引不存在',
  0x06090030: '值超出范围',
  0x06090031: '值太高（溢出）',
  0x06090032: '值太低（不足）',
  0x06090036: '子索引范围错误',
  0x08000000: '通用错误',
  0x08000020: '存储未完成',
  0x08000021: '存储权限错误',
  0x08000022: '下载时对象字典锁定',
  0x08000023: '下载超时',
};

/// CANopen SDO 协议编解码（Expedited 快速传输，≤4 字节）。
///
/// SDO COB-ID：
/// - 客户端请求 → 0x600 + Node ID
/// - 服务器响应 → 0x580 + Node ID
///
/// Expedited 格式（8 字节）：
/// Byte 0: 命令码
/// Byte 1-2: Index（小端）
/// Byte 3: Subindex
/// Byte 4-7: 数据（小端填充，剩余字节为 0）
///
/// Segmented 传输（>4 字节）暂不支持，检测到后返回 null。
class SdoCodec {
  SdoCodec._();

  /// SDO 请求 COB-ID 基址。
  static const int requestCobIdBase = 0x600;

  /// SDO 响应 COB-ID 基址。
  static const int responseCobIdBase = 0x580;

  /// 构造 SDO Expedited 读取请求帧数据（8 字节）。
  ///
  /// [index] 对象字典索引（0x0000~0xFFFF）
  /// [subindex] 子索引（0x00~0xFF）
  static Uint8List buildReadRequest(int index, int subindex) {
    final data = Uint8List(8);
    data[0] = 0x40; // Read request
    data[1] = index & 0xFF;
    data[2] = (index >> 8) & 0xFF;
    data[3] = subindex & 0xFF;
    // data[4-7] = 0 (填充)
    return data;
  }

  /// 构造 SDO Expedited 写入请求帧数据（8 字节）。
  ///
  /// [index] 对象字典索引
  /// [subindex] 子索引
  /// [value] 要写入的数据（最多 4 字节，超出返回 null）
  static Uint8List? buildWriteRequest(int index, int subindex, Uint8List value) {
    if (value.isEmpty || value.length > 4) return null;
    final data = Uint8List(8);
    // 根据数据长度选择命令码
    data[0] = switch (value.length) {
      4 => 0x23,
      3 => 0x2B,
      2 => 0x2F,
      1 => 0x27,
      _ => 0,
    };
    data[1] = index & 0xFF;
    data[2] = (index >> 8) & 0xFF;
    data[3] = subindex & 0xFF;
    for (var i = 0; i < 4; i++) {
      data[4 + i] = i < value.length ? value[i] : 0;
    }
    return data;
  }

  /// 解析 SDO 响应帧数据（8 字节，来自 COB-ID 0x580+NID）。
  ///
  /// 返回 [SdoResponseResult]，包含响应类型、Index/Subindex 和数据（或 Abort 错误）。
  /// 检测到 Segmented 传输（Byte0 为 0x01/0x03/0x11/0x13 等）时返回 null。
  static SdoResponseResult? parseResponse(Uint8List data) {
    if (data.length != 8) return null;
    final cmd = data[0];
    final index = data[1] | (data[2] << 8);
    final subindex = data[3];

    // Abort
    if (cmd == 0x80) {
      final abortCode = data[4] |
          (data[5] << 8) |
          (data[6] << 16) |
          (data[7] << 24);
      return SdoResponseResult(
        type: SdoResponse.abort,
        index: index,
        subindex: subindex,
        data: Uint8List(0),
        abortCode: abortCode,
      );
    }

    // Segmented 传输检测：命令码低 2 位为 0x01/0x03/0x11/0x13 表示块传输
    // 简化判断：Expedited 的响应码为 0x42(读成功) 或 0x43(写成功)
    if (cmd != 0x42 && cmd != 0x43) {
      // 可能是 Segmented 或未知命令码，暂不支持
      return null;
    }

    // Expedited 传输中数据长度由请求时的命令码隐含，
    // 响应中 0x42 表示读成功（数据在 data[4-7]），有效长度=4；
    // 0x43 表示写成功（data[4-7] 无意义，用 0 填充）。

    if (cmd == 0x42) {
      // Read OK Expedited，4 字节数据
      final payload = Uint8List.fromList([data[4], data[5], data[6], data[7]]);
      return SdoResponseResult(
        type: SdoResponse.readOk,
        index: index,
        subindex: subindex,
        data: payload,
      );
    } else if (cmd == 0x43) {
      // Write OK Expedited，无数据
      return SdoResponseResult(
        type: SdoResponse.writeOk,
        index: index,
        subindex: subindex,
        data: Uint8List(0),
      );
    }
    return null;
  }

  /// Abort 错误码转可读文本。
  static String describeAbort(int code) {
    final known = kSdoAbortCodes[code];
    if (known != null) return known;
    return '未知 SDO Abort 0x${code.toRadixString(16).toUpperCase()}';
  }
}

/// SDO 响应解析结果。
class SdoResponseResult {
  SdoResponseResult({
    required this.type,
    required this.index,
    required this.subindex,
    required this.data,
    this.abortCode,
  });

  final SdoResponse type;
  final int index;
  final int subindex;
  final Uint8List data;
  final int? abortCode;

  /// 来自哪个 Node ID 的响应（由 COB-ID 路由时设置）。
  CanOpenNodeId? fromNodeId;
}
