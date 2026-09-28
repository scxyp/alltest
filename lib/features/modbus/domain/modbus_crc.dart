import 'dart:typed_data';

/// Modbus RTU 使用的 CRC-16（多项式 0xA001，初始 0xFFFF）。
class ModbusCrc {
  /// 计算 [data] 的 CRC 值（未拆字节的原始 16 位值）。
  static int calculate(List<int> data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      crc ^= byte & 0xFF;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// 低字节在前追加 CRC，返回完整 RTU 帧。
  static Uint8List append(List<int> body) {
    final crc = calculate(body);
    final out = BytesBuilder()
      ..add(body)
      ..addByte(crc & 0xFF)
      ..addByte((crc >> 8) & 0xFF);
    return out.toBytes();
  }

  /// 校验完整 RTU 帧（最后两字节为 CRC，低字节在前）。
  static bool verify(List<int> frame) {
    if (frame.length < 4) return false;
    final body = frame.sublist(0, frame.length - 2);
    final expected = calculate(body);
    final actual =
        (frame[frame.length - 2] & 0xFF) |
        ((frame[frame.length - 1] & 0xFF) << 8);
    return expected == actual;
  }
}
