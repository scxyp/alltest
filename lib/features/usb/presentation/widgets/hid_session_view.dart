import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../../core/ui/send_panel.dart';
import '../../../../core/util/data_format.dart';
import '../../domain/hid_usb_session.dart';
import '../../domain/usb_session_base.dart';
import '../../domain/usb_session_manager.dart';
import 'report_descriptor_dialog.dart';

/// 单个 HID 会话视图：状态栏 + HID 工具条 + 接收区 + 发送区。
class HidSessionView extends StatefulWidget {
  const HidSessionView({
    super.key,
    required this.session,
    required this.manager,
    required this.onCloseSession,
  });

  final HidUsbSession session;
  final UsbSessionManager manager;
  final Future<void> Function() onCloseSession;

  @override
  State<HidSessionView> createState() => _HidSessionViewState();
}

class _HidSessionViewState extends State<HidSessionView> {
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Column(
      children: [
        _buildStatusBar(context, session),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  _buildToolbar(context, session),
                  const Divider(height: 1),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: session,
                      builder: (context, _) => ReceivePanel(
                        entries: session.logs,
                        rxBytes: session.rxBytes,
                        txBytes: session.txBytes,
                        onClear: session.clearLogs,
                        exportNamePrefix: 'usb_hid_${session.device.vidPidHex}',
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints:
                        BoxConstraints(maxHeight: constraints.maxHeight * 0.55),
                    child: SendPanel(
                      controller: session,
                      store: widget.manager,
                      disconnectedHint: '请先打开 HID 设备',
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

  Widget _buildStatusBar(BuildContext context, HidUsbSession session) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final connected = session.isConnected;
        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.displayName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      session.device.subtitle,
                      style:
                          TextStyle(fontSize: 11, color: scheme.outline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connected ? '已打开' : '未打开',
                style: TextStyle(
                  fontSize: 12,
                  color: connected ? Colors.green : scheme.outline,
                ),
              ),
              if (session.loopSending) ...[
                const SizedBox(width: 10),
                const _LoopBadge(),
              ],
              const SizedBox(width: 8),
              connected
                  ? OutlinedButton.icon(
                      onPressed: () => session.close(),
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('关闭设备'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () => _open(session),
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('打开设备'),
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
    );
  }

  Widget _buildToolbar(BuildContext context, HidUsbSession session) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final connected = session.isConnected;
        return Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Report ID:', style: TextStyle(fontSize: 12)),
              SizedBox(
                width: 64,
                child: TextFormField(
                  initialValue: session.reportId.toString(),
                  enabled: connected,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (v) =>
                      session.setReportId(int.tryParse(v) ?? 0),
                ),
              ),
              FilterChip(
                label: const Text('中断 OUT 端点', style: TextStyle(fontSize: 12)),
                selected: session.useInterruptOut,
                onSelected:
                    connected ? (v) => session.setUseInterruptOut(v) : null,
              ),
              OutlinedButton.icon(
                onPressed: connected ? () => _featureRead(session) : null,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Feature 读'),
              ),
              OutlinedButton.icon(
                onPressed: connected ? () => _featureWrite(session) : null,
                icon: const Icon(Icons.upload, size: 16),
                label: const Text('Feature 写'),
              ),
              OutlinedButton.icon(
                onPressed: connected ? () => _showDescriptor(session) : null,
                icon: const Icon(Icons.account_tree_outlined, size: 16),
                label: const Text('报告描述符'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _open(HidUsbSession session) async {
    try {
      await session.open();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _featureRead(HidUsbSession session) async {
    final result = await _PromptDialog.show(
      context,
      title: '读取 Feature Report',
      confirmText: '读取',
      fields: const [
        _PromptField(key: 'rid', label: 'Report ID (0-255)', initial: '0'),
        _PromptField(
            key: 'size', label: '缓冲区长度', initial: '1024', required: true),
      ],
    );
    if (result == null) return;
    try {
      await session.readFeatureReport(
        int.tryParse(result['rid'] ?? '') ?? 0,
        bufferSize: int.tryParse(result['size'] ?? '') ?? 1024,
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _featureWrite(HidUsbSession session) async {
    final result = await _PromptDialog.show(
      context,
      title: '写入 Feature Report',
      confirmText: '写入',
      hexField: true,
      fields: const [
        _PromptField(key: 'rid', label: 'Report ID (0-255)', initial: '0'),
      ],
    );
    if (result == null) return;
    final bytes = DataFormat.hexToBytes(result['hex'] ?? '');
    if (bytes.isEmpty) {
      _showError(const FormatException('HEX 内容为空'));
      return;
    }
    try {
      await session.writeFeatureReport(
        bytes,
        int.tryParse(result['rid'] ?? '') ?? 0,
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _showDescriptor(HidUsbSession session) async {
    try {
      final descriptor = await session.loadDescriptor();
      if (mounted) {
        await ReportDescriptorDialog.show(context, descriptor: descriptor);
      }
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
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
          Text('循环发送中',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
        ],
      ),
    );
  }
}

/// 简单的参数输入对话框（若干单行字段 + 可选的多行 HEX 字段）。
class _PromptField {
  const _PromptField({
    required this.key,
    required this.label,
    this.initial = '',
    this.required = false,
  });

  final String key;
  final String label;
  final String initial;
  final bool required;
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.confirmText,
    required this.fields,
    required this.hexField,
  });

  final String title;
  final String confirmText;
  final List<_PromptField> fields;
  final bool hexField;

  static Future<Map<String, String>?> show(
    BuildContext context, {
    required String title,
    required String confirmText,
    required List<_PromptField> fields,
    bool hexField = false,
  }) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _PromptDialog(
        title: title,
        confirmText: confirmText,
        fields: fields,
        hexField: hexField,
      ),
    );
  }

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final Map<String, TextEditingController> _controllers = {};
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _controllers[f.key] = TextEditingController(text: f.initial);
    }
    _hexController = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _hexController.dispose();
    super.dispose();
  }

  void _submit() {
    final result = <String, String>{
      for (final f in widget.fields) f.key: _controllers[f.key]!.text.trim(),
    };
    if (widget.hexField) {
      result['hex'] = _hexController.text.trim();
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _controllers[f.key],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: f.label,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            if (widget.hexField)
              TextField(
                controller: _hexController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '数据（HEX，如 01 02 FF）',
                  border: OutlineInputBorder(),
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
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}
