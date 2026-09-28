import 'dart:typed_data';

/// Modbus 标准功能码（模拟器支持的 8 个）。
enum ModbusFunction {
  readCoils(0x01, '读线圈', true, false),
  readDiscreteInputs(0x02, '读离散输入', true, false),
  readHoldingRegisters(0x03, '读保持寄存器', true, false),
  readInputRegisters(0x04, '读输入寄存器', true, false),
  writeSingleCoil(0x05, '写单个线圈', false, true),
  writeSingleRegister(0x06, '写单个寄存器', false, true),
  writeMultipleCoils(0x0F, '写多个线圈', true, true),
  writeMultipleRegisters(0x10, '写多个寄存器', true, true);

  const ModbusFunction(
    this.code,
    this.label,
    this.isQuantityBased,
    this.isWrite,
  );

  final int code;
  final String label;

  /// 请求是否带"起始地址 + 数量"结构（FC1-4、15、16）。
  final bool isQuantityBased;

  /// 是否为写功能码。
  final bool isWrite;

  bool get isRead => !isWrite;

  /// 位类型功能码（线圈 / 离散输入）。
  bool get isBitType =>
      this == ModbusFunction.readCoils ||
      this == ModbusFunction.readDiscreteInputs ||
      this == ModbusFunction.writeSingleCoil ||
      this == ModbusFunction.writeMultipleCoils;

  static ModbusFunction? fromCode(int code) {
    for (final f in ModbusFunction.values) {
      if (f.code == code) return f;
    }
    return null;
  }
}

/// Modbus 异常码（PDU 数据区首字节，功能码已置位 0x80）。
enum ModbusExceptionCode {
  illegalFunction(0x01, '非法功能码'),
  illegalDataAddress(0x02, '非法数据地址'),
  illegalDataValue(0x03, '非法数据值'),
  slaveDeviceFailure(0x04, '从机设备故障'),
  acknowledge(0x05, '确认'),
  busy(0x06, '从机忙');

  const ModbusExceptionCode(this.code, this.label);

  final int code;
  final String label;

  static String labelOf(int code) {
    for (final e in ModbusExceptionCode.values) {
      if (e.code == code) return e.label;
    } return '异常码 0x${code.toRadixString(16).padLeft(2, '0')}';
  }
}

/// Modbus 协议异常（从机返回异常响应时抛出 / 携带）。
class ModbusException implements Exception {
  const ModbusException(this.code, [this.detail]);

  final int code;
  final String? detail;

  String get message =>
      '${ModbusExceptionCode.labelOf(code)}${detail == null ? '' : '：$detail'}';

  @override
  String toString() => 'ModbusException($code, $message)';
}

/// 传输方式。
enum ModbusTransportMode { rtu('RTU（串口）'), tcp('TCP（网口）');

  const ModbusTransportMode(this.label);
  final String label;
}

/// 一个 Modbus 请求（主机侧构造、从机侧解析）。
class ModbusRequest {
  const ModbusRequest({
    required this.unitId,
    required this.function,
    required this.startAddress,
    this.quantity = 1,
    this.values = const [],
  });

  /// 从机地址（RTU 1-247；TCP 为 Unit ID，常用 1 或 255）。
  final int unitId;
  final ModbusFunction function;

  /// 起始地址（0-65535）。
  final int startAddress;

  /// 读数量 / 写多个时的数量。
  final int quantity;

  /// 写操作的值：位功能码为 0/1 列表；寄存器为 uint16 列表。
  final List<int> values;

  /// 编码 PDU（功能码 + 数据，不含地址/MBAP）。
  Uint8List encodePdu() {
    final b = BytesBuilder();
    b.addByte(function.code);
    switch (function) {
      case ModbusFunction.readCoils:
      case ModbusFunction.readDiscreteInputs:
      case ModbusFunction.readHoldingRegisters:
      case ModbusFunction.readInputRegisters:
        b.add(_word(startAddress));
        b.add(_word(quantity));
      case ModbusFunction.writeSingleCoil:
        b.add(_word(startAddress));
        b.add(_word((values.isNotEmpty && values.first != 0) ? 0xFF00 : 0x0000));
      case ModbusFunction.writeSingleRegister:
        b.add(_word(startAddress));
        b.add(_word(values.isEmpty ? 0 : values.first));
      case ModbusFunction.writeMultipleCoils:
        b.add(_word(startAddress));
        b.add(_word(quantity));
        final byteCount = (quantity + 7) ~/ 8;
        b.addByte(byteCount);
        b.add(_packBits(values, quantity));
      case ModbusFunction.writeMultipleRegisters:
        b.add(_word(startAddress));
        b.add(_word(quantity));
        b.addByte(quantity * 2);
        for (final v in values) {
          b.add(_word(v));
        }
    }
    return b.toBytes();
  }

  /// 解析请求 PDU（[pdu] 含功能码首字节）。
  factory ModbusRequest.decodePdu(int unitId, Uint8List pdu) {
    final function = ModbusFunction.fromCode(pdu[0]);
    if (function == null) {
      throw const ModbusException(0x01);
    }
    int word(int offset) =>
        ((pdu[offset] & 0xFF) << 8) | (pdu[offset + 1] & 0xFF);

    switch (function) {
      case ModbusFunction.readCoils:
      case ModbusFunction.readDiscreteInputs:
      case ModbusFunction.readHoldingRegisters:
      case ModbusFunction.readInputRegisters:
        _expectLength(pdu, 5);
        return ModbusRequest(
          unitId: unitId,
          function: function,
          startAddress: word(1),
          quantity: word(3),
        );
      case ModbusFunction.writeSingleCoil:
        _expectLength(pdu, 5);
        return ModbusRequest(
          unitId: unitId,
          function: function,
          startAddress: word(1),
          quantity: 1,
          values: [word(3) == 0xFF00 ? 1 : 0],
        );
      case ModbusFunction.writeSingleRegister:
        _expectLength(pdu, 5);
        return ModbusRequest(
          unitId: unitId,
          function: function,
          startAddress: word(1),
          quantity: 1,
          values: [word(3)],
        );
      case ModbusFunction.writeMultipleCoils:
        _expectLength(pdu, 6);
        final start = word(1);
        final qty = word(3);
        final byteCount = pdu[5] & 0xFF;
        _expectLength(pdu, 6 + byteCount);
        return ModbusRequest(
          unitId: unitId,
          function: function,
          startAddress: start,
          quantity: qty,
          values: _unpackBits(pdu.sublist(6, 6 + byteCount), qty),
        );
      case ModbusFunction.writeMultipleRegisters:
        _expectLength(pdu, 6);
        final start = word(1);
        final qty = word(3);
        final byteCount = pdu[5] & 0xFF;
        _expectLength(pdu, 6 + byteCount);
        final values = <int>[
          for (var i = 0; i < qty; i++) word(6 + i * 2),
        ];
        return ModbusRequest(
          unitId: unitId,
          function: function,
          startAddress: start,
          quantity: qty,
          values: values,
        );
    }
  }

  static void _expectLength(Uint8List pdu, int length) {
    if (pdu.length < length) {
      throw const ModbusException(0x03, '报文长度不足');
    }
  }

  static List<int> _word(int value) =>
      [(value >> 8) & 0xFF, value & 0xFF];

  static List<int> _packBits(List<int> bits, int qty) {
    final bytes = <int>[];
    for (var i = 0; i < qty; i++) {
      if (i % 8 == 0) bytes.add(0);
      if (i < bits.length && bits[i] != 0) {
        bytes[i ~/ 8] |= (1 << (i % 8));
      }
    }
    return bytes;
  }

  static List<int> _unpackBits(List<int> bytes, int qty) {
    final bits = <int>[];
    for (var i = 0; i < qty; i++) {
      bits.add((bytes[i ~/ 8] >> (i % 8)) & 0x01);
    }
    return bits;
  }
}

/// 主机收到的响应解析结果。
class ModbusResponse {
  const ModbusResponse({
    required this.function,
    required this.isException,
    this.exceptionCode,
    this.bits = const [],
    this.registers = const [],
    this.echoAddress,
    this.echoQuantity,
    this.echoValue,
  });

  final ModbusFunction function;
  final bool isException;
  final int? exceptionCode;

  /// 读位操作返回的位值；读寄存器返回的 uint16 值。
  final List<int> bits;
  final List<int> registers;

  /// 写操作响应回显。
  final int? echoAddress;
  final int? echoQuantity;
  final int? echoValue;

  /// 解析响应 PDU（[pdu] 含功能码首字节），需结合请求的 [request] 判定类型。
  factory ModbusResponse.decode(ModbusRequest request, Uint8List pdu) {
    if (pdu.isEmpty) {
      throw const ModbusException(0x04, '响应为空');
    }
    final rawCode = pdu[0] & 0xFF;
    if ((rawCode & 0x80) != 0) {
      if (pdu.length < 2) {
        throw const ModbusException(0x04, '异常响应长度不足');
      }
      final code = pdu[1] & 0xFF;
      final function = ModbusFunction.fromCode(rawCode & 0x7F) ??
          request.function;
      return ModbusResponse(
        function: function,
        isException: true,
        exceptionCode: code,
      );
    }

    final function = ModbusFunction.fromCode(rawCode) ?? request.function;
    int word(int offset) =>
        ((pdu[offset] & 0xFF) << 8) | (pdu[offset + 1] & 0xFF);

    switch (function) {
      case ModbusFunction.readCoils:
      case ModbusFunction.readDiscreteInputs:
        final byteCount = pdu[1] & 0xFF;
        final bits = _decodeBits(
          pdu.sublist(2, 2 + byteCount),
          request.quantity,
        );
        return ModbusResponse(function: function, isException: false, bits: bits);
      case ModbusFunction.readHoldingRegisters:
      case ModbusFunction.readInputRegisters:
        final byteCount = pdu[1] & 0xFF;
        final count = byteCount ~/ 2;
        return ModbusResponse(
          function: function,
          isException: false,
          registers: [for (var i = 0; i < count; i++) word(2 + i * 2)],
        );
      case ModbusFunction.writeSingleCoil:
      case ModbusFunction.writeSingleRegister:
        return ModbusResponse(
          function: function,
          isException: false,
          echoAddress: word(1),
          echoValue: word(3),
        );
      case ModbusFunction.writeMultipleCoils:
      case ModbusFunction.writeMultipleRegisters:
        return ModbusResponse(
          function: function,
          isException: false,
          echoAddress: word(1),
          echoQuantity: word(3),
        );
    }
  }

  static List<int> _decodeBits(List<int> bytes, int qty) {
    final bits = <int>[];
    for (var i = 0; i < qty; i++) {
      bits.add((bytes[i ~/ 8] >> (i % 8)) & 0x01);
    }
    return bits;
  }
}
