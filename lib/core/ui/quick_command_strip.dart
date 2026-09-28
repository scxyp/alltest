import 'package:flutter/material.dart';

import 'quick_command.dart';
import 'send_contracts.dart';

/// 快捷指令胶囊：左半部分点击立即发送，右侧菜单支持载入 / 编辑 / 删除。
class QuickChip extends StatelessWidget {
  const QuickChip({
    super.key,
    required this.command,
    required this.enabled,
    required this.onSend,
    required this.onLoad,
    required this.onEdit,
    required this.onDelete,
  });

  final QuickCommand command;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onLoad;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(20)),
            onTap: enabled ? onSend : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    command.asHex ? Icons.hexagon_outlined : Icons.bolt,
                    size: 13,
                    color: enabled ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    command.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: enabled ? null : scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '操作',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.arrow_drop_down, size: 18, color: scheme.outline),
            onSelected: (v) {
              switch (v) {
                case 'send':
                  onSend();
                case 'load':
                  onLoad();
                case 'edit':
                  onEdit();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'send', child: Text('立即发送')),
              PopupMenuItem(value: 'load', child: Text('载入到输入框')),
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 发送历史下拉菜单：点击历史条目将其载入输入框，可整体清空。
class HistoryMenu extends StatelessWidget {
  const HistoryMenu({super.key, required this.store, required this.onPick});

  final QuickCommandStore store;
  final ValueChanged<SendHistoryItem> onPick;

  String _truncate(String text) {
    final oneLine = text.replaceAll(RegExp(r'[\r\n]+'), '\\n');
    if (oneLine.length <= 24) return oneLine;
    return '${oneLine.substring(0, 24)}…';
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '发送历史',
      onSelected: (index) {
        if (index == -1) {
          store.clearHistory();
        } else if (index < store.history.length) {
          onPick(store.history[index]);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem<int>(
          enabled: false,
          value: -2,
          child: Text('发送历史（点击载入）',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const PopupMenuDivider(),
        if (store.history.isEmpty)
          const PopupMenuItem<int>(enabled: false, value: -2, child: Text('暂无记录')),
        for (var i = 0; i < store.history.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(
              store.history[i].asHex
                  ? '[HEX] ${_truncate(store.history[i].content)}'
                  : _truncate(store.history[i].content),
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
            ),
          ),
        if (store.history.isNotEmpty) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<int>(value: -1, child: Text('清空历史')),
        ],
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history,
              size: 17, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            '历史 (${store.history.length})',
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
