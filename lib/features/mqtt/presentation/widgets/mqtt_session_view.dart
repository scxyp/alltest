import 'package:flutter/material.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../../core/ui/send_panel.dart';
import '../../domain/mqtt_config.dart';
import '../../domain/mqtt_session.dart';
import '../../domain/mqtt_session_manager.dart';
import 'mqtt_connection_dialog.dart';

/// 单个 MQTT 会话的完整视图：状态栏 + 订阅区 + 接收区 + 发布区 + 发送区。
class MqttSessionView extends StatefulWidget {
  const MqttSessionView({
    super.key,
    required this.session,
    required this.manager,
    required this.onCloseSession,
  });

  final MqttSession session;
  final MqttSessionManager manager;
  final Future<void> Function() onCloseSession;

  @override
  State<MqttSessionView> createState() => _MqttSessionViewState();
}

class _MqttSessionViewState extends State<MqttSessionView> {
  final _subController = TextEditingController();
  final _pubController = TextEditingController();
  MqttQosLevel _subQos = MqttQosLevel.atMostOnce;
  bool _showSubPanel = false;

  @override
  void dispose() {
    _subController.dispose();
    _pubController.dispose();
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
    final config = await MqttConnectionDialog.show(
      context,
      initial: widget.session.config,
    );
    if (config != null) widget.session.updateConfig(config);
  }

  void _subscribe() {
    final topic = _subController.text.trim();
    if (topic.isEmpty) return;
    try {
      widget.session.subscribe(topic, _subQos);
      _subController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
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
                  const Text(
                    'MQTT',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                  if (session.loopSending) ...[
                    const SizedBox(width: 10),
                    _LoopBadge(),
                  ],
                  const Spacer(),
                  // 订阅面板开关
                  IconButton(
                    tooltip: _showSubPanel ? '收起订阅' : '展开订阅',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _showSubPanel = !_showSubPanel),
                    icon: Icon(
                      _showSubPanel ? Icons.unfold_less : Icons.filter_list,
                      size: 19,
                    ),
                  ),
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
        // --- 订阅区（可折叠）---
        ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            if (!_showSubPanel && session.subscriptions.isEmpty) {
              return const SizedBox.shrink();
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_showSubPanel)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _subController,
                            enabled: session.isConnected,
                            style: const TextStyle(
                                fontFamily: 'Consolas', fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: '主题过滤器，如 sensor/#',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                            ),
                            onSubmitted: (_) => _subscribe(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _QosDropdown(
                          value: _subQos,
                          onChanged: (v) =>
                              setState(() => _subQos = v),
                        ),
                        const SizedBox(width: 6),
                        FilledButton.tonal(
                          onPressed: session.isConnected ? _subscribe : null,
                          child: const Text('订阅'),
                        ),
                      ],
                    ),
                  if (session.subscriptions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final entry in session.subscriptions.entries)
                            Chip(
                              label: Text(
                                '${entry.key}  Q${entry.value.index}',
                                style: const TextStyle(
                                    fontSize: 11, fontFamily: 'Consolas'),
                              ),
                              onDeleted: session.isConnected
                                  ? () =>
                                      session.unsubscribe(entry.key)
                                  : null,
                              deleteIconColor: Colors.red.shade400,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
        // --- 接收区 + 发布区 + 发送区 ---
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
                        exportNamePrefix: 'mqtt',
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  // --- 发布选项行 ---
                  ListenableBuilder(
                    listenable: session,
                    builder: (context, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        child: Row(
                          children: [
                            Text('发布主题',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _pubController,
                                enabled: session.isConnected,
                                style: const TextStyle(
                                    fontFamily: 'Consolas', fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: '如 cmd/device/led',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                ),
                                onChanged: (v) =>
                                    session.publishTopic = v,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _QosDropdown(
                              value: session.publishQos,
                              onChanged: (v) =>
                                  session.publishQos = v,
                            ),
                            const SizedBox(width: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: session.retain,
                                    onChanged: (v) =>
                                        session.retain = v ?? false,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Text('Retain',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline)),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.45,
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

/// QoS 下拉选择器。
class _QosDropdown extends StatelessWidget {
  const _QosDropdown({required this.value, required this.onChanged});

  final MqttQosLevel value;
  final ValueChanged<MqttQosLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<MqttQosLevel>(
      value: value,
      isDense: true,
      underline: const SizedBox(),
      items: [
        for (final q in MqttQosLevel.values)
          DropdownMenuItem(value: q, child: Text('Q${q.index}')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _LoopBadge extends StatelessWidget {
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
