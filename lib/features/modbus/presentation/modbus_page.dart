import 'package:flutter/material.dart';

import '../domain/modbus_workspace.dart';
import 'widgets/master_view.dart';
import 'widgets/slave_view.dart';

/// Modbus 调试主页：在"主机"与"从机"模拟器之间切换。
class ModbusPage extends StatefulWidget {
  const ModbusPage({super.key, required this.workspace});

  final ModbusWorkspace workspace;

  @override
  State<ModbusPage> createState() => _ModbusPageState();
}

class _ModbusPageState extends State<ModbusPage> {
  bool _masterMode = true;

  @override
  Widget build(BuildContext context) {
    final ws = widget.workspace;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modbus 模拟器'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<bool>(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('主机 Master'),
                  icon: Icon(Icons.smart_toy_outlined, size: 18),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('从机 Slave'),
                  icon: Icon(Icons.dns_outlined, size: 18),
                ),
              ],
              selected: {_masterMode},
              showSelectedIcon: false,
              onSelectionChanged: (v) =>
                  setState(() => _masterMode = v.first),
            ),
          ),
        ],
      ),
      body: _masterMode
          ? MasterView(controller: ws.master)
          : SlaveView(controller: ws.slave),
    );
  }
}
