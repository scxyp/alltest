import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../can/domain/can_config.dart';
import '../../domain/canopen_config.dart';

/// 新建 CANopen 连接 / 修改 CANopen 参数对话框。
///
/// 复用 CAN 模块的串口 + CAN 波特率选择，额外增加目标 Node ID 输入。
class CanOpenConnectionDialog extends StatefulWidget {
  const CanOpenConnectionDialog({
    super.key,
    required this.ports,
    required this.busyPorts,
    required this.initial,
    required this.actionText,
  });

  final List<String> ports;
  final Set<String> busyPorts;
  final CanOpenConfig initial;
  final String actionText;

  static const List<int> baudPresets = [
    9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600,
  ];

  static Future<CanOpenConfig?> show(
    BuildContext context, {
    required List<String> ports,
    required Set<String> busyPorts,
    required CanOpenConfig initial,
    required String actionText,
  }) {
    return showDialog<CanOpenConfig>(
      context: context,
      builder: (_) => CanOpenConnectionDialog(
        ports: ports,
        busyPorts: busyPorts,
        initial: initial,
        actionText: actionText,
      ),
    );
  }

  @override
  State<CanOpenConnectionDialog> createState() =>
      _CanOpenConnectionDialogState();
}

class _CanOpenConnectionDialogState extends State<CanOpenConnectionDialog> {
  late String _portName;
  late TextEditingController _baudController;
  late CanBitrate _canBitrate;
  late TextEditingController _nodeIdController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final cfg = widget.initial;
    _portName = cfg.portName;
    _baudController = TextEditingController(text: cfg.baudRate.toString());
    _canBitrate = cfg.canBitrate;
    _nodeIdController = TextEditingController(text: cfg.nodeId.toString());
  }

  @override
  void dispose() {
    _baudController.dispose();
    _nodeIdController.dispose();
    super.dispose();
  }

  List<String> get _portChoices {
    final choices = <String>{...widget.ports, if (_portName.isNotEmpty) _portName};
    return choices.toList();
  }

  void _submit() {
    final baud = int.tryParse(_baudController.text.trim());
    final nodeId = int.tryParse(_nodeIdController.text.trim());
    if (_portName.isEmpty) {
      setState(() => _errorText = '请选择串口');
      return;
    }
    if (baud == null || baud <= 0) {
      setState(() => _errorText = '请输入有效的波特率');
      return;
    }
    if (nodeId == null || nodeId < 1 || nodeId > 127) {
      setState(() => _errorText = 'Node ID 范围：1~127');
      return;
    }
    if (widget.busyPorts.contains(_portName) &&
        _portName != widget.initial.portName) {
      setState(() => _errorText = '$_portName 已被其他会话占用');
      return;
    }
    Navigator.of(context).pop(
      CanOpenConfig(
        portName: _portName,
        baudRate: baud,
        canBitrate: _canBitrate,
        nodeId: nodeId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CANopen 适配器参数'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label('串口（CAN 适配器虚拟串口）'),
              if (_portChoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '未发现可用串口，请检查适配器连接后点击"刷新"',
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue:
                    _portChoices.contains(_portName) ? _portName : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                hint: const Text('选择串口'),
                items: [
                  for (final p in _portChoices)
                    DropdownMenuItem(
                      value: p,
                      child: Text(
                        widget.busyPorts.contains(p) &&
                                p != widget.initial.portName
                            ? '$p（已占用）'
                            : p,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _portName = v ?? '';
                  _errorText = null;
                }),
              ),
              const SizedBox(height: 14),
              _label('串口波特率'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextFormField(
                      controller: _baudController,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        labelText: '常用',
                      ),
                      initialValue:
                          CanOpenConnectionDialog.baudPresets.contains(
                                  int.tryParse(_baudController.text))
                              ? int.tryParse(_baudController.text)
                              : null,
                      items: [
                        for (final b in CanOpenConnectionDialog.baudPresets)
                          DropdownMenuItem(value: b, child: Text('$b')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _baudController.text = '$v');
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _label('CAN 总线波特率'),
              DropdownButtonFormField<CanBitrate>(
                initialValue: _canBitrate,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final b in CanBitrate.values)
                    DropdownMenuItem(value: b, child: Text(b.label)),
                ],
                onChanged: (v) =>
                    setState(() => _canBitrate = v ?? CanBitrate.speed500K),
              ),
              const SizedBox(height: 14),
              _label('CANopen Node ID (1~127)'),
              TextFormField(
                controller: _nodeIdController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(_errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.actionText),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );
}
