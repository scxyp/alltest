import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/network_info_service.dart';
import '../../domain/net_config.dart';

/// 新建 / 编辑网络会话的配置对话框。
class NetConnectionDialog extends StatefulWidget {
  const NetConnectionDialog({
    super.key,
    required this.interfaces,
    this.initial,
  });

  final List<NetInterfaceInfo> interfaces;
  final NetConfig? initial;

  static Future<NetConfig?> show(
    BuildContext context, {
    required List<NetInterfaceInfo> interfaces,
    NetConfig? initial,
  }) {
    return showDialog<NetConfig>(
      context: context,
      builder: (_) =>
          NetConnectionDialog(interfaces: interfaces, initial: initial),
    );
  }

  @override
  State<NetConnectionDialog> createState() => _NetConnectionDialogState();
}

class _NetConnectionDialogState extends State<NetConnectionDialog> {
  late NetMode _mode;
  late String _bindAddress;
  late final TextEditingController _localPort;
  late final TextEditingController _remoteHost;
  late final TextEditingController _remotePort;
  late bool _broadcast;

  /// 0.0.0.0 特殊选项（绑定所有网卡）。
  static const String _anyAddress = '__any__';

  @override
  void initState() {
    super.initState();
    final cfg = widget.initial;
    _mode = cfg?.mode ?? NetMode.tcpClient;
    _bindAddress = cfg?.bindAddress ?? '';
    _localPort = TextEditingController(
      text: (cfg?.localPort ?? 0) == 0 ? '' : '${cfg?.localPort}',
    );
    _remoteHost = TextEditingController(text: cfg?.remoteHost ?? '');
    _remotePort = TextEditingController(
      text: (cfg?.remotePort ?? 0) == 0 ? '' : '${cfg?.remotePort}',
    );
    _broadcast = cfg?.broadcast ?? false;
  }

  @override
  void dispose() {
    _localPort.dispose();
    _remoteHost.dispose();
    _remotePort.dispose();
    super.dispose();
  }

  /// 网卡下拉项：所有网卡 + 每张网卡的每个 IPv4。
  List<DropdownMenuItem<String>> get _interfaceItems {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: _anyAddress,
        child: Text('所有网卡（0.0.0.0）'),
      ),
    ];
    for (final iface in widget.interfaces) {
      for (final ip in iface.ipv4Addresses) {
        items.add(DropdownMenuItem(
          value: ip,
          child: Text('${iface.name}（$ip）', overflow: TextOverflow.ellipsis),
        ));
      }
    }
    return items;
  }

  String get _bindValue {
    final validIps = {
      for (final iface in widget.interfaces) ...iface.ipv4Addresses,
    };
    if (_bindAddress.isEmpty || !validIps.contains(_bindAddress)) {
      return _anyAddress;
    }
    return _bindAddress;
  }

  void _submit() {
    final localPort = int.tryParse(_localPort.text.trim()) ?? 0;
    final remotePort = int.tryParse(_remotePort.text.trim()) ?? 0;
    final remoteHost = _remoteHost.text.trim();

    if (_mode == NetMode.tcpServer &&
        (localPort <= 0 || localPort > 65535)) {
      _snack('请填写有效的本地监听端口（1-65535）');
      return;
    }
    if ((_mode == NetMode.tcpClient || _mode == NetMode.udp) &&
        remoteHost.isEmpty) {
      _snack('请填写目标主机地址');
      return;
    }
    if ((_mode == NetMode.tcpClient || _mode == NetMode.udp) &&
        (remotePort <= 0 || remotePort > 65535)) {
      _snack('请填写有效的目标端口（1-65535）');
      return;
    }

    Navigator.of(context).pop(NetConfig(
      mode: _mode,
      bindAddress: _bindValue == _anyAddress ? '' : _bindValue,
      localPort: localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
      broadcast: _mode == NetMode.udp ? _broadcast : false,
    ));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needRemote =
        _mode == NetMode.tcpClient || _mode == NetMode.udp;
    final needLocalPort =
        _mode == NetMode.tcpServer || _mode == NetMode.udp;

    return AlertDialog(
      title: const Text('新建网络连接'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<NetMode>(
                segments: const [
                  ButtonSegment(
                    value: NetMode.tcpClient,
                    label: Text('TCP 客户端'),
                  ),
                  ButtonSegment(
                    value: NetMode.tcpServer,
                    label: Text('TCP 服务端'),
                  ),
                  ButtonSegment(value: NetMode.udp, label: Text('UDP')),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              const SizedBox(height: 18),
              const _FieldLabel('选择网口（自动识别本机 IP）'),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _bindValue,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _interfaceItems,
                onChanged: (v) => setState(() {
                  _bindAddress = (v == _anyAddress || v == null) ? '' : v;
                }),
              ),
              if (needLocalPort) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _localPort,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText:
                        _mode == NetMode.tcpServer ? '本地监听端口' : '本地绑定端口（可空）',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              if (needRemote) ...[
                const SizedBox(height: 14),
                const _FieldLabel('目标地址'),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _remoteHost,
                        decoration: InputDecoration(
                          hintText: _mode == NetMode.udp
                              ? '如 192.168.1.100 或 255.255.255.255'
                              : '如 192.168.1.100',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text(':'),
                    ),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _remotePort,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          hintText: '端口',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_mode == NetMode.udp) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Switch(
                      value: _broadcast,
                      onChanged: (v) => setState(() => _broadcast = v),
                    ),
                    const Text('启用广播发送（SO_BROADCAST）'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('连接')),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
