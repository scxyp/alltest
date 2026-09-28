import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../../core/ui/send_panel.dart';
import '../../domain/can_session.dart';
import '../../domain/can_session_manager.dart';
import 'can_connection_dialog.dart';

/// 单个 CAN 会话的完整视图：状态栏 + 帧属性区 + 接收区 + 发送区。
class CanSessionView extends StatefulWidget {
  const CanSessionView({
    super.key,
    required this.session,
    required this.manager,
    required this.onCloseSession,
  });

  final CanSession session;
  final CanSessionManager manager;

  /// 关闭并移除该会话（由页面处理确认逻辑）。
  final Future<void> Function() onCloseSession;

  @override
  State<CanSessionView> createState() => _CanSessionViewState();
}

class _CanSessionViewState extends State<CanSessionView> {
  late final TextEditingController _idController;

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController(
      text: widget.session.frameId.toRadixString(16).toUpperCase(),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

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
    final config = await CanConnectionDialog.show(
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

  void _onIdChanged(String value) {
    final hex = value.trim().replaceAll(RegExp(r'^0[xX]'), '');
    final id = int.tryParse(hex, radix: 16);
    if (id != null) {
      widget.session.frameId = id;
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
                      session.config.canBitrate.label,
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
        // --- 帧属性行（ID / 扩展 / 远程）---
        ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Text('帧 ID',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _idController,
                      enabled: session.isConnected,
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 13),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-FxX]')),
                      ],
                      decoration: const InputDecoration(
                        prefixText: '0x',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                      ),
                      onChanged: _onIdChanged,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ToggleChip(
                    label: '扩展帧',
                    selected: session.extended,
                    onChanged: session.isConnected
                        ? (v) => session.extended = v
                        : null,
                  ),
                  const SizedBox(width: 6),
                  _ToggleChip(
                    label: '远程帧',
                    selected: session.remote,
                    onChanged: session.isConnected
                        ? (v) => session.remote = v
                        : null,
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
        // --- 接收区 + 发送区 ---
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
                            'can_${session.config.portName}',
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
                      disconnectedHint: '请先连接 CAN 适配器',
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

/// 帧属性切换芯片。
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
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
