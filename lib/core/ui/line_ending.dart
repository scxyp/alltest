/// 发送时使用的行结束符（各调试模块通用）。
enum LineEnding {
  none('无', ''),
  crLf('CRLF (\\r\\n)', '\r\n'),
  cr('CR (\\r)', '\r'),
  lf('LF (\\n)', '\n');

  const LineEnding(this.label, this.suffix);

  final String label;
  final String suffix;
}
