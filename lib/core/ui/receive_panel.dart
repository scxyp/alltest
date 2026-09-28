import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/data_format.dart';
import 'debug_log_entry.dart';

/// 接收 / 数据监视器面板。
class ReceivePanel extends StatefulWidget {
  const ReceivePanel({
    super.key,
    required this.entries,
    required this.rxBytes,
    required this.txBytes,
    required this.onClear,
    this.exportNamePrefix = 'log',
    this.rxLabel = 'RX',
    this.txLabel = 'TX',
  });

  /// 外部会话的日志引用（同一 List 实例，随会话追加而更新）。
  final List<DebugLogEntry> entries;

  /// 已接收字节数。
  final int rxBytes;

  /// 已发送字节数。
  final int txBytes;

  /// 清空日志并归零统计（面板内保留二次确认对话框）。
  final VoidCallback onClear;

  /// 导出文件名前缀（如连接名称，仅保留字母数字）。
  final String exportNamePrefix;

  /// 收 / 发方向的显示标签（如 Modbus 主机用"响应 / 请求"）。
  final String rxLabel;
  final String txLabel;

  @override
  State<ReceivePanel> createState() => _ReceivePanelState();
}

class _ReceivePanelState extends State<ReceivePanel> {
  final ScrollController _scrollController = ScrollController();

  // --- 接收区显示选项 ---
  bool _showTimestamp = true;
  bool _receiveAsHex = false;
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  String get _renderedLog => widget.entries
      .map((e) => e.toTextLine(
            asHex: _receiveAsHex,
            withTimestamp: _showTimestamp,
          ))
      .join('\r\n');

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _renderedLog));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日志已复制到剪贴板'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _clearLog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定清空当前会话的全部收发记录吗？（不影响已导出的文件）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onClear();
  }

  Future<void> _export(bool asCsv) async {
    if (widget.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无日志可导出')),
      );
      return;
    }
    final ext = asCsv ? 'csv' : 'txt';
    final suggestedName =
        '${widget.exportNamePrefix.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}'
        '_${DataFormat.fileTimestamp(DateTime.now())}.$ext';
    try {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(label: '日志文件', extensions: [ext]),
        ],
      );
      if (location == null) return;
      final content = asCsv
          ? buildCsvLog(widget.entries)
          : buildTextLog(widget.entries, asHex: _receiveAsHex);
      await File(location.path).writeAsString(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出：${location.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // --- 工具栏 ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          color: scheme.surfaceContainerLow,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('文本')),
                  ButtonSegment(value: true, label: Text('HEX')),
                ],
                selected: {_receiveAsHex},
                onSelectionChanged: (v) =>
                    setState(() => _receiveAsHex = v.first),
              ),
              _ToolbarToggle(
                icon: Icons.schedule,
                label: '时间戳',
                active: _showTimestamp,
                onTap: () => setState(() => _showTimestamp = !_showTimestamp),
              ),
              _ToolbarToggle(
                icon: _autoScroll
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                label: _autoScroll ? '暂停滚动' : '自动滚动',
                active: _autoScroll,
                onTap: () => setState(() => _autoScroll = !_autoScroll),
              ),
              const SizedBox(width: 4),
              _StatText(label: widget.rxLabel, bytes: widget.rxBytes, color: Colors.green.shade800),
              _StatText(label: widget.txLabel, bytes: widget.txBytes, color: Colors.blue.shade800),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '复制日志',
                visualDensity: VisualDensity.compact,
                onPressed: _copyLog,
                icon: const Icon(Icons.copy, size: 19),
              ),
              PopupMenuButton<String>(
                tooltip: '导出日志',
                icon: const Icon(Icons.download, size: 19),
                onSelected: (v) => _export(v == 'csv'),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'txt', child: Text('导出为 TXT')),
                  PopupMenuItem(value: 'csv', child: Text('导出为 CSV')),
                ],
              ),
              IconButton(
                tooltip: '清空日志',
                visualDensity: VisualDensity.compact,
                onPressed: _clearLog,
                icon: const Icon(Icons.delete_outline, size: 19),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // --- 日志列表 ---
        Expanded(
          child: ColoredBox(
            color: scheme.surfaceContainerLowest,
            child: _buildLogArea(scheme),
          ),
        ),
      ],
    );
  }

  Widget _buildLogArea(ColorScheme scheme) {
    if (widget.entries.isEmpty) {
      return Center(
        child: Text(
          '等待数据…',
          style: TextStyle(color: scheme.outline),
        ),
      );
    }
    _scrollToBottom();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 8),
      itemCount: widget.entries.length,
      itemExtent: null,
      itemBuilder: (context, index) => _LogRow(
        entry: widget.entries[index],
        showTimestamp: _showTimestamp,
        receiveAsHex: _receiveAsHex,
      ),
    );
  }
}

class _ToolbarToggle extends StatelessWidget {
  const _ToolbarToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 17,
                color: active ? scheme.primary : scheme.outline),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: active ? scheme.primary : scheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatText extends StatelessWidget {
  const _StatText({
    required this.label,
    required this.bytes,
    required this.color,
  });

  final String label;
  final int bytes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $bytes B',
      style: TextStyle(
        fontSize: 12,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.entry,
    required this.showTimestamp,
    required this.receiveAsHex,
  });

  final DebugLogEntry entry;
  final bool showTimestamp;
  final bool receiveAsHex;

  Color _directionColor(BuildContext context) {
    return switch (entry.direction) {
      DebugDirection.receive => Colors.green.shade800,
      DebugDirection.transmit => Colors.blue.shade800,
      DebugDirection.system => Colors.deepOrange.shade700,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dirColor = _directionColor(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontFamilyFallback: ['Courier New', 'Microsoft YaHei'],
            fontSize: 13,
            height: 1.35,
          ),
          children: [
            if (showTimestamp)
              TextSpan(
                text: '[${DataFormat.clockTimestamp(entry.timestamp)}] ',
                style: TextStyle(color: scheme.outline),
              ),
            TextSpan(
              text: '[${entry.tag}] ',
              style: TextStyle(
                color: dirColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: entry.body(asHex: receiveAsHex),
              style: TextStyle(
                color: entry.isSystem ? dirColor : null,
                fontStyle:
                    entry.isSystem ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 由日志记录生成 TXT 文本（每条一行，CRLF 分隔，含完整时间戳）。
String buildTextLog(List<DebugLogEntry> entries, {required bool asHex}) =>
    entries
        .map((e) => e.toTextLine(asHex: asHex, withTimestamp: true))
        .join('\r\n');

/// 由日志记录生成 CSV 文本（列：时间 / 方向 / 字节数 / HEX / 文本）。
String buildCsvLog(List<DebugLogEntry> entries) {
  String field(String value) => '"${value.replaceAll('"', '""')}"';
  final sb = StringBuffer()
    ..writeln('时间,方向,字节数,HEX,文本');
  for (final entry in entries) {
    if (entry.isSystem) {
      sb
        ..write(field(DataFormat.fullTimestamp(entry.timestamp)))
        ..write(',')
        ..write(field('系统'))
        ..write(',,')
        ..write(field(''))
        ..write(',')
        ..writeln(field(entry.message ?? ''));
      continue;
    }
    final bytes = entry.data!;
    sb
      ..write(field(DataFormat.fullTimestamp(entry.timestamp)))
      ..write(',')
      ..write(field(entry.tag))
      ..write(',')
      ..write(bytes.length)
      ..write(',')
      ..write(field(DataFormat.bytesToHex(bytes)))
      ..write(',')
      ..writeln(field(DataFormat.bytesToText(bytes)));
  }
  return sb.toString();
}
