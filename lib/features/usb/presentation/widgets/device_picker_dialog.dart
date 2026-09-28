import 'package:flutter/material.dart';

import '../../domain/usb_device_info.dart';
import '../../domain/usb_session_manager.dart';

/// USB 设备选择对话框：在 HID 设备 / 通用 USB 两个列表间切换。
class DevicePickerDialog extends StatefulWidget {
  const DevicePickerDialog({super.key, required this.manager});

  final UsbSessionManager manager;

  /// 弹出选择对话框，返回选中的设备；取消则返回 null。
  static Future<UsbDeviceInfo?> show(
    BuildContext context, {
    required UsbSessionManager manager,
  }) {
    return showDialog<UsbDeviceInfo>(
      context: context,
      builder: (_) => DevicePickerDialog(manager: manager),
    );
  }

  @override
  State<DevicePickerDialog> createState() => _DevicePickerDialogState();
}

class _DevicePickerDialogState extends State<DevicePickerDialog> {
  UsbDeviceKind _kind = UsbDeviceKind.hid;
  final TextEditingController _filterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 打开时强制刷新一次（含字符串描述符）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.manager.refresh();
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          const Text('选择 USB 设备'),
          const SizedBox(width: 12),
          ListenableBuilder(
            listenable: widget.manager,
            builder: (context, _) {
              if (!widget.manager.isEnumerating) return const SizedBox.shrink();
              return const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            },
          ),
          const Spacer(),
          IconButton(
            tooltip: '重新枚举',
            onPressed: () => widget.manager.refresh(),
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        height: 480,
        child: Column(
          children: [
            SegmentedButton<UsbDeviceKind>(
              segments: const [
                ButtonSegment(
                  value: UsbDeviceKind.hid,
                  icon: Icon(Icons.keyboard),
                  label: Text('HID 设备'),
                ),
                ButtonSegment(
                  value: UsbDeviceKind.raw,
                  icon: Icon(Icons.memory),
                  label: Text('通用 USB'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 10),
            if (_kind == UsbDeviceKind.raw) _buildRawHint(scheme),
            if (_kind == UsbDeviceKind.raw) const SizedBox(height: 10),
            TextField(
              controller: _filterController,
              decoration: const InputDecoration(
                labelText: '按名称 / VID:PID / 序列号过滤',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.manager,
                builder: (context, _) => _buildList(scheme),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildRawHint(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '通用 USB 模式要求设备驱动为 WinUSB。若列表为空或打开失败，'
              '请先用 Zadig 将该设备驱动替换为 WinUSB 后重新枚举。',
              style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme scheme) {
    final manager = widget.manager;
    final devices =
        _kind == UsbDeviceKind.hid ? manager.hidDevices : manager.rawDevices;
    final error = _kind == UsbDeviceKind.hid
        ? manager.hidEnumerateError
        : manager.rawEnumerateError;
    final filter = _filterController.text.trim().toLowerCase();
    final busy = manager.busyIds;

    final filtered = filter.isEmpty
        ? devices
        : devices.where((d) {
            return d.displayName.toLowerCase().contains(filter) ||
                d.vidPidHex.toLowerCase().contains(filter) ||
                d.id.toLowerCase().contains(filter) ||
                (d.serial ?? '').toLowerCase().contains(filter);
          }).toList();

    if (error != null && devices.isEmpty) {
      return _centeredHint(scheme, '枚举失败：$error\n可点击右上角刷新重试');
    }
    if (filtered.isEmpty) {
      return _centeredHint(
        scheme,
        manager.isEnumerating ? '正在枚举设备...' : '未发现设备',
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: filtered.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: Colors.grey.shade200),
      itemBuilder: (context, index) {
        final device = filtered[index];
        final isBusy = busy.contains(device.id);
        return ListTile(
          dense: true,
          leading: Icon(
            _kind == UsbDeviceKind.hid ? Icons.keyboard : Icons.memory,
            size: 22,
            color: isBusy
                ? Colors.grey
                : (_kind == UsbDeviceKind.hid
                    ? const Color(0xFF6C5CE7)
                    : Colors.teal),
          ),
          title: Text(
            device.displayName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isBusy ? Colors.grey : null,
            ),
          ),
          subtitle: Text(
            device.subtitle,
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
          trailing: isBusy
              ? const Text('已打开',
                  style: TextStyle(fontSize: 12, color: Colors.grey))
              : null,
          enabled: !isBusy,
          onTap: () => Navigator.of(context).pop(device),
        );
      },
    );
  }

  Widget _centeredHint(ColorScheme scheme, String text) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.outline),
      ),
    );
  }
}
