import 'package:flutter/material.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../../core/ui/send_panel.dart';
import '../../domain/serial_session.dart';
import '../../domain/serial_session_manager.dart';
import 'connection_dialog.dart';

/// 单个串口会话的完整视图：连接状态栏 + 接收区 + 发送区。
class SessionView extends StatefulWidget {
  const SessionView({
    super.key,
    required this.session,
    required this.manager,
    required this.onCloseSession,
  });

  final SerialSession session;
  final SerialSessionManager manager;

  /// 关闭并移除该会话（由页面处理确认逻辑）。
  final Future<void> Function() onCloseSession;

  @override
  State<SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<SessionView> {
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
    final session = widget.session;
    final manager = widget.manager;
    final config = await ConnectionDialog.show(
      context,
      ports: manager.availablePorts,
      busyPorts: manager.busyPorts,
      initial: session.config,
      actionText: '保存',
    );
    if (config != null) {
      session.updateConfig(config);
    }
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
                    session.config.portName,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      session.config.summary,
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'Consolas'),
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
                          label: const Text('关闭串口'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: _toggleConnection,
                          icon: const Icon(Icons.power, size: 18),
                          label: const Text('打开串口'),
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
              // 发送区最多占面板高度 55%，超出部分内部滚动，
              // 保证并排 / 田字布局下小面板也不会溢出。
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
                            'serial_${session.config.portName}',
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
                      disconnectedHint: '请先打开串口',
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
