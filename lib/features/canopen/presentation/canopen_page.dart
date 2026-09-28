import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/tiled_layout.dart';
import '../domain/canopen_config.dart';
import '../domain/canopen_session.dart';
import '../domain/canopen_session_manager.dart';
import 'widgets/canopen_connection_dialog.dart';
import 'widgets/canopen_session_view.dart';

/// CANopen 调试主页面：最多 4 个适配器会话以平铺方式同时展示。
class CanOpenPage extends StatefulWidget {
  const CanOpenPage({super.key, required this.manager});

  final CanOpenSessionManager manager;

  @override
  State<CanOpenPage> createState() => _CanOpenPageState();
}

class _CanOpenPageState extends State<CanOpenPage> {
  Timer? _pollTimer;
  TripleLayout _tripleLayout = TripleLayout.oneTopTwoBottom;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      widget.manager.refreshPorts();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _newSession() async {
    final manager = widget.manager;
    if (manager.sessions.length >= CanOpenSessionManager.maxSessions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多支持同时打开 4 个 CANopen 会话')),
      );
      return;
    }
    manager.refreshPorts();

    final last = manager.lastConfig;
    final initial = (last != null && last.portName.isNotEmpty)
        ? last
        : CanOpenConfig(
            portName: manager.availablePorts.isNotEmpty
                ? manager.availablePorts.first
                : '',
          );

    final config = await CanOpenConnectionDialog.show(
      context,
      ports: manager.availablePorts,
      busyPorts: manager.busyPorts,
      initial: initial,
      actionText: '连接',
    );
    if (config == null) return;
    try {
      await manager.openSession(config);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _closeSession(CanOpenSession session) async {
    if (session.isConnected) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('关闭会话'),
          content: Text('将断开 ${session.config.portName}，确定关闭该会话吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await widget.manager.closeSession(session.id);
  }

  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final sessions = manager.sessions;
        return Scaffold(
          appBar: AppBar(
            title: const Text('CANopen 调试'),
            actions: [
              if (sessions.length == 3)
                TripleLayoutPicker(
                  value: _tripleLayout,
                  onChanged: (layout) =>
                      setState(() => _tripleLayout = layout),
                ),
              IconButton(
                tooltip: '刷新端口列表',
                onPressed: manager.refreshPorts,
                icon: const Icon(Icons.refresh),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _newSession,
                  icon: const Icon(Icons.add),
                  label: const Text('新建连接'),
                ),
              ),
            ],
          ),
          body: sessions.isEmpty
              ? _EmptyView(onCreate: _newSession)
              : Padding(
                  padding: const EdgeInsets.all(6),
                  child: TiledLayout(
                    tripleLayout: _tripleLayout,
                    children: [
                      for (var i = 0; i < sessions.length; i++)
                        CanOpenSessionView(
                          key: ValueKey(sessions[i].id),
                          session: sessions[i],
                          manager: widget.manager,
                          onCloseSession: () => _closeSession(sessions[i]),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.settings_input_component_outlined,
              size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('还没有 CANopen 会话',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '通过 SLCAN 串口协议连接 CAN 适配器，在 CAN 之上实现 CANopen 协议层；支持 SDO Expedited 读写、NMT 节点控制、Heartbeat；最多同时打开 4 个',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_link),
            label: const Text('新建 CANopen 连接'),
          ),
        ],
      ),
    );
  }
}
