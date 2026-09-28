import 'dart:io';

/// 一张可用网卡及其 IPv4 地址。
class NetInterfaceInfo {
  const NetInterfaceInfo({required this.name, required this.ipv4Addresses});

  /// 系统网卡名，如 Windows 上的 "以太网" / "WLAN"。
  final String name;

  /// 该网卡上的全部 IPv4 地址。
  final List<String> ipv4Addresses;
}

/// 网卡枚举服务：列出本机网卡及 IPv4 地址，供"选择网口、自动识别 IP"使用。
class NetworkInfoService {
  /// 获取本机全部含 IPv4 地址的网卡（含环回口，排在最后）。
  ///
  /// 枚举失败时返回空列表，由调用方决定提示方式。
  static Future<List<NetInterfaceInfo>> list() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: true,
    );
    final result = <NetInterfaceInfo>[
      for (final iface in interfaces)
        if (iface.addresses.isNotEmpty)
          NetInterfaceInfo(
            name: iface.name,
            ipv4Addresses:
                iface.addresses.map((a) => a.address).toList(growable: false),
          ),
    ];
    // 环回口排到最后，普通网卡优先展示。
    result.sort((a, b) {
      final aLo = a.ipv4Addresses
          .every((ip) => ip.startsWith('127.'));
      final bLo = b.ipv4Addresses
          .every((ip) => ip.startsWith('127.'));
      return aLo == bLo ? 0 : (aLo ? 1 : -1);
    });
    return result;
  }
}
