import 'package:flutter/material.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../../core/ui/send_panel.dart';
import '../../domain/ble_session.dart';
import '../../domain/ble_session_manager.dart';
import 'service_characteristic_tree.dart';

/// 单个 BLE 会话的完整视图：连接状态栏 + GATT 树 + 接收区 + 发送区。
class SessionView extends StatefulWidget {
  const SessionView({
    super.key,
    required this.session,
    required this.manager,
    required this.onCloseSession,
  });

  final BleSession session;
  final BleSessionManager manager;

  final Future<void> Function() onCloseSession;

  @override
  State<SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<SessionView> {
  bool _showGattTree = true;

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

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Column(
      children: [
        // --- 状态栏 ---
        ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final connected = session.isConnected;
            final scheme = Theme.of(context).colorScheme;
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
                  Expanded(
                    child: Text(
                      session.displayName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
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
                  if (session.loopSending) ...[
                    const SizedBox(width: 10),
                    const _LoopBadge(),
                  ],
                  const SizedBox(width: 8),
                  // GATT 树切换
                  IconButton(
                    tooltip: _showGattTree ? '隐藏 GATT 树' : '显示 GATT 树',
                    iconSize: 18,
                    onPressed: () =>
                        setState(() => _showGattTree = !_showGattTree),
                    icon: Icon(_showGattTree
                        ? Icons.account_tree
                        : Icons.account_tree_outlined),
                  ),
                  connected
                      ? OutlinedButton.icon(
                          onPressed: _toggleConnection,
                          icon: const Icon(Icons.bluetooth_disabled, size: 18),
                          label: const Text('断开'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: _toggleConnection,
                          icon: const Icon(Icons.bluetooth_connected, size: 18),
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
        // --- 主体 ---
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  // GATT 服务 / 特征树（可折叠）
                  if (_showGattTree)
                    SizedBox(
                      height: 180,
                      child: ListenableBuilder(
                        listenable: session,
                        builder: (context, _) =>
                            ServiceCharacteristicTree(session: session),
                      ),
                    ),
                  if (_showGattTree)
                    const Divider(height: 1),
                  // 接收面板
                  Expanded(
                    child: ListenableBuilder(
                      listenable: session,
                      builder: (context, _) => ReceivePanel(
                        entries: session.logs,
                        rxBytes: session.rxBytes,
                        txBytes: session.txBytes,
                        onClear: session.clearLogs,
                        exportNamePrefix: 'ble_${session.deviceId}',
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  // 发送面板
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.55,
                    ),
                    child: SendPanel(
                      controller: session,
                      store: widget.manager,
                      disconnectedHint: '请先连接 BLE 设备',
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
