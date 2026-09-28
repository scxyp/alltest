import 'package:flutter/material.dart';

import 'quick_command.dart';

/// 新增 / 编辑快捷指令对话框（各调试模块通用）。
class QuickCommandDialog extends StatefulWidget {
  const QuickCommandDialog({super.key, this.existing, required this.newId});

  /// 传入则为编辑，否则为新增。
  final QuickCommand? existing;
  final String newId;

  static Future<QuickCommand?> show(
    BuildContext context, {
    QuickCommand? existing,
    required String newId,
  }) {
    return showDialog<QuickCommand>(
      context: context,
      builder: (_) => QuickCommandDialog(existing: existing, newId: newId),
    );
  }

  @override
  State<QuickCommandDialog> createState() => _QuickCommandDialogState();
}

class _QuickCommandDialogState extends State<QuickCommandDialog> {
  late final TextEditingController _name;
  late final TextEditingController _content;
  late bool _asHex;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _content = TextEditingController(text: widget.existing?.content ?? '');
    _asHex = widget.existing?.asHex ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final content = _content.text;
    if (name.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称和内容都不能为空')),
      );
      return;
    }
    Navigator.of(context).pop(
      QuickCommand(
        id: widget.existing?.id ?? widget.newId,
        name: name,
        content: content,
        asHex: _asHex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '新增快捷指令' : '编辑快捷指令'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _content,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'Consolas'),
              decoration: InputDecoration(
                labelText: _asHex ? 'HEX 内容（如：AA 01 FF）' : '发送内容',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Switch(
                  value: _asHex,
                  onChanged: (v) => setState(() => _asHex = v),
                ),
                const Text('以 HEX 格式发送'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
