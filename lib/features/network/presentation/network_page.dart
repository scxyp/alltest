import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/tiled_layout.dart';
import '../domain/net_session.dart';
import '../domain/net_session_manager.dart';
import 'widgets/net_connection_dialog.dart';
import 'widgets/net_session_view.dart';

/// 网络调试主页面：最多 4 个 TCP/UDP 会话平铺展示。
class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key, required this.manager});

  final NetSessionManager manager;

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  Timer? _pollTimer;
  TripleLayout _tripleLayout = TripleLayout.oneTopTwoBottom;

  @override
  void initState() {
    super.initState();
    // 定时刷新网卡列表：插拔网线 / 切换 Wi-Fi / DHCP 续租后自动识别新 IP。
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      widget.manager.refreshInterfaces();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _newSession() async {
    final manager = widget.manager;
    if (manager.sessions.length >= NetSessionManager.maxSessions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多支持同时打开 4 个网络会话')),
      );
      return;
    }
    await manager.refreshInterfaces();
    if (!mounted) return;

    final config = await NetConnectionDialog.show(
      context,
      interfaces: manager.interfaces,
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

  Future<void> _closeSession(NetSession session) async {
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
            title: const Text('网络调试'),
            actions: [
              if (sessions.length == 3)
                TripleLayoutPicker(
                  value: _tripleLayout,
                  onChanged: (layout) =>
                      setState(() => _tripleLayout = layout),
                ),
              IconButton(
                tooltip: '刷新网卡列表',
                onPressed: manager.refreshInterfaces,
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
                      for (final session in sessions)
                        NetSessionView(
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
          Icon(Icons.lan_outlined,
              size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('还没有网络会话',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '支持 TCP 客户端 / TCP 服务端 / UDP；最多同时打开 4 个会话',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_link),
            label: const Text('新建网络连接'),
          ),
        ],
      ),
    );
  }
}
