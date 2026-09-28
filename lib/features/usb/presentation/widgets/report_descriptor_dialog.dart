import 'package:flutter/material.dart';
import 'package:hid_tool/hid_tool.dart';

import '../../../../core/util/data_format.dart';

/// HID 报告描述符查看对话框：原始字节 HEX + Input/Output/Feature 解析表。
class ReportDescriptorDialog extends StatelessWidget {
  const ReportDescriptorDialog({super.key, required this.descriptor});

  final HidReportDescriptor descriptor;

  static Future<void> show(
    BuildContext context, {
    required HidReportDescriptor descriptor,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ReportDescriptorDialog(descriptor: descriptor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('HID 报告描述符'),
      content: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('原始字节（${descriptor.rawBytes.length} 字节）',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Container(
              height: 90,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  DataFormat.bytesToHex(descriptor.rawBytes),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Input'),
                        Tab(text: 'Output'),
                        Tab(text: 'Feature'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _ItemTable(items: descriptor.inputs),
                          _ItemTable(items: descriptor.outputs),
                          _ItemTable(items: descriptor.features),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 单组 Report Item 的解析表。
class _ItemTable extends StatelessWidget {
  const _ItemTable({required this.items});

  final List<HidReportItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('无条目'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8),
      child: DataTable(
        columnSpacing: 18,
        headingRowHeight: 34,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 46,
        columns: const [
          DataColumn(label: Text('RID')),
          DataColumn(label: Text('UsagePage')),
          DataColumn(label: Text('Usage')),
          DataColumn(label: Text('逻辑范围')),
          DataColumn(label: Text('位×数量')),
          DataColumn(label: Text('属性')),
        ],
        rows: [
          for (final item in items)
            DataRow(cells: [
              DataCell(Text(item.reportId.toString())),
              DataCell(Text(
                  '0x${item.usagePage.toRadixString(16).toUpperCase()}')),
              DataCell(Text(_usageText(item))),
              DataCell(Text(
                  '${item.logicalMinimum ?? '-'} ~ ${item.logicalMaximum ?? '-'}')),
              DataCell(Text('${item.reportSize}×${item.reportCount}')),
              DataCell(Text(_flagsText(item))),
            ]),
        ],
      ),
    );
  }

  String _usageText(HidReportItem item) {
    if (item.usage != null) {
      return '0x${item.usage!.toRadixString(16).toUpperCase()}';
    }
    if (item.usageMinimum != null && item.usageMaximum != null) {
      return '0x${item.usageMinimum!.toRadixString(16).toUpperCase()}'
          '~0x${item.usageMaximum!.toRadixString(16).toUpperCase()}';
    }
    return '-';
  }

  String _flagsText(HidReportItem item) {
    final flags = <String>[
      item.isArray ? '数组' : '变量',
      item.isAbsolute ? '绝对' : '相对',
      if (item.hasNull) '含空态',
    ];
    return flags.join(' / ');
  }
}
