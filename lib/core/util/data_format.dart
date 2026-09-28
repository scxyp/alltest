import 'dart:convert';
import 'dart:typed_data';

/// 字节数据与文本 / HEX 之间的转换，以及时间戳格式化。
class DataFormat {
  const DataFormat._();

  /// 字节数组转成 "AA BB 01" 形式的大写 HEX 字符串。
  static String bytesToHex(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    final sb = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i > 0) sb.write(' ');
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return sb.toString();
  }

  /// HEX 字符串（允许空格 / 换行分隔）转字节数组，非法时抛出 [FormatException]。
  static Uint8List hexToBytes(String input) {
    final hex = input.replaceAll(RegExp(r'\s+'), '');
    if (hex.isEmpty) return Uint8List(0);
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      throw const FormatException('HEX 数据不合法：需为偶数位十六进制字符（0-9 A-F）');
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// 字节转文本（UTF-8，非法字节使用替换字符，不抛异常）。
  static String bytesToText(Uint8List bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  /// 文本转 UTF-8 字节。
  static Uint8List textToBytes(String text) =>
      Uint8List.fromList(utf8.encode(text));

  /// 完整时间戳：2026-09-21 14:03:25.123（用于导出文件）。
  static String fullTimestamp(DateTime t) =>
      '${_date(t)} ${_clock(t)}.${_digits(t.millisecond, 3)}';

  /// 界面显示用时间戳：14:03:25.123。
  static String clockTimestamp(DateTime t) =>
      '${_clock(t)}.${_digits(t.millisecond, 3)}';

  /// 文件名用时间：20260921_140325。
  static String fileTimestamp(DateTime t) =>
      '${_date(t).replaceAll('-', '')}_${_clock(t).replaceAll(':', '')}';

  static String _date(DateTime t) =>
      '${t.year}-${_digits(t.month)}-${_digits(t.day)}';

  static String _clock(DateTime t) =>
      '${_digits(t.hour)}:${_digits(t.minute)}:${_digits(t.second)}';

  static String _digits(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');
}
