import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/tiled_layout.dart';
import '../domain/serial_config.dart';
import '../domain/serial_session.dart';
import '../domain/serial_session_manager.dart';
import 'widgets/connection_dialog.dart';
import 'widgets/session_view.dart';

/// 串口调试主页面：最多 4 个会话以平铺方式同时展示。
///
/// - 1 个：占满
/// - 2 个：左右并排
/// - 3 个：上一下二 / 上二下一 / 三栏并排（可选）
/// - 4 个：田字排布
class SerialPage extends StatefulWidget {
  const SerialPage({super.key, required this.manager});

  final SerialSessionManager manager;

  @override
  State<SerialPage> createState() => _SerialPageState();
}

class _SerialPageState extends State<SerialPage> {
  Timer? _pollTimer;
  TripleLayout _tripleLayout = TripleLayout.oneTopTwoBottom;

  @override
  void initState() {
    super.initState();
    // 定时刷新端口列表：方便热插拔后看到新设备，
    // 同时驱动"设备被拔出"检测（端口从枚举中消失即判定断开）。
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
    if (manager.sessions.length >= SerialSessionManager.maxSessions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('最多支持同时打开 4 个串口会话'),
        ),
      );
      return;
    }
    manager.refreshPorts();

    final last = manager.lastConfig;
    final initial = (last != null && last.portName.isNotEmpty)
        ? last
        : SerialConfig(
            portName: manager.availablePorts.isNotEmpty
                ? manager.availablePorts.first
                : '',
          );

    final config = await ConnectionDialog.show(
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

  Future<void> _closeSession(SerialSession session) async {
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
            title: const Text('串口调试'),
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
                        SessionView(
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
          Icon(Icons.cable_outlined,
              size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('还没有打开的串口',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '点击“新建连接”打开一个串口；最多支持同时打开 4 个',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_link),
            label: const Text('新建串口连接'),
          ),
        ],
      ),
    );
  }
}
