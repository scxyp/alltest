import 'package:flutter/material.dart';

import '../../../core/ui/tiled_layout.dart';
import '../domain/ble_session.dart';
import '../domain/ble_session_manager.dart';
import 'widgets/scan_dialog.dart';
import 'widgets/session_view.dart';

/// 蓝牙调试主页面：扫描 BLE 设备 → 连接 → 多会话平铺展示。
///
/// - 1 个：占满
/// - 2 个：左右并排
/// - 3 个：上一下二 / 上二下一 / 三栏并排（可选）
/// - 4 个：田字排布
class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key, required this.manager});

  final BleSessionManager manager;

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  TripleLayout _tripleLayout = TripleLayout.oneTopTwoBottom;

  Future<void> _newSession() async {
    final manager = widget.manager;
    if (manager.sessions.length >= BleSessionManager.maxSessions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多支持同时打开 4 个 BLE 会话')),
      );
      return;
    }

    final device = await ScanDialog.show(context, manager: manager);
    if (device == null) return;
    try {
      await manager.openSession(device);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _closeSession(BleSession session) async {
    if (session.isConnected) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('关闭会话'),
          content: Text('将断开 ${session.displayName}，确定关闭该会话吗？'),
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
            title: const Text('蓝牙调试'),
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
                  label: const Text('扫描连接'),
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
          Icon(Icons.bluetooth,
              size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('还没有连接的 BLE 设备',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '点击"扫描连接"搜索附近的 BLE 设备；最多支持同时连接 4 个',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('扫描 BLE 设备'),
          ),
        ],
      ),
    );
  }
}
