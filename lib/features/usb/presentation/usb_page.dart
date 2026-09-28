import 'package:flutter/material.dart';

import '../../../core/ui/tiled_layout.dart';
import '../domain/hid_usb_session.dart';
import '../domain/raw_usb_session.dart';
import '../domain/usb_session_base.dart';
import '../domain/usb_session_manager.dart';
import 'widgets/device_picker_dialog.dart';
import 'widgets/hid_session_view.dart';
import 'widgets/raw_usb_session_view.dart';

/// USB 调试主页面：枚举 HID / 通用 USB 设备 → 打开 → 多会话平铺展示。
class UsbPage extends StatefulWidget {
  const UsbPage({super.key, required this.manager});

  final UsbSessionManager manager;

  @override
  State<UsbPage> createState() => _UsbPageState();
}

class _UsbPageState extends State<UsbPage> {
  TripleLayout _tripleLayout = TripleLayout.oneTopTwoBottom;

  Future<void> _newSession() async {
    final manager = widget.manager;
    if (manager.sessions.length >= UsbSessionManager.maxSessions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多支持同时打开 4 个 USB 会话')),
      );
      return;
    }

    final device = await DevicePickerDialog.show(context, manager: manager);
    if (device == null) return;
    try {
      await manager.openSession(device);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _closeSession(UsbSessionBase session) async {
    if (session.isConnected) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('关闭会话'),
          content: Text('将关闭 ${session.displayName}，确定关闭该会话吗？'),
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

  Widget _buildSessionView(UsbSessionBase session) {
    if (session is HidUsbSession) {
      return HidSessionView(
        key: ValueKey(session.id),
        session: session,
        manager: widget.manager,
        onCloseSession: () => _closeSession(session),
      );
    }
    if (session is RawUsbSession) {
      return RawUsbSessionView(
        key: ValueKey(session.id),
        session: session,
        manager: widget.manager,
        onCloseSession: () => _closeSession(session),
      );
    }
    return const SizedBox.shrink();
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
            title: const Text('USB 调试'),
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
                  label: const Text('打开设备'),
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
                      for (final session in sessions) _buildSessionView(session),
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
          Icon(Icons.usb,
              size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('还没有打开的 USB 设备',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '支持 HID 设备与通用 USB（需 WinUSB 驱动）；最多同时打开 4 个会话',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.usb),
            label: const Text('选择 USB 设备'),
          ),
        ],
      ),
    );
  }
}
