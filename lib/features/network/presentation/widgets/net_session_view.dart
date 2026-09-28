import 'package:flutter/material.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../../core/ui/send_panel.dart';
import '../../domain/net_config.dart';
import '../../domain/net_session.dart';
import '../../domain/net_session_manager.dart';
import 'net_connection_dialog.dart';

/// 单个网络会话的完整视图：状态栏 + 接收区 + 发送区。
class NetSessionView extends StatefulWidget {
  const NetSessionView({
    super.key,
    required this.session,
    required this.manager,
    required this.onCloseSession,
  });

  final NetSession session;
  final NetSessionManager manager;
  final Future<void> Function() onCloseSession;

  @override
  State<NetSessionView> createState() => _NetSessionViewState();
}

class _NetSessionViewState extends State<NetSessionView> {
  Future<void> _toggleConnection() async {
    final session = widget.session;
    if (session.isConnected) {
      await session.disconnect();
      return;
    }
    try {
      await session.connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _editConfig() async {
    final config = await NetConnectionDialog.show(
      context,
      interfaces: widget.manager.interfaces,
      initial: widget.session.config,
    );
    if (config != null) widget.session.updateConfig(config);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Column(
      children: [
        ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final connected = session.isConnected;
            final scheme = Theme.of(context).colorScheme;
            final isServer = session.config.mode == NetMode.tcpServer;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  Text(
                    session.config.mode.label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        session.config.summary,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'Consolas'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    connected ? '已连接' : '未连接',
                    style: TextStyle(
                      fontSize: 12,
                      color: connected ? Colors.green : scheme.outline,
                    ),
                  ),
                  if (isServer && connected) ...[
                    const SizedBox(width: 10),
                    _PeerSelector(session: session),
                  ],
                  if (session.loopSending) ...[
                    const SizedBox(width: 10),
                    const _LoopBadge(),
                  ],
                  const Spacer(),
                  if (!connected)
                    TextButton.icon(
                      onPressed: _editConfig,
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('参数'),
                    ),
                  const SizedBox(width: 4),
                  connected
                      ? OutlinedButton.icon(
                          onPressed: _toggleConnection,
                          icon: const Icon(Icons.link_off, size: 18),
                          label: const Text('断开'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: _toggleConnection,
                          icon: const Icon(Icons.power, size: 18),
                          label: const Text('连接'),
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
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  Expanded(
                    child: ListenableBuilder(
                      listenable: session,
                      builder: (context, _) => ReceivePanel(
                        entries: session.logs,
                        rxBytes: session.rxBytes,
                        txBytes: session.txBytes,
                        onClear: session.clearLogs,
                        exportNamePrefix:
                            'net_${session.config.mode.name}',
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.55,
                    ),
                    child: SendPanel(
                      controller: session,
                      store: widget.manager,
                      disconnectedHint: '请先建立连接',
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
}

/// TCP 服务端模式下选择发送目标：全部客户端 / 指定客户端。
class _PeerSelector extends StatelessWidget {
  const _PeerSelector({required this.session});

  final NetSession session;

  @override
  Widget build(BuildContext context) {
    final peers = session.peers;
    return PopupMenuButton<String?>(
      tooltip: '选择发送目标',
      onSelected: session.setTargetPeer,
      itemBuilder: (_) => [
        const PopupMenuItem<String?>(
          value: null,
          child: Text('发送给：全部客户端'),
        ),
        const PopupMenuDivider(),
        for (final peer in peers)
          PopupMenuItem<String?>(
            value: peer.id,
            child: Text(peer.label,
                style: const TextStyle(fontFamily: 'Consolas')),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices,
                size: 15, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 5),
            Text(
              _targetLabel(peers),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  String _targetLabel(List<NetPeer> peers) {
    if (session.targetPeerId == null) return '全部客户端 (${peers.length})';
    for (final peer in peers) {
      if (peer.id == session.targetPeerId) return peer.label;
    }
    return '指定客户端';
  }
}

class _LoopBadge extends StatelessWidget {
  const _LoopBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.repeat, size: 13, color: Colors.orange.shade800),
          const SizedBox(width: 4),
          Text(
            '循环发送中',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
          ),
        ],
      ),
    );
  }
}
