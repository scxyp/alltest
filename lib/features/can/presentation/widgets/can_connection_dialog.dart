import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/can_config.dart';

/// 新建 CAN 连接 / 修改 CAN 参数对话框。
///
/// 配置两部分参数：
/// - 串口侧：端口名 + 波特率（与适配器的虚拟串口通信）
/// - CAN 侧：总线波特率（S0~S9 预设）
class CanConnectionDialog extends StatefulWidget {
  const CanConnectionDialog({
    super.key,
    required this.ports,
    required this.busyPorts,
    required this.initial,
    required this.actionText,
  });

  final List<String> ports;
  final Set<String> busyPorts;
  final CanConfig initial;
  final String actionText;

  static const List<int> baudPresets = [
    9600,
    19200,
    38400,
    57600,
    115200,
    230400,
    460800,
    921600,
  ];

  static Future<CanConfig?> show(
    BuildContext context, {
    required List<String> ports,
    required Set<String> busyPorts,
    required CanConfig initial,
    required String actionText,
  }) {
    return showDialog<CanConfig>(
      context: context,
      builder: (_) => CanConnectionDialog(
        ports: ports,
        busyPorts: busyPorts,
        initial: initial,
        actionText: actionText,
      ),
    );
  }

  @override
  State<CanConnectionDialog> createState() => _CanConnectionDialogState();
}

class _CanConnectionDialogState extends State<CanConnectionDialog> {
  late String _portName;
  late TextEditingController _baudController;
  late CanBitrate _canBitrate;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final cfg = widget.initial;
    _portName = cfg.portName;
    _baudController = TextEditingController(text: cfg.baudRate.toString());
    _canBitrate = cfg.canBitrate;
  }

  @override
  void dispose() {
    _baudController.dispose();
    super.dispose();
  }

  /// 可选端口：全部可用端口 + 初始端口（可能已不在列表），占用端口标注。
  List<String> get _portChoices {
    final choices = <String>{...widget.ports, if (_portName.isNotEmpty) _portName};
    return choices.toList();
  }

  void _submit() {
    final baud = int.tryParse(_baudController.text.trim());
    if (_portName.isEmpty) {
      setState(() => _errorText = '请选择串口');
      return;
    }
    if (baud == null || baud <= 0) {
      setState(() => _errorText = '请输入有效的波特率');
      return;
    }
    if (widget.busyPorts.contains(_portName) &&
        _portName != widget.initial.portName) {
      setState(() => _errorText = '$_portName 已被其他会话占用');
      return;
    }
    Navigator.of(context).pop(
      CanConfig(
        portName: _portName,
        baudRate: baud,
        canBitrate: _canBitrate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CAN 适配器参数'),
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
                          CanConnectionDialog.baudPresets.contains(int.tryParse(_baudController.text))
                              ? int.tryParse(_baudController.text)
                              : null,
                      items: [
                        for (final b in CanConnectionDialog.baudPresets)
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
