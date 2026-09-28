import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/serial_config.dart';

/// 新建串口连接 / 修改串口参数对话框。
class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({
    super.key,
    required this.ports,
    required this.busyPorts,
    required this.initial,
    required this.actionText,
  });

  final List<String> ports;
  final Set<String> busyPorts;
  final SerialConfig initial;
  final String actionText;

  static const List<int> baudPresets = [
    1200,
    2400,
    4800,
    9600,
    19200,
    38400,
    57600,
    115200,
    230400,
    460800,
    921600,
  ];

  static Future<SerialConfig?> show(
    BuildContext context, {
    required List<String> ports,
    required Set<String> busyPorts,
    required SerialConfig initial,
    required String actionText,
  }) {
    return showDialog<SerialConfig>(
      context: context,
      builder: (_) => ConnectionDialog(
        ports: ports,
        busyPorts: busyPorts,
        initial: initial,
        actionText: actionText,
      ),
    );
  }

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  late String _portName;
  late TextEditingController _baudController;
  late int _dataBits;
  late SerialParity _parity;
  late SerialStopBits _stopBits;
  late SerialFlowControl _flowControl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final cfg = widget.initial;
    _portName = cfg.portName;
    _baudController = TextEditingController(text: cfg.baudRate.toString());
    _dataBits = cfg.dataBits;
    _parity = cfg.parity;
    _stopBits = cfg.stopBits;
    _flowControl = cfg.flowControl;
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
      SerialConfig(
        portName: _portName,
        baudRate: baud,
        dataBits: _dataBits,
        parity: _parity,
        stopBits: _stopBits,
        flowControl: _flowControl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('串口参数'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label('串口'),
              if (_portChoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '未发现可用串口，请检查设备连接后点击“刷新”',
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
              _label('波特率'),
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
                          ConnectionDialog.baudPresets.contains(int.tryParse(_baudController.text))
                              ? int.tryParse(_baudController.text)
                              : null,
                      items: [
                        for (final b in ConnectionDialog.baudPresets)
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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('数据位'),
                        DropdownButtonFormField<int>(
                          initialValue: _dataBits,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final b in const [5, 6, 7, 8])
                              DropdownMenuItem(value: b, child: Text('$b')),
                          ],
                          onChanged: (v) =>
                              setState(() => _dataBits = v ?? 8),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('停止位'),
                        DropdownButtonFormField<SerialStopBits>(
                          initialValue: _stopBits,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final s in SerialStopBits.values)
                              DropdownMenuItem(
                                value: s,
                                child: Text(s.label),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _stopBits = v ?? SerialStopBits.one),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('校验位'),
                        DropdownButtonFormField<SerialParity>(
                          initialValue: _parity,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final p in SerialParity.values)
                              DropdownMenuItem(
                                value: p,
                                child: Text(p.label),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _parity = v ?? SerialParity.none),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('流控'),
                        DropdownButtonFormField<SerialFlowControl>(
                          initialValue: _flowControl,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final f in SerialFlowControl.values)
                              DropdownMenuItem(
                                value: f,
                                child: Text(f.label),
                              ),
                          ],
                          onChanged: (v) => setState(
                              () => _flowControl = v ?? SerialFlowControl.none),
                        ),
                      ],
                    ),
                  ),
                ],
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
