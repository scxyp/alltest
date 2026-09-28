/// 网络调试的工作模式。
enum NetMode {
  tcpClient('TCP 客户端'),
  tcpServer('TCP 服务端'),
  udp('UDP');

  const NetMode(this.label);

  final String label;
}

/// 一次网络会话的完整参数。
class NetConfig {
  const NetConfig({
    this.mode = NetMode.tcpClient,

    /// 绑定的本机 IPv4；空串表示绑定所有网卡（0.0.0.0）。
    this.bindAddress = '',
    this.localPort = 0,
    this.remoteHost = '',
    this.remotePort = 0,
    this.broadcast = false,
  });

  final NetMode mode;
  final String bindAddress;
  final int localPort;
  final String remoteHost;
  final int remotePort;

  /// UDP 是否启用广播发送。
  final bool broadcast;

  /// 绑定地址的展示文本。
  String get bindLabel => bindAddress.isEmpty ? '0.0.0.0' : bindAddress;

  /// 概要文本，用于会话状态栏的参数标签。
  String get summary => switch (mode) {
        NetMode.tcpClient =>
          'TCP → ${remoteHost.isEmpty ? '?' : remoteHost}:$remotePort',
        NetMode.tcpServer => 'TCP 监听 :$localPort @ $bindLabel',
        NetMode.udp =>
          'UDP :$localPort → ${remoteHost.isEmpty ? '?' : remoteHost}'
              ':$remotePort${broadcast ? ' (广播)' : ''}',
      };

  NetConfig copyWith({
    NetMode? mode,
    String? bindAddress,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    bool? broadcast,
  }) {
    return NetConfig(
      mode: mode ?? this.mode,
      bindAddress: bindAddress ?? this.bindAddress,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      broadcast: broadcast ?? this.broadcast,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'bindAddress': bindAddress,
        'localPort': localPort,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
        'broadcast': broadcast,
      };

  factory NetConfig.fromJson(Map<String, dynamic> json) => NetConfig(
        mode: NetMode.values.firstWhere(
          (e) => e.name == json['mode'],
          orElse: () => NetMode.tcpClient,
        ),
        bindAddress: json['bindAddress'] as String? ?? '',
        localPort: (json['localPort'] as num?)?.toInt() ?? 0,
        remoteHost: json['remoteHost'] as String? ?? '',
        remotePort: (json['remotePort'] as num?)?.toInt() ?? 0,
        broadcast: json['broadcast'] as bool? ?? false,
      );
}
