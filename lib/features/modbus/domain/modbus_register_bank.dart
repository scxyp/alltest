import 'dart:typed_data';

import 'modbus_pdu.dart';

/// Modbus 从机的四个数据区。
///
/// - 线圈（Coils，0x 区，FC1 读 / FC5,15 写，位）
/// - 离散输入（Discrete Inputs，1x 区，FC2 只读，位）
/// - 保持寄存器（Holding Registers，4x 区，FC3 读 / FC6,16 写，uint16）
/// - 输入寄存器（Input Registers，3x 区，FC4 只读，uint16）
class ModbusRegisterBank {
  ModbusRegisterBank({
    int coilCount = 1000,
    int discreteCount = 1000,
    int holdingCount = 1000,
    int inputCount = 1000,
  })  : coils = Uint8List(coilCount),
        discreteInputs = Uint8List(discreteCount),
        holdingRegisters = Uint16List(holdingCount),
        inputRegisters = Uint16List(inputCount);

  /// 位区用 0/1 表示。
  final Uint8List coils;
  final Uint8List discreteInputs;
  final Uint16List holdingRegisters;
  final Uint16List inputRegisters;

  Map<String, dynamic> toJson() => {
        'coils': coils.toList(),
        'discreteInputs': discreteInputs.toList(),
        'holdingRegisters': holdingRegisters.toList(),
        'inputRegisters': inputRegisters.toList(),
      };

  factory ModbusRegisterBank.fromJson(Map<String, dynamic> json) {
    final bank = ModbusRegisterBank(
      coilCount: (json['coils'] as List?)?.length ?? 1000,
      discreteCount: (json['discreteInputs'] as List?)?.length ?? 1000,
      holdingCount: (json['holdingRegisters'] as List?)?.length ?? 1000,
      inputCount: (json['inputRegisters'] as List?)?.length ?? 1000,
    );
    _fillByte(bank.coils, json['coils']);
    _fillByte(bank.discreteInputs, json['discreteInputs']);
    _fillWord(bank.holdingRegisters, json['holdingRegisters']);
    _fillWord(bank.inputRegisters, json['inputRegisters']);
    return bank;
  }

  static void _fillByte(Uint8List target, dynamic source) {
    if (source is List) {
      for (var i = 0; i < target.length && i < source.length; i++) {
        target[i] = (source[i] as num).toInt() & 0x01;
      }
    }
  }

  static void _fillWord(Uint16List target, dynamic source) {
    if (source is List) {
      for (var i = 0; i < target.length && i < source.length; i++) {
        target[i] = (source[i] as num).toInt() & 0xFFFF;
      }
    }
  }

  // --- UI 编辑用 ---

  void setCoil(int address, bool value) {
    if (address < 0 || address >= coils.length) return;
    coils[address] = value ? 1 : 0;
  }

  void setDiscreteInput(int address, bool value) {
    if (address < 0 || address >= discreteInputs.length) return;
    discreteInputs[address] = value ? 1 : 0;
  }

  void setHoldingRegister(int address, int value) {
    if (address < 0 || address >= holdingRegisters.length) return;
    holdingRegisters[address] = value & 0xFFFF;
  }

  void setInputRegister(int address, int value) {
    if (address < 0 || address >= inputRegisters.length) return;
    inputRegisters[address] = value & 0xFFFF;
  }

  /// 处理请求 PDU，返回**响应 PDU（含功能码首字节）**。
  ///
  /// 出错时抛出 [ModbusException]（由调用方转为异常响应）。
  Uint8List handleRequest(ModbusRequest request) {
    final b = BytesBuilder();
    switch (request.function) {
      case ModbusFunction.readCoils:
        _checkReadRange(request, coils.length, 2000);
        b.addByte(ModbusFunction.readCoils.code);
        b.addByte((request.quantity + 7) ~/ 8);
        b.add(_readBits(coils, request.startAddress, request.quantity));
      case ModbusFunction.readDiscreteInputs:
        _checkReadRange(request, discreteInputs.length, 2000);
        b.addByte(ModbusFunction.readDiscreteInputs.code);
        b.addByte((request.quantity + 7) ~/ 8);
        b.add(_readBits(discreteInputs, request.startAddress, request.quantity));
      case ModbusFunction.readHoldingRegisters:
        _checkReadRange(request, holdingRegisters.length, 125);
        b.addByte(ModbusFunction.readHoldingRegisters.code);
        b.addByte(request.quantity * 2);
        for (final v in _readWords(
            holdingRegisters, request.startAddress, request.quantity)) {
          b.addByte((v >> 8) & 0xFF);
          b.addByte(v & 0xFF);
        }
      case ModbusFunction.readInputRegisters:
        _checkReadRange(request, inputRegisters.length, 125);
        b.addByte(ModbusFunction.readInputRegisters.code);
        b.addByte(request.quantity * 2);
        for (final v in _readWords(
            inputRegisters, request.startAddress, request.quantity)) {
          b.addByte((v >> 8) & 0xFF);
          b.addByte(v & 0xFF);
        }
      case ModbusFunction.writeSingleCoil:
        _checkAddress(request.startAddress, coils.length);
        coils[request.startAddress] =
            request.values.isNotEmpty && request.values.first != 0 ? 1 : 0;
        b.addByte(ModbusFunction.writeSingleCoil.code);
        b.add(_word(request.startAddress));
        b.add(_word(coils[request.startAddress] != 0 ? 0xFF00 : 0x0000));
      case ModbusFunction.writeSingleRegister:
        _checkAddress(request.startAddress, holdingRegisters.length);
        holdingRegisters[request.startAddress] =
            request.values.isEmpty ? 0 : request.values.first & 0xFFFF;
        b.addByte(ModbusFunction.writeSingleRegister.code);
        b.add(_word(request.startAddress));
        b.add(_word(holdingRegisters[request.startAddress]));
      case ModbusFunction.writeMultipleCoils:
        _checkWriteRange(request, coils.length, 1968);
        for (var i = 0; i < request.quantity; i++) {
          coils[request.startAddress + i] =
              i < request.values.length && request.values[i] != 0 ? 1 : 0;
        }
        b.addByte(ModbusFunction.writeMultipleCoils.code);
        b.add(_word(request.startAddress));
        b.add(_word(request.quantity));
      case ModbusFunction.writeMultipleRegisters:
        _checkWriteRange(request, holdingRegisters.length, 123);
        for (var i = 0; i < request.quantity; i++) {
          holdingRegisters[request.startAddress + i] =
              i < request.values.length ? request.values[i] & 0xFFFF : 0;
        }
        b.addByte(ModbusFunction.writeMultipleRegisters.code);
        b.add(_word(request.startAddress));
        b.add(_word(request.quantity));
    }
    return b.toBytes();
  }

  void _checkAddress(int address, int length) {
    if (address < 0 || address >= length) {
      throw const ModbusException(0x02, '地址超出数据区范围');
    }
  }

  void _checkReadRange(ModbusRequest r, int length, int maxQuantity) {
    if (r.quantity < 1 || r.quantity > maxQuantity) {
      throw ModbusException(0x03, '读取数量应在 1-$maxQuantity 之间');
    }
    if (r.startAddress < 0 ||
        r.startAddress + r.quantity > length) {
      throw const ModbusException(0x02, '地址超出数据区范围');
    }
  }

  void _checkWriteRange(ModbusRequest r, int length, int maxQuantity) {
    if (r.quantity < 1 || r.quantity > maxQuantity) {
      throw ModbusException(0x03, '写入数量应在 1-$maxQuantity 之间');
    }
    if (r.startAddress < 0 ||
        r.startAddress + r.quantity > length) {
      throw const ModbusException(0x02, '地址超出数据区范围');
    }
  }

  List<int> _readBits(Uint8List area, int start, int qty) {
    final bytes = <int>[];
    for (var i = 0; i < qty; i++) {
      if (i % 8 == 0) bytes.add(0);
      if (area[start + i] != 0) bytes[i ~/ 8] |= (1 << (i % 8));
    }
    return bytes;
  }

  List<int> _readWords(Uint16List area, int start, int qty) =>
      [for (var i = 0; i < qty; i++) area[start + i]];

  static List<int> _word(int value) =>
      [(value >> 8) & 0xFF, value & 0xFF];
}
