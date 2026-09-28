import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../../core/ui/send_panel.dart';
import '../../data/raw_usb_service.dart';
import '../../domain/raw_usb_session.dart';
import '../../domain/usb_session_base.dart';
import '../../domain/usb_session_manager.dart';

/// 通用 USB 会话视图：状态栏 + 接口/端点配置 + 接收区 + 发送区。
class RawUsbSessionView extends StatefulWidget {
  const RawUsbSessionView({
    super.key,
    required this.session,
    required this.manager,
    required this.onCloseSession,
  });

  final RawUsbSession session;
  final UsbSessionManager manager;
  final Future<void> Function() onCloseSession;

  @override
  State<RawUsbSessionView> createState() => _RawUsbSessionViewState();
}

class _RawUsbSessionViewState extends State<RawUsbSessionView> {
  bool _showConfig = true;
  late final TextEditingController _readSizeController;
  late final TextEditingController _intervalController;
  late final TextEditingController _timeoutController;

  RawUsbSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _readSizeController =
        TextEditingController(text: session.readSize.toString());
    _intervalController =
        TextEditingController(text: session.pollIntervalMs.toString());
    _timeoutController =
        TextEditingController(text: session.readTimeoutMs.toString());
  }

  @override
  void dispose() {
    _readSizeController.dispose();
    _intervalController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await session.open();
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  void _applyPollConfig() {
    session.updatePollConfig(
      readSize: int.tryParse(_readSizeController.text),
      intervalMs: int.tryParse(_intervalController.text),
      timeoutMs: int.tryParse(_timeoutController.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildStatusBar(context),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  if (_showConfig) _buildConfigPanel(context),
                  if (_showConfig) const Divider(height: 1),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: session,
                      builder: (context, _) => ReceivePanel(
                        entries: session.logs,
                        rxBytes: session.rxBytes,
                        txBytes: session.txBytes,
                        onClear: session.clearLogs,
                        exportNamePrefix: 'usb_raw_${session.device.vidPidHex}',
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints:
                        BoxConstraints(maxHeight: constraints.maxHeight * 0.55),
                    child: SendPanel(
                      controller: session,
                      store: widget.manager,
                      disconnectedHint: '请先打开 USB 设备',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final connected = session.isConnected;
        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: scheme.surfaceContainerLowest,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: connected
                      ? Colors.green
                      : (session.lastError != null
                          ? Colors.red
                          : Colors.grey),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.displayName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      session.device.subtitle,
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connected ? '已打开' : '未打开',
                style: TextStyle(
                  fontSize: 12,
                  color: connected ? Colors.green : scheme.outline,
                ),
              ),
              if (session.receiving) ...[
                const SizedBox(width: 10),
                _Badge(
                  icon: Icons.radio_button_checked,
                  text: '接收中',
                  color: Colors.teal.shade700,
                ),
              ],
              if (session.loopSending) ...[
                const SizedBox(width: 10),
                _Badge(
                  icon: Icons.repeat,
                  text: '循环发送中',
                  color: Colors.orange.shade800,
                ),
              ],
              const SizedBox(width: 8),
              IconButton(
                tooltip: _showConfig ? '隐藏端点配置' : '显示端点配置',
                iconSize: 18,
                onPressed: () => setState(() => _showConfig = !_showConfig),
                icon: Icon(_showConfig
                    ? Icons.account_tree
                    : Icons.account_tree_outlined),
              ),
              connected
                  ? OutlinedButton.icon(
                      onPressed: () => session.close(),
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('关闭设备'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('打开设备'),
                    ),
              IconButton(
                tooltip: '关闭会话',
                onPressed: widget.onCloseSession,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConfigPanel(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final connected = session.isConnected;
        return Container(
          height: 230,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('接口：', style: TextStyle(fontSize: 12)),
                  DropdownButton<int>(
                    value: session.claimedInterface,
                    isDense: true,
                    hint: const Text('未认领', style: TextStyle(fontSize: 12)),
                    items: [
                      for (final iface in session.interfaces)
                        DropdownMenuItem(
                          value: iface.number,
                          child: Text('接口 ${iface.number}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                    onChanged: connected
                        ? (n) {
                            if (n != null) {
                              session.selectInterface(n).catchError(_showError);
                            }
                          }
                        : null,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('连续接收', style: TextStyle(fontSize: 12)),
                      Switch(
                        value: session.receiving,
                        onChanged: connected
                            ? (v) {
                                try {
                                  v
                                      ? session.startReceiving()
                                      : session.stopReceiving();
                                } catch (e) {
                                  _showError(e);
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                  _numberField(
                    label: '读长',
                    controller: _readSizeController,
                    enabled: connected,
                  ),
                  _numberField(
                    label: '间隔ms',
                    controller: _intervalController,
                    enabled: connected,
                  ),
                  _numberField(
                    label: '超时ms',
                    controller: _timeoutController,
                    enabled: connected,
                  ),
                  OutlinedButton.icon(
                    onPressed: connected
                        ? () => session.readOnce().catchError(_showError)
                        : null,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('读一次'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(child: _buildEndpointList(context, connected)),
            ],
          ),
        );
      },
    );
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
  }) {
    return SizedBox(
      width: 92,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(fontSize: 12),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          border: const OutlineInputBorder(),
        ),
        onEditingComplete: _applyPollConfig,
      ),
    );
  }

  Widget _buildEndpointList(BuildContext context, bool connected) {
    if (session.interfaces.isEmpty) {
      return Center(
        child: Text(
          connected ? '未发现接口/端点' : '打开设备后显示接口与端点',
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final iface in session.interfaces) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: iface.number == session.claimedInterface
                ? Colors.teal.withValues(alpha: 0.08)
                : null,
            child: Row(
              children: [
                Icon(
                  Icons.layers,
                  size: 14,
                  color: iface.number == session.claimedInterface
                      ? Colors.teal.shade700
                      : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text('接口 ${iface.number}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (iface.number == session.claimedInterface)
                  Text('已认领',
                      style: TextStyle(
                          fontSize: 11, color: Colors.teal.shade700)),
                const Spacer(),
                if (iface.number != session.claimedInterface)
                  TextButton(
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: connected
                        ? () => session
                            .selectInterface(iface.number)
                            .catchError(_showError)
                        : null,
                    child: const Text('切换', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          for (final ep in iface.endpoints)
            _EndpointTile(
              endpoint: ep,
              connected: connected,
              selectedAsIn: ep.address == session.inEndpoint,
              selectedAsOut: ep.address == session.outEndpoint,
              onTap: () {
                if (!connected) return;
                if (ep.isIn) {
                  session.selectInEndpoint(ep.address);
                } else {
                  session.selectOutEndpoint(ep.address);
                }
              },
            ),
        ],
      ],
    );
  }
}

/// 单个端点行：方向图标 + 地址/类型/包长 + 当前角色标记。
class _EndpointTile extends StatelessWidget {
  const _EndpointTile({
    required this.endpoint,
    required this.connected,
    required this.selectedAsIn,
    required this.selectedAsOut,
    required this.onTap,
  });

  final RawEndpointInfo endpoint;
  final bool connected;
  final bool selectedAsIn;
  final bool selectedAsOut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = selectedAsIn || selectedAsOut;
    return InkWell(
      onTap: connected ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.only(left: 28, right: 12, top: 2, bottom: 2),
        child: Row(
          children: [
            Icon(
              endpoint.isIn ? Icons.south_west : Icons.north_east,
              size: 15,
              color: endpoint.isIn ? Colors.teal : Colors.indigo,
            ),
            const SizedBox(width: 8),
            Text(
              '${endpoint.addressHex} · ${endpoint.transferTypeLabel} · '
              '${endpoint.maxPacketSize} 字节',
              style: TextStyle(
                fontSize: 12,
                color: connected ? null : Theme.of(context).colorScheme.outline,
              ),
            ),
            const Spacer(),
            if (selected)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (selectedAsIn ? Colors.teal : Colors.indigo)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  selectedAsIn ? '接收' : '发送',
                  style: TextStyle(
                    fontSize: 11,
                    color: selectedAsIn
                        ? Colors.teal.shade800
                        : Colors.indigo.shade800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
