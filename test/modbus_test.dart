import 'dart:typed_data';

import 'package:debug_assistant/features/modbus/domain/modbus_crc.dart';
import 'package:debug_assistant/features/modbus/domain/modbus_master_controller.dart';
import 'package:debug_assistant/features/modbus/domain/modbus_pdu.dart';
import 'package:debug_assistant/features/modbus/domain/modbus_register_bank.dart';
import 'package:debug_assistant/features/modbus/domain/modbus_slave_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CRC16', () {
    test('标准向量 01 03 00 00 00 0A → CRC 寄存器 0xCDC5（低字节先发 C5 CD）',
        () {
      final body = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A];
      expect(ModbusCrc.calculate(body), 0xCDC5);
      final frame = ModbusCrc.append(body);
      expect(frame[frame.length - 2], 0xC5);
      expect(frame[frame.length - 1], 0xCD);
      expect(ModbusCrc.verify(frame), isTrue);
    });

    test('篡改任意字节后校验失败', () {
      final frame = ModbusCrc.append([0x01, 0x03, 0x00, 0x00]);
      frame[1] = 0x04;
      expect(ModbusCrc.verify(frame), isFalse);
    });
  });

  group('PDU 编解码', () {
    test('FC3 读保持寄存器请求往返', () {
      const req = ModbusRequest(
        unitId: 1,
        function: ModbusFunction.readHoldingRegisters,
        startAddress: 0x0102,
        quantity: 10,
      );
      final pdu = req.encodePdu();
      expect(pdu, [0x03, 0x01, 0x02, 0x00, 0x0A]);
      final decoded = ModbusRequest.decodePdu(1, Uint8List.fromList(pdu));
      expect(decoded.startAddress, 0x0102);
      expect(decoded.quantity, 10);
    });

    test('FC16 写多个寄存器往返', () {
      const req = ModbusRequest(
        unitId: 2,
        function: ModbusFunction.writeMultipleRegisters,
        startAddress: 0x0000,
        quantity: 3,
        values: [0x1234, 0xABCD, 0x0001],
      );
      final pdu = req.encodePdu();
      expect(pdu,
          [0x10, 0x00, 0x00, 0x00, 0x03, 0x06, 0x12, 0x34, 0xAB, 0xCD, 0x00, 0x01]);
      final decoded = ModbusRequest.decodePdu(2, Uint8List.fromList(pdu));
      expect(decoded.values, [0x1234, 0xABCD, 0x0001]);
    });

    test('FC15 多线圈打包与解包', () {
      const req = ModbusRequest(
        unitId: 1,
        function: ModbusFunction.writeMultipleCoils,
        startAddress: 0,
        quantity: 10,
        values: [1, 0, 1, 1, 0, 0, 1, 0, 1, 1],
      );
      final pdu = req.encodePdu();
      expect(pdu[5], 2); // byte count
      final decoded = ModbusRequest.decodePdu(1, Uint8List.fromList(pdu));
      expect(decoded.values, [1, 0, 1, 1, 0, 0, 1, 0, 1, 1]);
    });
  });

  group('从机寄存器库', () {
    test('FC3 读保持寄存器返回正确字节', () {
      final bank = ModbusRegisterBank();
      bank.setHoldingRegister(0, 0x0102);
      bank.setHoldingRegister(1, 0x0304);
      const req = ModbusRequest(
        unitId: 1,
        function: ModbusFunction.readHoldingRegisters,
        startAddress: 0,
        quantity: 2,
      );
      final resp = bank.handleRequest(req);
      expect(resp, [0x03, 0x04, 0x01, 0x02, 0x03, 0x04]);
    });

    test('FC1 读线圈位打包', () {
      final bank = ModbusRegisterBank();
      bank.setCoil(0, true);
      bank.setCoil(2, true);
      bank.setCoil(7, true);
      const req = ModbusRequest(
        unitId: 1,
        function: ModbusFunction.readCoils,
        startAddress: 0,
        quantity: 8,
      );
      final resp = bank.handleRequest(req);
      expect(resp, [0x01, 0x01, 0x85]); // bit0 + bit2 + bit7 = 10000101
    });

    test('FC6 写单个寄存器后可读回', () {
      final bank = ModbusRegisterBank();
      const write = ModbusRequest(
        unitId: 1,
        function: ModbusFunction.writeSingleRegister,
        startAddress: 10,
        values: [0xBEEF],
      );
      final resp = bank.handleRequest(write);
      expect(resp, [0x06, 0x00, 0x0A, 0xBE, 0xEF]);
      expect(bank.holdingRegisters[10], 0xBEEF);
    });

    test('地址越界返回非法数据地址异常 0x02', () {
      final bank = ModbusRegisterBank(holdingCount: 100);
      const req = ModbusRequest(
        unitId: 1,
        function: ModbusFunction.readHoldingRegisters,
        startAddress: 90,
        quantity: 20,
      );
      expect(
        () => bank.handleRequest(req),
        throwsA(isA<ModbusException>()
            .having((e) => e.code, 'code', 0x02)),
      );
    });

    test('数量超过 125 返回非法数据值异常 0x03', () {
      final bank = ModbusRegisterBank();
      const req = ModbusRequest(
        unitId: 1,
        function: ModbusFunction.readHoldingRegisters,
        startAddress: 0,
        quantity: 200,
      );
      expect(
        () => bank.handleRequest(req),
        throwsA(isA<ModbusException>()
            .having((e) => e.code, 'code', 0x03)),
      );
    });
  });

  group('TCP 主从回环', () {
    const port = 19502;
    late ModbusSlaveController slave;
    late ModbusMasterController master;

    setUp(() async {
      slave = ModbusSlaveController(
        config: const SlaveConfig(tcpPort: port),
        bank: ModbusRegisterBank(),
      );
      await slave.start();
      master = ModbusMasterController(
        config: const MasterConfig(
          mode: ModbusTransportMode.tcp,
          host: '127.0.0.1',
          port: port,
          timeoutMs: 2000,
        ),
      );
      await master.connect();
    });

    tearDown(() async {
      await master.disconnect();
      await slave.stop();
      master.dispose();
      slave.dispose();
    });

    test('FC3 读保持寄存器', () async {
      slave.bank.setHoldingRegister(0, 0x1122);
      slave.bank.setHoldingRegister(1, 0x3344);
      final item = MasterPollItem(
        id: 't1',
        name: '读HR',
        unitId: 1,
        function: ModbusFunction.readHoldingRegisters,
        startAddress: 0,
        quantity: 2,
      );
      await master.execute(item);
      expect(item.lastError, isNull);
      expect(item.lastResult!.registers, [0x1122, 0x3344]);
      expect(master.txFrames, 1);
      expect(master.rxFrames, 1);
    });

    test('FC16 写多个寄存器后 FC3 读回', () async {
      final write = MasterPollItem(
        id: 't2',
        name: '写多寄存器',
        unitId: 1,
        function: ModbusFunction.writeMultipleRegisters,
        startAddress: 5,
        quantity: 3,
        values: [0x0001, 0x0002, 0x0003],
      );
      await master.execute(write);
      expect(write.lastError, isNull);
      expect(write.lastResult!.echoQuantity, 3);
      expect(slave.bank.holdingRegisters.sublist(5, 8).toList(), [1, 2, 3]);

      final read = MasterPollItem(
        id: 't3',
        name: '读回',
        unitId: 1,
        function: ModbusFunction.readHoldingRegisters,
        startAddress: 5,
        quantity: 3,
      );
      await master.execute(read);
      expect(read.lastResult!.registers, [1, 2, 3]);
    });

    test('FC1 读线圈与 FC5 写单线圈', () async {
      final write = MasterPollItem(
        id: 't4',
        name: '写线圈',
        unitId: 1,
        function: ModbusFunction.writeSingleCoil,
        startAddress: 3,
        values: [1],
      );
      await master.execute(write);
      expect(slave.bank.coils[3], 1);

      final read = MasterPollItem(
        id: 't5',
        name: '读线圈',
        unitId: 1,
        function: ModbusFunction.readCoils,
        startAddress: 0,
        quantity: 8,
      );
      await master.execute(read);
      expect(read.lastResult!.bits[3], 1);
      expect(read.lastResult!.bits[0], 0);
    });

    test('越界读取收到异常响应（0x83 + 0x02）', () async {
      final item = MasterPollItem(
        id: 't6',
        name: '越界',
        unitId: 1,
        function: ModbusFunction.readHoldingRegisters,
        startAddress: 950,
        quantity: 100,
      );
      await master.execute(item);
      expect(item.lastResult!.isException, isTrue);
      expect(item.lastResult!.exceptionCode, 0x02);
      expect(item.lastError, contains('非法数据地址'));
    });
  });
}
