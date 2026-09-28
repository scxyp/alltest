import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../serial/domain/serial_config.dart';
import '../../domain/modbus_master_controller.dart';
import '../../domain/modbus_pdu.dart';
import 'poll_item_editor.dart';
import 'serial_port_fields.dart';

/// Modbus 主机视图：连接配置、轮询表、结果详情与原始报文日志。
class MasterView extends StatefulWidget {
  const MasterView({super.key, required this.controller});

  final ModbusMasterController controller;

  @override
  State<MasterView> createState() => _MasterViewState();
}

class _MasterViewState extends State<MasterView> {
  late ModbusTransportMode _mode;
  late TextEditingController _host;
  late TextEditingController _port;
  late TextEditingController _timeout;
  late TextEditingController _pollInterval;
  SerialConfig? _serialConfig;
  MasterPollItem? _selected;
  bool _busy = false;

  ModbusMasterController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    final cfg = c.config;
    _mode = cfg.mode;
    _host = TextEditingController(text: cfg.host);
    _port = TextEditingController(text: '${cfg.port}');
    _timeout = TextEditingController(text: '${cfg.timeoutMs}');
    _pollInterval = TextEditingController(text: '${cfg.pollIntervalMs}');
    _serialConfig = cfg.serialConfig;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _timeout.dispose();
    _pollInterval.dispose();
    super.dispose();
  }

  void _syncConfig() {
    c.updateConfig(MasterConfig(
      mode: _mode,
      serialConfig: _mode == ModbusTransportMode.rtu ? _serialConfig : null,
      host: _host.text.trim().isEmpty ? '127.0.0.1' : _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 502,
      timeoutMs: int.tryParse(_timeout.text.trim()) ?? 1000,
      pollIntervalMs: int.tryParse(_pollInterval.text.trim()) ?? 1000,
    ));
  }

  Future<void> _toggleConnect() async {
    if (c.isConnected) {
      await c.disconnect();
      return;
    }
    _syncConfig();
    try {
      await c.connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _execute(MasterPollItem item) async {
    try {
      await c.execute(item);
    } catch (_) {
      // 错误已显示在条目与日志中。
    }
  }

  Future<void> _addOrEdit({MasterPollItem? existing}) async {
    final item = await PollItemEditor.show(
      context,
      existing: existing,
      newId: c.newItemId(),
    );
    if (item == null) return;
    if (existing == null) {
      c.addPollItem(item);
    }
    _selected = item;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Column(
          children: [
            _buildConnectionBar(),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 340, child: _buildPollList()),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(
                            height: 250,
                            child: _ResultDetail(item: _selected),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: c,
                              builder: (context, _) => ReceivePanel(
                                entries: c.logs,
                                rxBytes: c.rxFrames,
                                txBytes: c.txFrames,
                                rxLabel: '响应',
                                txLabel: '请求',
                                onClear: c.clearLogs,
                                exportNamePrefix: 'modbus_master',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 顶部连接栏 ---

  Widget _buildConnectionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<ModbusTransportMode>(
            segments: const [
              ButtonSegment(
                  value: ModbusTransportMode.rtu, label: Text('RTU')),
              ButtonSegment(
                  value: ModbusTransportMode.tcp, label: Text('TCP')),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: c.isConnected
                ? null
                : (v) => setState(() => _mode = v.first),
          ),
          if (_mode == ModbusTransportMode.rtu)
            SerialPortFields(
              initial: _serialConfig,
              onChanged: (cfg) {
                _serialConfig = cfg;
                _syncConfig();
              },
            )
          else ...[
            SizedBox(
              width: 150,
              child: TextField(
                controller: _host,
                enabled: !c.isConnected,
                decoration: const InputDecoration(
                  labelText: '从机 IP',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _syncConfig(),
              ),
            ),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _port,
                enabled: !c.isConnected,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '端口',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _syncConfig(),
              ),
            ),
          ],
          SizedBox(
            width: 96,
            child: TextField(
              controller: _timeout,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '超时(ms)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _syncConfig(),
            ),
          ),
          SizedBox(
            width: 104,
            child: TextField(
              controller: _pollInterval,
              enabled: c.isConnected,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '轮询(ms)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) {
                _syncConfig();
                if (c.polling) {
                  c.stopPolling();
                  c.startPolling();
                }
              },
            ),
          ),
          c.isConnected
              ? OutlinedButton.icon(
                  onPressed: _toggleConnect,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('断开'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700),
                )
              : FilledButton.icon(
                  onPressed: _busy ? null : () async {
                    setState(() => _busy = true);
                    await _toggleConnect();
                    if (mounted) setState(() => _busy = false);
                  },
                  icon: const Icon(Icons.power, size: 18),
                  label: const Text('连接'),
                ),
          if (c.isConnected) ...[
            OutlinedButton.icon(
              onPressed: c.polling ? c.stopPolling : c.startPolling,
              icon: Icon(c.polling ? Icons.stop : Icons.play_arrow,
                  size: 18),
              label: Text(c.polling ? '停止轮询' : '开始轮询'),
            ),
          ],
          _StatusDot(connected: c.isConnected),
        ],
      ),
    );
  }

  // --- 左侧轮询表 ---

  Widget _buildPollList() {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                const Text('请求列表',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('${c.pollItems.length} 条',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline)),
                const Spacer(),
                IconButton(
                  tooltip: '添加请求',
                  onPressed: () => _addOrEdit(),
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: c.pollItems.isEmpty
                ? Center(
                    child: Text('点击 + 添加 Modbus 请求',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline)),
                  )
                : ListView.builder(
                    itemCount: c.pollItems.length,
                    itemBuilder: (context, index) {
                      final item = c.pollItems[index];
                      final selected = identical(item, _selected);
                      return _PollItemTile(
                        item: item,
                        selected: selected,
                        connected: c.isConnected,
                        onTap: () => setState(() => _selected = item),
                        onToggleEnabled: () => setState(
                            () => item.enabled = !item.enabled),
                        onExecute: () => _execute(item),
                        onEdit: () => _addOrEdit(existing: item),
                        onDelete: () => setState(
                            () => c.removePollItem(item.id)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PollItemTile extends StatelessWidget {
  const _PollItemTile({
    required this.item,
    required this.selected,
    required this.connected,
    required this.onTap,
    required this.onToggleEnabled,
    required this.onExecute,
    required this.onEdit,
    required this.onDelete,
  });

  final MasterPollItem item;
  final bool selected;
  final bool connected;
  final VoidCallback onTap;
  final VoidCallback onToggleEnabled;
  final VoidCallback onExecute;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = item.lastError != null;
    return Material(
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom:
                  BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Checkbox(
                      value: item.enabled,
                      onChanged: (_) => onToggleEnabled(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: item.enabled ? null : scheme.outline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '执行一次',
                    visualDensity: VisualDensity.compact,
                    onPressed: connected ? onExecute : null,
                    icon: Icon(Icons.play_arrow,
                        size: 18, color: scheme.primary),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '操作',
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '0x${item.function.code.toRadixString(16).padLeft(2, '0').toUpperCase()} ${item.function.label}'
                      '  地址 ${item.startAddress}'
                      '${item.function.isQuantityBased ? ' × ${item.quantity}' : ''}'
                      '  从机 ${item.unitId}',
                      style:
                          const TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.resultPreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'Consolas',
                        color: hasError ? Colors.red.shade700 : scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 请求结果结构化详情。
class _ResultDetail extends StatelessWidget {
  const _ResultDetail({required this.item});

  final MasterPollItem? item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: item == null
            ? Center(
                child: Text('选择左侧请求查看结果',
                    style: TextStyle(color: scheme.outline)),
              )
            : _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final i = item!;
    final r = i.lastResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(i.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Text(
              '0x${i.function.code.toRadixString(16).padLeft(2, '0').toUpperCase()} '
              '${i.function.label} @${i.startAddress}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Spacer(),
            if (i.lastTime != null)
              Text(_time(i.lastTime!),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
          ],
        ),
        const Divider(height: 14),
        Expanded(child: _buildData(context, r)),
      ],
    );
  }

  Widget _buildData(BuildContext context, ModbusResponse? r) {
    if (item!.lastError != null && r == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(item!.lastError!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
      );
    }
    if (r == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text('尚未执行',
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    if (r.isException) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          '从机返回异常：${ModbusExceptionCode.labelOf(r.exceptionCode ?? 0)}',
          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
        ),
      );
    }

    if (r.bits.isNotEmpty) {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 12,
          childAspectRatio: 2.6,
        ),
        itemCount: r.bits.length,
        itemBuilder: (context, index) {
          final on = r.bits[index] != 0;
          return Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: on
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: on ? Colors.green.shade300 : Colors.grey.shade300,
              ),
            ),
            child: Center(
              child: Text(
                '${addrOf(index)}',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 10.5,
                  color: on ? Colors.green.shade800 : Colors.grey.shade600,
                ),
              ),
            ),
          );
        },
      );
    }

    if (r.registers.isNotEmpty) {
      return ListView.separated(
        itemCount: r.registers.length,
        separatorBuilder: (context, index) =>
            Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final address = item!.startAddress + index;
          final v = r.registers[index];
          final signed = v >= 0x8000 ? v - 0x10000 : v;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text('地址 $address',
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 12)),
                ),
                SizedBox(
                  width: 90,
                  child: Text('0x${v.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                      style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 12.5,
                          color: Color(0xFF2E5EAA))),
                ),
                Text('$v',
                    style: const TextStyle(
                        fontFamily: 'Consolas', fontSize: 12.5)),
                const SizedBox(width: 14),
                Text('有符号: $signed',
                    style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11.5,
                        color: Colors.grey.shade500)),
              ],
            ),
          );
        },
      );
    }

    // 写操作回显。
    return Align(
      alignment: Alignment.topLeft,
      child: Text(
        r.echoAddress != null
            ? '写入成功：地址 ${r.echoAddress}'
                '${r.echoValue != null ? '，值 0x${(r.echoValue!).toRadixString(16).padLeft(4, '0').toUpperCase()}' : ''}'
                '${r.echoQuantity != null ? '，数量 ${r.echoQuantity}' : ''}'
            : '写入成功',
        style: const TextStyle(fontSize: 13, color: Colors.green),
      ),
    );
  }

  int addrOf(int index) => item!.startAddress + index;

  String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: connected ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(connected ? '已连接' : '未连接',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}
