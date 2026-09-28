import '../../can/domain/can_config.dart';
import '../../can/domain/can_transport.dart';

/// CANopen 节点 ID（1~127，0=广播）。
///
/// CANopen COB-ID 由功能码前缀 + Node ID 组成，
/// 因此 Node ID 决定了每个功能的 COB-ID 偏移。
typedef CanOpenNodeId = int;

/// CANopen 会话完整配置。
///
/// 传输层插件化后，[transportType] 指定使用的 CAN 传输层（默认 `slcan`），
/// 其余字段与 [CanConfig] 相同，额外增加 CANopen 特有的 [nodeId]。
class CanOpenConfig {
  const CanOpenConfig({
    this.transportType = 'slcan',
    required this.portName,
    this.baudRate = 115200,
    this.canBitrate = CanBitrate.speed500K,
    this.nodeId = 1,
    this.rawConfig = const {},
  });

  /// CAN 传输层类型，对应 [CanTransport.transportType]。
  final String transportType;

  /// 适配器标识（如 SLCAN 的串口名 `COM5`）。
  final String portName;

  /// SLCAN 传输层的串口波特率；其他传输层可忽略此字段（参数放 [rawConfig]）。
  final int baudRate;

  /// CAN 总线波特率。
  final CanBitrate canBitrate;

  /// CANopen 目标节点 ID（1~127，0 表示广播所有节点）。
  final CanOpenNodeId nodeId;

  /// 传输层特有的额外参数。
  final Map<String, dynamic> rawConfig;

  /// 形如 `COM5 115200 / 500 kbps / Node 1` 的概要文本。
  String get summary =>
      '$portName $baudRate / ${canBitrate.label} / Node $nodeId';

  /// 转换为底层 CAN 传输层配置。
  CanTransportConfig toTransportConfig() => CanTransportConfig(
        transportType: transportType,
        portName: portName,
        canBitrate: canBitrate,
        rawConfig: {
          if (transportType == 'slcan') 'baudRate': baudRate,
          ...rawConfig,
        },
      );

  CanOpenConfig copyWith({
    String? transportType,
    String? portName,
    int? baudRate,
    CanBitrate? canBitrate,
    CanOpenNodeId? nodeId,
    Map<String, dynamic>? rawConfig,
  }) {
    return CanOpenConfig(
      transportType: transportType ?? this.transportType,
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      canBitrate: canBitrate ?? this.canBitrate,
      nodeId: nodeId ?? this.nodeId,
      rawConfig: rawConfig ?? this.rawConfig,
    );
  }

  Map<String, dynamic> toJson() => {
        'transportType': transportType,
        'portName': portName,
        'baudRate': baudRate,
        'canBitrate': canBitrate.name,
        'nodeId': nodeId,
        'rawConfig': rawConfig,
      };

  factory CanOpenConfig.fromJson(Map<String, dynamic> json) {
    return CanOpenConfig(
      transportType: json['transportType'] as String? ?? 'slcan',
      portName: json['portName'] as String? ?? '',
      baudRate: (json['baudRate'] as num?)?.toInt() ?? 115200,
      canBitrate: CanBitrate.values.firstWhere(
        (e) => e.name == json['canBitrate'],
        orElse: () => CanBitrate.speed500K,
      ),
      nodeId: (json['nodeId'] as num?)?.toInt() ?? 1,
      rawConfig: Map<String, dynamic>.from(json['rawConfig'] as Map? ?? {}),
    );
  }
}
