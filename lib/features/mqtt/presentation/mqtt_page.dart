import 'package:flutter/material.dart';

import '../../../core/ui/tiled_layout.dart';
import '../domain/mqtt_session.dart';
import '../domain/mqtt_session_manager.dart';
import 'widgets/mqtt_connection_dialog.dart';
import 'widgets/mqtt_session_view.dart';

/// MQTT 调试主页面：最多 4 个 Broker 连接平铺展示。
class MqttPage extends StatefulWidget {
  const MqttPage({super.key, required this.manager});

  final MqttSessionManager manager;

  @override
  State<MqttPage> createState() => _MqttPageState();
}

class _MqttPageState extends State<MqttPage> {
  TripleLayout _tripleLayout = TripleLayout.oneTopTwoBottom;

  Future<void> _newSession() async {
    final manager = widget.manager;
    if (manager.sessions.length >= MqttSessionManager.maxSessions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多支持同时打开 4 个 MQTT 会话')),
      );
      return;
    }

    final config = await MqttConnectionDialog.show(
      context,
      initial: manager.lastConfig,
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

  Future<void> _closeSession(MqttSession session) async {
    if (session.isConnected) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('关闭会话'),
          content: Text('将断开 ${session.config.summary}，确定关闭吗？'),
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
            title: const Text('MQTT 调试'),
            actions: [
              if (sessions.length == 3)
                TripleLayoutPicker(
                  value: _tripleLayout,
                  onChanged: (layout) =>
                      setState(() => _tripleLayout = layout),
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
                      for (final session in sessions)
                        MqttSessionView(
                          key: ValueKey(session.id),
                          session: session,
                          manager: manager,
                          onCloseSession: () => _closeSession(session),
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
          Icon(Icons.hub_outlined,
              size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('还没有 MQTT 会话',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '连接到 MQTT Broker，支持订阅/发布/QoS 0-2/保留消息/遗嘱；最多同时打开 4 个会话',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_link),
            label: const Text('新建 MQTT 连接'),
          ),
        ],
      ),
    );
  }
}
