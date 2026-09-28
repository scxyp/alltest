import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/ble_device_info.dart';
import '../../domain/ble_session_manager.dart';

/// BLE 扫描对话框：实时展示扫描到的设备列表，用户选中后返回。
class ScanDialog extends StatefulWidget {
  const ScanDialog({super.key, required this.manager});

  final BleSessionManager manager;

  /// 弹出扫描对话框，返回用户选中的 [BleDeviceInfo]；取消则返回 null。
  static Future<BleDeviceInfo?> show(
    BuildContext context, {
    required BleSessionManager manager,
  }) {
    return showDialog<BleDeviceInfo>(
      context: context,
      builder: (_) => ScanDialog(manager: manager),
    );
  }

  @override
  State<ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<ScanDialog> {
  late final TextEditingController _filterController;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController();
    // 启动扫描
    widget.manager.startScan();
    // 扫描 15 秒后自动停止（用户也可手动停止）
    _scanTimer = Timer(const Duration(seconds: 15), () {
      if (widget.manager.isScanning) widget.manager.stopScan();
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _filterController.dispose();
    if (widget.manager.isScanning) widget.manager.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Text('扫描 BLE 设备'),
          const SizedBox(width: 12),
          ListenableBuilder(
            listenable: widget.manager,
            builder: (context, _) {
              if (!widget.manager.isScanning) return const SizedBox.shrink();
              return const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            },
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: widget.manager,
            builder: (context, _) {
              return TextButton.icon(
                onPressed: widget.manager.isScanning
                    ? () => widget.manager.stopScan()
                    : () => widget.manager.startScan(),
                icon: Icon(widget.manager.isScanning
                    ? Icons.stop
                    : Icons.play_arrow),
                label: Text(widget.manager.isScanning ? '停止' : '重新扫描'),
              );
            },
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _filterController,
              decoration: const InputDecoration(
                labelText: '按名称过滤',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.manager,
                builder: (context, _) {
                  final results = widget.manager.scanResults;
                  final filter = _filterController.text.toLowerCase();
                  final filtered = filter.isEmpty
                      ? results
                      : results
                          .where((d) =>
                              (d.name ?? '').toLowerCase().contains(filter))
                          .toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        widget.manager.isScanning ? '正在搜索...' : '未发现设备',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final device = filtered[index];
                      final isBusy =
                          widget.manager.busyDeviceIds.contains(device.deviceId);
                      return ListTile(
                        leading: Icon(
                          Icons.bluetooth,
                          size: 22,
                          color: isBusy ? Colors.grey : const Color(0xFF4A90D9),
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
                          device.deviceId,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (device.rssi != null)
                              Text(
                                '${device.rssi} dBm',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: device.rssi! > -60
                                      ? Colors.green
                                      : device.rssi! > -80
                                          ? Colors.orange
                                          : Colors.red,
                                ),
                              ),
                            if (isBusy) ...[
                              const SizedBox(width: 8),
                              const Text('已连接',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            ],
                          ],
                        ),
                        enabled: !isBusy,
                        onTap: () {
                          widget.manager.stopScan();
                          Navigator.of(context).pop(device);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.manager.stopScan();
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
      ],
    );
  }
}
