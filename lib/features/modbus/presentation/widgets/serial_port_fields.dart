import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../serial/data/serial_port_service.dart';
import '../../../serial/domain/serial_config.dart';

/// RTU 模式下的串口参数选择（端口 / 波特率 / 数据位 / 校验 / 停止位）。
class SerialPortFields extends StatefulWidget {
  const SerialPortFields({
    super.key,
    this.initial,
    required this.onChanged,
    this.compact = true,
  });

  final SerialConfig? initial;
  final ValueChanged<SerialConfig> onChanged;

  /// 紧凑模式：下拉框更窄，适合放在顶部连接栏。
  final bool compact;

  @override
  State<SerialPortFields> createState() => _SerialPortFieldsState();
}

class _SerialPortFieldsState extends State<SerialPortFields> {
  static const List<int> _baudRates = [
    1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200,
    230400, 460800, 921600,
  ];

  late String _portName;
  late int _baudRate;
  late int _dataBits;
  late SerialParity _parity;
  late SerialStopBits _stopBits;
  List<String> _ports = const [];

  @override
  void initState() {
    super.initState();
    final cfg = widget.initial;
    _portName = cfg?.portName ?? '';
    _baudRate = cfg?.baudRate ?? 9600;
    _dataBits = cfg?.dataBits ?? 8;
    _parity = cfg?.parity ?? SerialParity.none;
    _stopBits = cfg?.stopBits ?? SerialStopBits.one;
    _refreshPorts();
  }

  void _refreshPorts() {
    final ports = SerialPortService.availablePorts;
    setState(() {
      _ports = ports;
      if (_portName.isEmpty && ports.isNotEmpty) {
        _portName = ports.first;
      }
    });
    _emit();
  }

  void _emit() {
    if (_portName.isEmpty) return;
    widget.onChanged(SerialConfig(
      portName: _portName,
      baudRate: _baudRate,
      dataBits: _dataBits,
      parity: _parity,
      stopBits: _stopBits,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.compact ? 128.0 : null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: widget.compact ? 132 : 180,
          child: DropdownButtonFormField<String>(
            initialValue: _ports.contains(_portName) ? _portName : null,
            isDense: true,
            decoration: const InputDecoration(
              labelText: '串口',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in _ports)
                DropdownMenuItem(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() {
              _portName = v ?? '';
              _emit();
            }),
          ),
        ),
        SizedBox(
          width: width,
          child: DropdownButtonFormField<int>(
            initialValue: _baudRate,
            isDense: true,
            decoration: const InputDecoration(
              labelText: '波特率',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final b in _baudRates)
                DropdownMenuItem(value: b, child: Text('$b')),
            ],
            onChanged: (v) => setState(() {
              _baudRate = v ?? 9600;
              _emit();
            }),
          ),
        ),
        SizedBox(
          width: 76,
          child: DropdownButtonFormField<int>(
            initialValue: _dataBits,
            isDense: true,
            decoration: const InputDecoration(
              labelText: '数据位',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final d in [5, 6, 7, 8])
                DropdownMenuItem(value: d, child: Text('$d')),
            ],
            onChanged: (v) => setState(() {
              _dataBits = v ?? 8;
              _emit();
            }),
          ),
        ),
        SizedBox(
          width: 72,
          child: DropdownButtonFormField<SerialParity>(
            initialValue: _parity,
            isDense: true,
            decoration: const InputDecoration(
              labelText: '校验',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in SerialParity.values)
                DropdownMenuItem(
                    value: p, child: Text(p.shortLabel)),
            ],
            onChanged: (v) => setState(() {
              _parity = v ?? SerialParity.none;
              _emit();
            }),
          ),
        ),
        SizedBox(
          width: 76,
          child: DropdownButtonFormField<SerialStopBits>(
            initialValue: _stopBits,
            isDense: true,
            decoration: const InputDecoration(
              labelText: '停止位',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final s in SerialStopBits.values)
                DropdownMenuItem(
                    value: s, child: Text(s.shortLabel)),
            ],
            onChanged: (v) => setState(() {
              _stopBits = v ?? SerialStopBits.one;
              _emit();
            }),
          ),
        ),
        IconButton(
          tooltip: '刷新串口列表',
          onPressed: _refreshPorts,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
    );
  }
}

/// 小尺寸数字输入框。
class CompactNumberField extends StatelessWidget {
  const CompactNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.width = 90,
    this.allowHex = false,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final double width;
  final bool allowHex;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextFormField(
        key: ValueKey('$label-$value'),
        initialValue: allowHex
            ? value.toRadixString(16).toUpperCase()
            : '$value',
        keyboardType: TextInputType.text,
        inputFormatters: [
          allowHex
              ? FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-FxX]'))
              : FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (text) {
          final parsed = allowHex
              ? int.tryParse(text.startsWith('0x')
                      ? text.substring(2)
                      : text,
                  radix: 16) ??
                  0
              : int.tryParse(text) ?? 0;
          onChanged(parsed);
        },
      ),
    );
  }
}
