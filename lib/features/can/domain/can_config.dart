import 'can_transport.dart';

/// CAN 总线波特率预设（对应 SLCAN S0~S9 命令）。
enum CanBitrate {
  speed10K('10 kbps', '0'),
  speed20K('20 kbps', '1'),
  speed50K('50 kbps', '2'),
  speed100K('100 kbps', '3'),
  speed125K('125 kbps', '4'),
  speed250K('250 kbps', '5'),
  speed500K('500 kbps', '6'),
  speed800K('800 kbps', '7'),
  speed1M('1 Mbps', '8'),
  speed83K('83.3 kbps', '9');

  const CanBitrate(this.label, this.slcanCode);

  /// 界面显示文本。
  final String label;

  /// SLCAN 协议中 S 命令后的波特率代码字符。
  final String slcanCode;
}

/// 一次 CAN 连接的完整参数。
///
/// 传输层插件化后，配置包含三部分：
/// - [transportType]：使用的 CAN 传输层（默认 `slcan`，未来可扩展 `pcan` / `kvaser` / 自研）
/// - [portName] / [baudRate]：适配器标识 + 传输层特有参数（如 SLCAN 的串口名 / 波特率）
/// - [canBitrate]：CAN 总线侧波特率（所有传输层共有）
///
/// 未来新增传输层特有的参数时，放入 [rawConfig] 即可。
class CanConfig {
  const CanConfig({
    this.transportType = 'slcan',
    required this.portName,
    this.baudRate = 115200,
    this.canBitrate = CanBitrate.speed500K,
    this.rawConfig = const {},
  });

  /// CAN 传输层类型，对应 [CanTransport.transportType]。
  /// 默认 `slcan`（Lawicel 串口协议）。
  final String transportType;

  /// 适配器标识（如 SLCAN 的串口名 `COM5`，PCAN 的通道号 `PCAN-USB1`）。
  final String portName;

  /// SLCAN 传输层的串口波特率；其他传输层可忽略此字段（参数放 [rawConfig]）。
  final int baudRate;

  /// CAN 总线波特率。
  final CanBitrate canBitrate;

  /// 传输层特有的额外参数（如 PCAN 的 USB 设备索引）。
  final Map<String, dynamic> rawConfig;

  /// 形如 `COM5 115200 / 500 kbps` 的概要文本。
  String get summary =>
      '$portName $baudRate / ${canBitrate.label}';

  CanConfig copyWith({
    String? transportType,
    String? portName,
    int? baudRate,
    CanBitrate? canBitrate,
    Map<String, dynamic>? rawConfig,
  }) {
    return CanConfig(
      transportType: transportType ?? this.transportType,
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      canBitrate: canBitrate ?? this.canBitrate,
      rawConfig: rawConfig ?? this.rawConfig,
    );
  }

  /// 转换为传输层通用配置。
  CanTransportConfig toTransportConfig() => CanTransportConfig(
        transportType: transportType,
        portName: portName,
        canBitrate: canBitrate,
        rawConfig: {
          if (transportType == 'slcan') 'baudRate': baudRate,
          ...rawConfig,
        },
      );

  Map<String, dynamic> toJson() => {
        'transportType': transportType,
        'portName': portName,
        'baudRate': baudRate,
        'canBitrate': canBitrate.name,
        'rawConfig': rawConfig,
      };

  factory CanConfig.fromJson(Map<String, dynamic> json) {
    return CanConfig(
      transportType: json['transportType'] as String? ?? 'slcan',
      portName: json['portName'] as String? ?? '',
      baudRate: (json['baudRate'] as num?)?.toInt() ?? 115200,
      canBitrate: CanBitrate.values.firstWhere(
        (e) => e.name == json['canBitrate'],
        orElse: () => CanBitrate.speed500K,
      ),
      rawConfig: Map<String, dynamic>.from(json['rawConfig'] as Map? ?? {}),
    );
  }
}
