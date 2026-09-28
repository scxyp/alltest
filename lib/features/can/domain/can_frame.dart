import 'dart:typed_data';

/// 一个 CAN 2.0B 数据帧或远程帧，及 SLCAN 协议编解码。
class CanFrame {
  CanFrame({
    required this.id,
    required this.extended,
    required this.remote,
    required this.data,
  }) {
    if (extended) {
      if (id < 0 || id > 0x1FFFFFFF) {
        throw RangeError('扩展帧 ID 范围：0~0x1FFFFFFF');
      }
    } else {
      if (id < 0 || id > 0x7FF) {
        throw RangeError('标准帧 ID 范围：0~0x7FF');
      }
    }
    if (data.length > 8) {
      throw RangeError('CAN 数据帧最多 8 字节');
    }
  }

  /// CAN 帧标识符（标准帧 11-bit / 扩展帧 29-bit）。
  final int id;

  /// 是否为扩展帧（29-bit ID）。
  final bool extended;

  /// 是否为远程帧（无数据，请求对应 ID 的数据帧）。
  final bool remote;

  /// 数据负载（0~8 字节，远程帧时为空）。
  final Uint8List data;

  /// 帧的数据长度码（DLC）。
  int get dlc => remote ? data.length : data.length;

  /// 帧 ID 的十六进制文本（大写）。
  String get idHex => extended
      ? id.toRadixString(16).toUpperCase().padLeft(8, '0')
      : id.toRadixString(16).toUpperCase().padLeft(3, '0');

  /// 日志中显示的来源标签。
  String get sourceTag => 'ID:0x$idHex';

  // --- SLCAN 编解码 ---

  /// 将帧编码为 SLCAN 命令字符串（含结尾 `\r`）。
  ///
  /// - 标准数据帧：`t` + 3hexID + 1hexDLC + hexData + `\r`
  /// - 扩展数据帧：`T` + 8hexID + 1hexDLC + hexData + `\r`
  /// - 标准远程帧：`r` + 3hexID + 1hexDLC + `\r`
  /// - 扩展远程帧：`R` + 8hexID + 1hexDLC + `\r`
  String toSlcanCommand() {
    final cmd = StringBuffer();
    if (remote) {
      cmd.write(extended ? 'R' : 'r');
    } else {
      cmd.write(extended ? 'T' : 't');
    }
    cmd.write(idHex);
    cmd.write(dlc.toRadixString(16).toUpperCase());
    if (!remote) {
      for (final b in data) {
        cmd.write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    cmd.write('\r');
    return cmd.toString();
  }

  /// 从 SLCAN 帧行（不含结尾 `\r`）解析 CAN 帧。
  ///
  /// 支持标准/扩展、数据/远程帧。解析失败返回 null。
  static CanFrame? fromSlcan(String line) {
    if (line.isEmpty) return null;
    final type = line[0];
    final bool extended;
    final bool remote;
    switch (type) {
      case 't':
        extended = false;
        remote = false;
        break;
      case 'T':
        extended = true;
        remote = false;
        break;
      case 'r':
        extended = false;
        remote = true;
        break;
      case 'R':
        extended = true;
        remote = true;
        break;
      default:
        return null;
    }

    final idLen = extended ? 8 : 3;
    // 1(type) + idLen + 1(dlc) 至少这么多字符
    if (line.length < 1 + idLen + 1) return null;

    final idStr = line.substring(1, 1 + idLen);
    final id = int.tryParse(idStr, radix: 16);
    if (id == null) return null;

    final dlcChar = line.substring(1 + idLen, 1 + idLen + 1);
    final dlc = int.tryParse(dlcChar, radix: 16);
    if (dlc == null || dlc < 0 || dlc > 8) return null;

    Uint8List data;
    if (!remote) {
      final dataStr = line.substring(1 + idLen + 1);
      // 数据部分必须是偶数位 hex，且长度匹配 dlc*2
      if (dataStr.length != dlc * 2) return null;
      if (!RegExp(r'^[0-9a-fA-F]*$').hasMatch(dataStr)) return null;
      data = Uint8List(dlc);
      for (var i = 0; i < dlc; i++) {
        data[i] = int.parse(dataStr.substring(i * 2, i * 2 + 2), radix: 16);
      }
    } else {
      data = Uint8List(0);
    }

    try {
      return CanFrame(
        id: id,
        extended: extended,
        remote: remote,
        data: data,
      );
    } catch (_) {
      return null;
    }
  }
}
