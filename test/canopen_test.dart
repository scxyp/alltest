import 'dart:typed_data';

import 'package:debug_assistant/features/can/domain/can_config.dart';
import 'package:debug_assistant/features/can/domain/can_frame.dart';
import 'package:debug_assistant/features/canopen/domain/canopen_config.dart';
import 'package:debug_assistant/features/canopen/domain/canopen_nmt.dart';
import 'package:debug_assistant/features/canopen/domain/canopen_sdo.dart';
import 'package:debug_assistant/features/canopen/domain/canopen_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CanOpenConfig', () {
    test('toJson / fromJson 往返一致', () {
      const config = CanOpenConfig(
        portName: 'COM5',
        baudRate: 115200,
        nodeId: 5,
      );
      final restored = CanOpenConfig.fromJson(config.toJson());
      expect(restored.portName, 'COM5');
      expect(restored.baudRate, 115200);
      expect(restored.canBitrate, CanBitrate.speed500K);
      expect(restored.nodeId, 5);
    });

    test('fromJson 容错：缺失字段使用默认值', () {
      final restored = CanOpenConfig.fromJson({});
      expect(restored.portName, isEmpty);
      expect(restored.baudRate, 115200);
      expect(restored.canBitrate, CanBitrate.speed500K);
      expect(restored.nodeId, 1);
    });

    test('summary 包含端口和 Node ID', () {
      const config = CanOpenConfig(portName: 'COM5', nodeId: 3);
      expect(config.summary, contains('COM5'));
      expect(config.summary, contains('Node 3'));
    });

    test('toCanConfig 转换正确', () {
      const config = CanOpenConfig(
        portName: 'COM5',
        baudRate: 115200,
        canBitrate: CanBitrate.speed250K,
        nodeId: 7,
      );
      final can = config.toTransportConfig();
      expect(can.portName, 'COM5');
      expect(can.rawConfig['baudRate'], 115200);
      expect(can.canBitrate, CanBitrate.speed250K);
    });

    test('copyWith 仅修改指定字段', () {
      const config = CanOpenConfig(portName: 'COM5', nodeId: 3);
      final updated = config.copyWith(nodeId: 10);
      expect(updated.portName, 'COM5');
      expect(updated.nodeId, 10);
    });
  });

  group('SdoCodec Expedited 编解码', () {
    test('读取请求编码正确', () {
      final data = SdoCodec.buildReadRequest(0x1000, 0x00);
      expect(data.length, 8);
      expect(data[0], 0x40);
      expect(data[1], 0x00); // Index 小端
      expect(data[2], 0x10);
      expect(data[3], 0x00); // Subindex
    });

    test('4 字节写入请求编码正确', () {
      final data = SdoCodec.buildWriteRequest(
        0x2000,
        0x01,
        Uint8List.fromList([0x11, 0x22, 0x33, 0x44]),
      );
      expect(data, isNotNull);
      expect(data![0], 0x23); // 4字节 Expedited Write
      expect(data[1], 0x00);
      expect(data[2], 0x20);
      expect(data[3], 0x01);
      expect(data[4], 0x11);
      expect(data[5], 0x22);
      expect(data[6], 0x33);
      expect(data[7], 0x44);
    });

    test('1 字节写入请求编码正确', () {
      final data = SdoCodec.buildWriteRequest(
        0x1018,
        0x01,
        Uint8List.fromList([0x05]),
      );
      expect(data, isNotNull);
      expect(data![0], 0x27); // 1字节 Expedited Write
      expect(data[4], 0x05);
      expect(data[5], 0);
      expect(data[6], 0);
      expect(data[7], 0);
    });

    test('空数据写入返回 null', () {
      final data = SdoCodec.buildWriteRequest(0x1000, 0x00, Uint8List(0));
      expect(data, isNull);
    });

    test('>4 字节写入返回 null（Expedited 不支持）', () {
      final data = SdoCodec.buildWriteRequest(
        0x1000,
        0x00,
        Uint8List(5),
      );
      expect(data, isNull);
    });

    test('解析 Read Expedited 响应', () {
      // 构造 Read OK 响应：0x42, Index, Index, Subindex, 数据...
      final data = Uint8List.fromList([0x42, 0x00, 0x10, 0x00, 0xAA, 0xBB, 0xCC, 0xDD]);
      final result = SdoCodec.parseResponse(data);
      expect(result, isNotNull);
      expect(result!.type, SdoResponse.readOk);
      expect(result.index, 0x1000);
      expect(result.subindex, 0x00);
      expect(result.data, [0xAA, 0xBB, 0xCC, 0xDD]);
    });

    test('解析 Write Expedited 响应', () {
      final data = Uint8List.fromList([0x43, 0x00, 0x20, 0x01, 0, 0, 0, 0]);
      final result = SdoCodec.parseResponse(data);
      expect(result, isNotNull);
      expect(result!.type, SdoResponse.writeOk);
      expect(result.index, 0x2000);
      expect(result.subindex, 0x01);
    });

    test('解析 Abort 响应', () {
      final data = Uint8List.fromList([0x80, 0x00, 0x10, 0x00, 0x02, 0x00, 0x06, 0x06]);
      final result = SdoCodec.parseResponse(data);
      expect(result, isNotNull);
      expect(result!.type, SdoResponse.abort);
      expect(result.abortCode, 0x06060002); // 小端拼接
    });

    test('长度不对的帧返回 null', () {
      expect(SdoCodec.parseResponse(Uint8List(0)), isNull);
      expect(SdoCodec.parseResponse(Uint8List(4)), isNull);
      expect(SdoCodec.parseResponse(Uint8List(16)), isNull);
    });

    test('Expedited 请求 → 响应往返', () {
      // 客户端发读请求 → 服务器回读响应
      final reqData = SdoCodec.buildReadRequest(0x1008, 0x00);
      expect(reqData[0], 0x40);

      // 服务器响应
      final respData = Uint8List.fromList([
        0x42,
        reqData[1], reqData[2], reqData[3],
        0x01, 0x00, 0x00, 0x00, // 版本号 1
      ]);
      final result = SdoCodec.parseResponse(respData);
      expect(result, isNotNull);
      expect(result!.type, SdoResponse.readOk);
      expect(result.index, 0x1008);
      expect(result.subindex, 0x00);
      expect(result.data, [0x01, 0x00, 0x00, 0x00]);
    });
  });

  group('NmtCodec', () {
    test('Start 命令编码正确', () {
      final data = NmtCodec.buildNmtCommand(NmtCommand.start, 1);
      expect(data.length, 3);
      expect(data[0], 0x01);
      expect(data[1], 1);
      expect(data[2], 0);
    });

    test('Reset 命令编码正确', () {
      final data = NmtCodec.buildNmtCommand(NmtCommand.reset, 5);
      expect(data[0], 0x81);
      expect(data[1], 5);
    });

    test('广播命令（targetNodeId=0）编码正确', () {
      final data = NmtCodec.buildNmtCommand(NmtCommand.start, 0);
      expect(data[1], 0);
    });

    test('Heartbeat 状态解析', () {
      expect(NmtCodec.parseHeartbeat(Uint8List.fromList([0x00])),
          NmtState.bootUp);
      expect(NmtCodec.parseHeartbeat(Uint8List.fromList([0x04])),
          NmtState.stopped);
      expect(NmtCodec.parseHeartbeat(Uint8List.fromList([0x05])),
          NmtState.operational);
      expect(NmtCodec.parseHeartbeat(Uint8List.fromList([0x7F])),
          NmtState.preOperational);
    });

    test('未知 Heartbeat 状态返回 null', () {
      expect(NmtCodec.parseHeartbeat(Uint8List.fromList([0x03])), isNull);
    });

    test('空 Heartbeat 返回 null', () {
      expect(NmtCodec.parseHeartbeat(Uint8List(0)), isNull);
    });

    test('COB-ID 基址常量', () {
      expect(NmtCodec.controlCobId, 0x000);
      expect(NmtCodec.heartbeatCobIdBase, 0x700);
    });
  });

  group('CanOpenSession', () {
    test('初始状态为未连接', () {
      final session = CanOpenSession(
        id: 'co1',
        config: const CanOpenConfig(portName: 'COM99'),
      );
      expect(session.isConnected, isFalse);
      expect(session.logs, isEmpty);
      expect(session.rxBytes, 0);
      expect(session.txBytes, 0);
      expect(session.nodeStates, isEmpty);
      session.dispose();
    });

    test('默认帧 ID 为 SDO Request COB-ID', () {
      final session = CanOpenSession(
        id: 'co2',
        config: const CanOpenConfig(portName: 'COM99', nodeId: 5),
      );
      // SDO Request COB-ID = 0x600 + Node ID = 0x605
      expect(session.frameId, 0x605);
      session.dispose();
    });

    test('frameId 属性变更触发通知', () {
      final session = CanOpenSession(
        id: 'co3',
        config: const CanOpenConfig(portName: 'COM99'),
      );
      var notified = false;
      session.addListener(() => notified = true);
      session.frameId = 0x123;
      expect(notified, isTrue);
      expect(session.frameId, 0x123);
      session.dispose();
    });

    test('未连接时 sendContent 抛出 StateError', () {
      final session = CanOpenSession(
        id: 'co4',
        config: const CanOpenConfig(portName: 'COM99'),
      );
      expect(
        () => session.sendContent('AA BB', asHex: true),
        throwsA(isA<StateError>()),
      );
      session.dispose();
    });

    test('未连接时 sendNmt 抛出 StateError', () {
      final session = CanOpenSession(
        id: 'co5',
        config: const CanOpenConfig(portName: 'COM99'),
      );
      expect(
        () => session.sendNmt(NmtCommand.start),
        throwsA(isA<StateError>()),
      );
      session.dispose();
    });

    test('未连接时 sdoRead/sdoWrite 抛出 StateError', () async {
      final session = CanOpenSession(
        id: 'co6',
        config: const CanOpenConfig(portName: 'COM99'),
      );
      await expectLater(
        session.sdoRead(0x1000, 0x00),
        throwsA(isA<StateError>()),
      );
      expect(
        () => session.sdoWrite(0x1000, 0x00, Uint8List.fromList([0x01])),
        throwsA(isA<StateError>()),
      );
      session.dispose();
    });

    test('clearLogs 清空日志并归零计数', () {
      final session = CanOpenSession(
        id: 'co7',
        config: const CanOpenConfig(portName: 'COM99'),
      );
      session.clearLogs();
      expect(session.logs, isEmpty);
      expect(session.rxBytes, 0);
      expect(session.txBytes, 0);
      session.dispose();
    });

    test('updateConfig 未连接时生效并更新默认帧 ID', () {
      final session = CanOpenSession(
        id: 'co8',
        config: const CanOpenConfig(portName: 'COM99', nodeId: 1),
      );
      session.updateConfig(const CanOpenConfig(
        portName: 'COM100',
        nodeId: 10,
      ));
      expect(session.config.portName, 'COM100');
      expect(session.config.nodeId, 10);
      expect(session.frameId, 0x60A); // 0x600 + 10 = 0x60A
      session.dispose();
    });
  });

  group('CanOpenSession SDO 解析', () {
    /// 通过手动操作 pendingSdos + routeFrame 模拟 SDO 请求/响应流程。
    test('SDO 响应帧路由并匹配待处理请求', () async {
      final session = CanOpenSession(
        id: 'co9',
        config: const CanOpenConfig(portName: 'COM99', nodeId: 3),
      );

      // 手动构造一个待处理请求（绕过串口连接）
      final pending = PendingSdo.read(0x1000, 0x00, 3);
      session.pendingSdos.add(pending);

      // 模拟接收到 SDO 响应帧（来自 Node 3）
      final respCanFrame = CanFrame(
        id: 0x583, // SDO Response COB-ID = 0x580 + 3
        extended: false,
        remote: false,
        data: Uint8List.fromList([
          0x42, // Read OK Expedited
          0x00, 0x10, // Index 0x1000 (LE)
          0x00, // Subindex
          0xDE, 0xAD, 0xBE, 0xEF, // 数据
        ]),
      );
      session.routeFrame(respCanFrame);

      // 等待响应处理
      final result = await pending.completer.future
          .timeout(const Duration(milliseconds: 100));
      expect(result.type, SdoResponse.readOk);
      expect(result.data, [0xDE, 0xAD, 0xBE, 0xEF]);
      expect(result.fromNodeId, 3);
      expect(session.pendingSdos, isEmpty);

      session.dispose();
    });

    test('Heartbeat 帧路由并更新节点状态', () {
      final session = CanOpenSession(
        id: 'co10',
        config: const CanOpenConfig(portName: 'COM99', nodeId: 1),
      );

      final hbFrame = CanFrame(
        id: 0x705, // Heartbeat from Node 5
        extended: false,
        remote: false,
        data: Uint8List.fromList([0x05]), // Operational
      );
      session.routeFrame(hbFrame);

      expect(session.nodeStates.containsKey(5), isTrue);
      expect(session.nodeStates[5]!.lastState, NmtState.operational);

      session.dispose();
    });

    test('EMCY 帧路由到日志', () {
      final session = CanOpenSession(
        id: 'co11',
        config: const CanOpenConfig(portName: 'COM99'),
      );

      final emcyFrame = CanFrame(
        id: 0x103, // EMCY from Node 3
        extended: false,
        remote: false,
        data: Uint8List.fromList([0x01, 0x10]),
      );
      session.routeFrame(emcyFrame);

      final hasEmcy = session.logs.any(
        (e) => e.source != null && e.source!.contains('EMCY'),
      );
      expect(hasEmcy, isTrue);

      session.dispose();
    });
  });
}
