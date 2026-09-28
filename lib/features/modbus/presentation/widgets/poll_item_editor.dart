import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/modbus_master_controller.dart';
import '../../domain/modbus_pdu.dart';

/// 主机轮询请求的新增 / 编辑对话框。
class PollItemEditor extends StatefulWidget {
  const PollItemEditor({super.key, this.existing, required this.newId});

  final MasterPollItem? existing;
  final String newId;

  static Future<MasterPollItem?> show(
    BuildContext context, {
    MasterPollItem? existing,
    required String newId,
  }) {
    return showDialog<MasterPollItem>(
      context: context,
      builder: (_) => PollItemEditor(existing: existing, newId: newId),
    );
  }

  @override
  State<PollItemEditor> createState() => _PollItemEditorState();
}

class _PollItemEditorState extends State<PollItemEditor> {
  late final TextEditingController _name;
  late int _unitId;
  late ModbusFunction _function;
  late int _startAddress;
  late int _quantity;
  late bool _singleBitValue;
  late final TextEditingController _singleRegister;
  late final TextEditingController _multiBits;
  late final TextEditingController _multiRegisters;
  late bool _hexInput;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '请求');
    _unitId = e?.unitId ?? 1;
    _function = e?.function ?? ModbusFunction.readHoldingRegisters;
    _startAddress = e?.startAddress ?? 0;
    _quantity = e?.quantity ?? 1;
    _singleBitValue = e != null && e.values.isNotEmpty && e.values.first != 0;
    _singleRegister = TextEditingController(
        text: e != null && e.values.isNotEmpty
            ? e.values.first.toRadixString(16).padLeft(4, '0')
            : '0000');
    _multiBits = TextEditingController(
        text: e?.values.map((v) => v == 0 ? '0' : '1').join(',') ?? '1,0,1');
    _multiRegisters = TextEditingController(
        text: e?.values
                .map((v) => v.toRadixString(16).padLeft(4, '0'))
                .join(',') ??
            '0001,0002');
    _hexInput = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _singleRegister.dispose();
    _multiBits.dispose();
    _multiRegisters.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('请填写名称');
      return;
    }
    if (_unitId < 0 || _unitId > 247) {
      _snack('从机地址应在 0-247（0 为 RTU 广播）');
      return;
    }
    if (_startAddress < 0 || _startAddress > 65535) {
      _snack('起始地址应在 0-65535');
      return;
    }

    List<int> values = const [];
    var quantity = _quantity;
    try {
      switch (_function) {
        case ModbusFunction.writeSingleCoil:
          values = [_singleBitValue ? 1 : 0];
          quantity = 1;
        case ModbusFunction.writeSingleRegister:
          values = [_parseRegister(_singleRegister.text)];
          quantity = 1;
        case ModbusFunction.writeMultipleCoils:
          values = _parseIntList(_multiBits.text)
              .map((v) => v == 0 ? 0 : 1)
              .toList();
          quantity = values.length;
        case ModbusFunction.writeMultipleRegisters:
          values = _multiRegisters.text
              .split(RegExp(r'[\s,;]+'))
              .where((s) => s.isNotEmpty)
              .map((s) {
            final t = s.startsWith('0x') || s.startsWith('0X')
                ? s.substring(2)
                : s;
            final v = _hexInput
                ? int.tryParse(t, radix: 16)
                : int.tryParse(t);
            if (v == null) throw FormatException('无法解析数值：$s');
            return v & 0xFFFF;
          }).toList();
          quantity = values.length;
        default:
          break;
      }
    } on FormatException catch (e) {
      _snack(e.message);
      return;
    }

    if (_function.isQuantityBased) {
      final maxQty = _function.isBitType ? 2000 : 125;
      if (quantity < 1 || quantity > maxQty) {
        _snack('数量应在 1-$maxQty 之间');
        return;
      }
    }
    if (_function == ModbusFunction.writeMultipleCoils &&
        (values.isEmpty || values.length > 1968)) {
      _snack('线圈数量应在 1-1968 之间');
      return;
    }
    if (_function == ModbusFunction.writeMultipleRegisters &&
        (values.isEmpty || values.length > 123)) {
      _snack('寄存器数量应在 1-123 之间');
      return;
    }

    Navigator.of(context).pop(MasterPollItem(
      id: widget.existing?.id ?? widget.newId,
      name: name,
      unitId: _unitId,
      function: _function,
      startAddress: _startAddress,
      quantity: quantity,
      values: values,
      enabled: widget.existing?.enabled ?? true,
    ));
  }

  int _parseRegister(String text) {
    final t = text.trim();
    final value = int.tryParse(t) ??
        int.tryParse(t.startsWith('0x') ? t.substring(2) : t, radix: 16);
    if (value == null) {
      throw const FormatException('寄存器值格式不正确');
    }
    return value & 0xFFFF;
  }

  List<int> _parseIntList(String text) {
    return text
        .split(RegExp(r'[\s,;]+'))
        .where((s) => s.isNotEmpty)
        .map((s) => int.tryParse(s) ??
            (throw FormatException('无法解析数值：$s')))
        .toList();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showQuantity = _function.isQuantityBased &&
        _function != ModbusFunction.writeMultipleCoils &&
        _function != ModbusFunction.writeMultipleRegisters;

    return AlertDialog(
      title: Text(widget.existing == null ? '添加请求' : '编辑请求'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<ModbusFunction>(
                initialValue: _function,
                decoration: const InputDecoration(
                  labelText: '功能码',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final f in ModbusFunction.values)
                    DropdownMenuItem(
                      value: f,
                      child: Text('0x${f.code.toRadixString(16).padLeft(2, '0').toUpperCase()}  ${f.label}'),
                    ),
                ],
                onChanged: (v) => setState(() => _function = v!),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('unitId'),
                      initialValue: '$_unitId',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: const InputDecoration(
                        labelText: '从机地址（0=广播）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => _unitId = int.tryParse(v) ?? 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('start'),
                      initialValue: '$_startAddress',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: const InputDecoration(
                        labelText: '起始地址（0-65535）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => _startAddress = int.tryParse(v) ?? 0,
                    ),
                  ),
                  if (showQuantity) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('qty'),
                        initialValue: '$_quantity',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: '数量',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => _quantity = int.tryParse(v) ?? 1,
                      ),
                    ),
                  ],
                ],
              ),
              if (_function == ModbusFunction.writeSingleCoil) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Switch(
                      value: _singleBitValue,
                      onChanged: (v) => setState(() => _singleBitValue = v),
                    ),
                    Text(_singleBitValue ? 'ON（0xFF00）' : 'OFF（0x0000）'),
                  ],
                ),
              ],
              if (_function == ModbusFunction.writeSingleRegister) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _singleRegister,
                  decoration: const InputDecoration(
                    labelText: '寄存器值（十进制或 0x.. 十六进制）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              if (_function == ModbusFunction.writeMultipleCoils) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _multiBits,
                  decoration: const InputDecoration(
                    labelText: '线圈值，逗号分隔 0/1（数量即写入个数）',
                    hintText: '1,0,1,1,0',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
              if (_function == ModbusFunction.writeMultipleRegisters) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('HEX')),
                        ButtonSegment(value: false, label: Text('DEC')),
                      ],
                      selected: {_hexInput},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) =>
                          setState(() => _hexInput = v.first),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _hexInput ? '每值 0-FFFF，逗号分隔' : '每值 0-65535',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _multiRegisters,
                  decoration: InputDecoration(
                    labelText: _hexInput
                        ? '寄存器值（HEX），逗号分隔'
                        : '寄存器值（十进制），逗号分隔',
                    border: const OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
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
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
