import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../serial/domain/serial_config.dart';
import '../../domain/modbus_pdu.dart';
import '../../domain/modbus_slave_controller.dart';
import 'serial_port_fields.dart';

/// Modbus 从机视图：连接配置、四区寄存器在线编辑、请求 / 响应日志。
class SlaveView extends StatefulWidget {
  const SlaveView({super.key, required this.controller});

  final ModbusSlaveController controller;

  @override
  State<SlaveView> createState() => _SlaveViewState();
}

class _SlaveViewState extends State<SlaveView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late ModbusTransportMode _mode;
  late TextEditingController _rtuAddress;
  late TextEditingController _tcpPort;
  late TextEditingController _tcpBind;
  SerialConfig? _serialConfig;
  bool _hexFormat = true;

  static const List<String> _tabTitles = [
    '线圈 (0x)',
    '离散输入 (1x)',
    '输入寄存器 (3x)',
    '保持寄存器 (4x)',
  ];

  ModbusSlaveController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    final cfg = c.config;
    _mode = cfg.mode;
    _rtuAddress = TextEditingController(text: '${cfg.rtuAddress}');
    _tcpPort = TextEditingController(text: '${cfg.tcpPort}');
    _tcpBind = TextEditingController(text: cfg.bindAddress);
    _serialConfig = cfg.serialConfig;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _rtuAddress.dispose();
    _tcpPort.dispose();
    _tcpBind.dispose();
    super.dispose();
  }

  void _syncConfig() {
    c.updateConfig(SlaveConfig(
      mode: _mode,
      serialConfig: _mode == ModbusTransportMode.rtu ? _serialConfig : null,
      rtuAddress: int.tryParse(_rtuAddress.text.trim()) ?? 1,
      bindAddress: _tcpBind.text.trim(),
      tcpPort: int.tryParse(_tcpPort.text.trim()) ?? 502,
    ));
  }

  Future<void> _toggleRun() async {
    if (c.isRunning) {
      await c.stop();
      return;
    }
    _syncConfig();
    try {
      await c.start();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is StateError ? e.message : '$e')),
        );
      }
    }
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
                    Expanded(child: _buildRegisterPanel()),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 400,
                      child: ReceivePanel(
                        entries: c.logs,
                        rxBytes: c.requestCount,
                        txBytes: c.responseCount,
                        rxLabel: '请求',
                        txLabel: '响应',
                        onClear: c.clearLogs,
                        exportNamePrefix: 'modbus_slave',
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
            onSelectionChanged: c.isRunning
                ? null
                : (v) => setState(() => _mode = v.first),
          ),
          if (_mode == ModbusTransportMode.rtu) ...[
            SerialPortFields(
              initial: _serialConfig,
              onChanged: (cfg) {
                _serialConfig = cfg;
                _syncConfig();
              },
            ),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _rtuAddress,
                enabled: !c.isRunning,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '从机地址',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _syncConfig(),
              ),
            ),
          ] else ...[
            SizedBox(
              width: 150,
              child: TextField(
                controller: _tcpBind,
                enabled: !c.isRunning,
                decoration: const InputDecoration(
                  labelText: '绑定网卡 IP（空=全部）',
                  hintText: '0.0.0.0',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _syncConfig(),
              ),
            ),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _tcpPort,
                enabled: !c.isRunning,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '监听端口',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _syncConfig(),
              ),
            ),
          ],
          c.isRunning
              ? OutlinedButton.icon(
                  onPressed: _toggleRun,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('停止'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700),
                )
              : FilledButton.icon(
                  onPressed: _toggleRun,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('启动从机'),
                ),
          _StatusDot(running: c.isRunning),
          if (c.isRunning)
            Text('已处理请求 ${c.requestCount}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildRegisterPanel() {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 420,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  onTap: (_) => setState(() {}),
                  tabs: [for (final t in _tabTitles) Tab(text: t)],
                ),
              ),
              const Spacer(),
              if (_tabController.index >= 2)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('HEX')),
                    ButtonSegment(value: false, label: Text('DEC')),
                  ],
                  selected: {_hexFormat},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      setState(() => _hexFormat = v.first),
                ),
              const SizedBox(width: 12),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _BitTable(
                  values: c.bank.coils,
                  title: '线圈',
                  onChanged: c.setCoil,
                ),
                _BitTable(
                  values: c.bank.discreteInputs,
                  title: '离散输入',
                  onChanged: c.setDiscreteInput,
                ),
                _RegisterTable(
                  values: c.bank.inputRegisters,
                  title: '输入寄存器',
                  hex: _hexFormat,
                  onChanged: c.setInputRegister,
                ),
                _RegisterTable(
                  values: c.bank.holdingRegisters,
                  title: '保持寄存器',
                  hex: _hexFormat,
                  onChanged: c.setHoldingRegister,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 位数据区表格（线圈 / 离散输入）。
class _BitTable extends StatelessWidget {
  const _BitTable({
    required this.values,
    required this.title,
    required this.onChanged,
  });

  final List<int> values;
  final String title;
  final void Function(int address, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemExtent: 38,
      itemCount: values.length,
      itemBuilder: (context, index) {
        final on = values[index] != 0;
        return InkWell(
          onTap: () => onChanged(index, !on),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.5)),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text('$title[$index]',
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 12.5)),
                ),
                Switch(
                  value: on,
                  onChanged: (v) => onChanged(index, v),
                ),
                const SizedBox(width: 8),
                Text(on ? 'ON (1)' : 'OFF (0)',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12.5,
                      color: on
                          ? Colors.green.shade700
                          : Colors.grey.shade500,
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 寄存器数据区表格（保持 / 输入寄存器）。
class _RegisterTable extends StatelessWidget {
  const _RegisterTable({
    required this.values,
    required this.title,
    required this.hex,
    required this.onChanged,
  });

  final List<int> values;
  final String title;
  final bool hex;
  final void Function(int address, int value) onChanged;

  Future<void> _edit(BuildContext context, int address, int value) async {
    final controller = TextEditingController(
      text: hex
          ? value.toRadixString(16).padLeft(4, '0').toUpperCase()
          : '$value',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 $title[$address]'),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: hex ? '十六进制值（0-FFFF）' : '十进制值（0-65535）',
              border: const OutlineInputBorder(),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                hex ? RegExp(r'[0-9a-fA-F]') : RegExp(r'[0-9]'),
              ),
            ],
            onSubmitted: (v) => Navigator.pop(ctx, _parse(v, hex)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, _parse(controller.text, hex)),
            child: const Text('写入'),
          ),
        ],
      ),
    );
    if (result != null) onChanged(address, result);
  }

  static int? _parse(String text, bool hex) =>
      hex ? int.tryParse(text.trim(), radix: 16) : int.tryParse(text.trim());

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemExtent: 36,
      itemCount: values.length,
      itemBuilder: (context, index) {
        final v = values[index];
        return InkWell(
          onTap: () => _edit(context, index, v),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.5)),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  child: Text('$title[$index]',
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 12.5)),
                ),
                Text(
                  hex
                      ? '0x${v.toRadixString(16).padLeft(4, '0').toUpperCase()}'
                      : '$v',
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 13,
                    color: Color(0xFF2E5EAA),
                  ),
                ),
                const SizedBox(width: 16),
                Text('HEX 切换查看 / 点击行编辑',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: running ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(running ? '从机运行中' : '未启动',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}
