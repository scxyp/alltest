/// MQTT 消息服务质量等级。
enum MqttQosLevel {
  atMostOnce('0 - 最多一次'),
  atLeastOnce('1 - 至少一次'),
  exactlyOnce('2 - 恰好一次');

  const MqttQosLevel(this.label);

  final String label;
}

/// MQTT 遗嘱消息（Last Will）配置。
class MqttLastWill {
  const MqttLastWill({
    required this.topic,
    required this.payload,
    this.qos = MqttQosLevel.atMostOnce,
    this.retain = false,
  });

  final String topic;
  final String payload;
  final MqttQosLevel qos;
  final bool retain;

  Map<String, dynamic> toJson() => {
        'topic': topic,
        'payload': payload,
        'qos': qos.name,
        'retain': retain,
      };

  factory MqttLastWill.fromJson(Map<String, dynamic> json) => MqttLastWill(
        topic: json['topic'] as String? ?? '',
        payload: json['payload'] as String? ?? '',
        qos: MqttQosLevel.values.firstWhere(
          (e) => e.name == json['qos'],
          orElse: () => MqttQosLevel.atMostOnce,
        ),
        retain: json['retain'] as bool? ?? false,
      );
}

/// 一次 MQTT 会话的完整连接参数。
class MqttConfig {
  const MqttConfig({
    this.host = '',
    this.port = 1883,
    this.clientId = '',
    this.username = '',
    this.password = '',
    this.tls = false,
    this.keepAlive = 60,
    this.will,
  });

  final String host;
  final int port;
  final String clientId;
  final String username;
  final String password;
  final bool tls;
  final int keepAlive;
  final MqttLastWill? will;

  /// 概要文本，用于会话状态栏的参数标签。
  String get summary =>
      'MQTT ${tls ? "TLS" : "TCP"} → ${host.isEmpty ? "?" : host}:$port';

  MqttConfig copyWith({
    String? host,
    int? port,
    String? clientId,
    String? username,
    String? password,
    bool? tls,
    int? keepAlive,
    MqttLastWill? will,
  }) {
    return MqttConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      clientId: clientId ?? this.clientId,
      username: username ?? this.username,
      password: password ?? this.password,
      tls: tls ?? this.tls,
      keepAlive: keepAlive ?? this.keepAlive,
      will: will ?? this.will,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'clientId': clientId,
        'username': username,
        'password': password,
        'tls': tls,
        'keepAlive': keepAlive,
        if (will != null) 'will': will!.toJson(),
      };

  factory MqttConfig.fromJson(Map<String, dynamic> json) => MqttConfig(
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 1883,
        clientId: json['clientId'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        tls: json['tls'] as bool? ?? false,
        keepAlive: (json['keepAlive'] as num?)?.toInt() ?? 60,
        will: json['will'] is Map<String, dynamic>
            ? MqttLastWill.fromJson(json['will'] as Map<String, dynamic>)
            : null,
      );
}
