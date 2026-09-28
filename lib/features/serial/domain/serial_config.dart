import 'package:libserialport/libserialport.dart';

/// 校验方式。
enum SerialParity {
  none('无 (None)', SerialPortParity.none, 'N'),
  odd('奇校验 (Odd)', SerialPortParity.odd, 'O'),
  even('偶校验 (Even)', SerialPortParity.even, 'E'),
  mark('Mark', SerialPortParity.mark, 'M'),
  space('Space', SerialPortParity.space, 'S');

  const SerialParity(this.label, this.nativeValue, this.shortLabel);

  final String label;
  final int nativeValue;
  final String shortLabel;
}

/// 停止位（取值与 libserialport C 枚举一致：1=0、1.5=1、2=2）。
enum SerialStopBits {
  one('1', 0, '1'),
  onePointFive('1.5', 1, '1.5'),
  two('2', 2, '2');

  const SerialStopBits(this.label, this.nativeValue, this.shortLabel);

  final String label;
  final int nativeValue;
  final String shortLabel;
}

/// 流控方式。
enum SerialFlowControl {
  none('无', SerialPortFlowControl.none),
  xonXoff('XON/XOFF', SerialPortFlowControl.xonXoff),
  rtsCts('RTS/CTS', SerialPortFlowControl.rtsCts),
  dtrDsr('DTR/DSR', SerialPortFlowControl.dtrDsr);

  const SerialFlowControl(this.label, this.nativeValue);

  final String label;
  final int nativeValue;
}

/// 一次串口连接的完整参数。
class SerialConfig {
  const SerialConfig({
    required this.portName,
    this.baudRate = 115200,
    this.dataBits = 8,
    this.parity = SerialParity.none,
    this.stopBits = SerialStopBits.one,
    this.flowControl = SerialFlowControl.none,
  });

  /// 系统串口名，例如 Windows 上的 `COM3`。
  final String portName;

  final int baudRate;
  final int dataBits;
  final SerialParity parity;
  final SerialStopBits stopBits;
  final SerialFlowControl flowControl;

  /// 形如 `115200 8-N-1` 的概要文本。
  String get summary =>
      '$baudRate $dataBits-${parity.shortLabel}-${stopBits.shortLabel}';

  SerialConfig copyWith({
    String? portName,
    int? baudRate,
    int? dataBits,
    SerialParity? parity,
    SerialStopBits? stopBits,
    SerialFlowControl? flowControl,
  }) {
    return SerialConfig(
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      parity: parity ?? this.parity,
      stopBits: stopBits ?? this.stopBits,
      flowControl: flowControl ?? this.flowControl,
    );
  }

  Map<String, dynamic> toJson() => {
        'portName': portName,
        'baudRate': baudRate,
        'dataBits': dataBits,
        'parity': parity.name,
        'stopBits': stopBits.name,
        'flowControl': flowControl.name,
      };

  factory SerialConfig.fromJson(Map<String, dynamic> json) {
    return SerialConfig(
      portName: json['portName'] as String? ?? '',
      baudRate: (json['baudRate'] as num?)?.toInt() ?? 115200,
      dataBits: (json['dataBits'] as num?)?.toInt() ?? 8,
      parity: SerialParity.values.firstWhere(
        (e) => e.name == json['parity'],
        orElse: () => SerialParity.none,
      ),
      stopBits: SerialStopBits.values.firstWhere(
        (e) => e.name == json['stopBits'],
        orElse: () => SerialStopBits.one,
      ),
      flowControl: SerialFlowControl.values.firstWhere(
        (e) => e.name == json['flowControl'],
        orElse: () => SerialFlowControl.none,
      ),
    );
  }
}
