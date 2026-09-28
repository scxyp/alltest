import 'dart:typed_data';

import 'package:debug_assistant/core/ui/line_ending.dart';
import 'package:debug_assistant/features/can/domain/can_config.dart';
import 'package:debug_assistant/features/can/domain/can_frame.dart';
import 'package:debug_assistant/features/can/domain/can_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CanConfig', () {
    test('toJson / fromJson 往返一致', () {
      const config = CanConfig(
        portName: 'COM5',
        baudRate: 115200,
        canBitrate: CanBitrate.speed500K,
      );
      final restored = CanConfig.fromJson(config.toJson());
      expect(restored.portName, 'COM5');
      expect(restored.baudRate, 115200);
      expect(restored.canBitrate, CanBitrate.speed500K);
    });

    test('fromJson 容错：缺失字段使用默认值', () {
      final restored = CanConfig.fromJson({});
      expect(restored.portName, isEmpty);
      expect(restored.baudRate, 115200);
      expect(restored.canBitrate, CanBitrate.speed500K);
    });

    test('summary 包含端口与 CAN 波特率', () {
      const config = CanConfig(portName: 'COM5', baudRate: 115200);
      expect(config.summary, contains('COM5'));
      expect(config.summary, contains('115200'));
      expect(config.summary, contains('500 kbps'));
    });

    test('copyWith 仅修改指定字段', () {
      const config = CanConfig(portName: 'COM5');
      final updated = config.copyWith(canBitrate: CanBitrate.speed250K);
      expect(updated.portName, 'COM5');
      expect(updated.canBitrate, CanBitrate.speed250K);
    });
  });

  group('CanBitrate', () {
    test('slcanCode 与 SLCAN 规范一致', () {
      expect(CanBitrate.speed10K.slcanCode, '0');
      expect(CanBitrate.speed500K.slcanCode, '6');
      expect(CanBitrate.speed1M.slcanCode, '8');
      expect(CanBitrate.speed83K.slcanCode, '9');
    });

    test('label 非空', () {
      for (final b in CanBitrate.values) {
        expect(b.label, isNotEmpty);
      }
    });
  });

  group('CanFrame SLCAN 编码', () {
    test('标准数据帧编码正确', () {
      final frame = CanFrame(
        id: 0x123,
        extended: false,
        remote: false,
        data: Uint8List.fromList([0x11, 0x22, 0x33]),
      );
      expect(frame.toSlcanCommand(), 't1233112233\r');
    });

    test('扩展数据帧编码正确', () {
      final frame = CanFrame(
        id: 0x1A2B3C4D,
        extended: true,
        remote: false,
        data: Uint8List.fromList([0xAA, 0xBB]),
      );
      expect(frame.toSlcanCommand(), 'T1A2B3C4D2AABB\r');
    });

    test('标准远程帧编码正确（无数据）', () {
      final frame = CanFrame(
        id: 0x045,
        extended: false,
        remote: true,
        data: Uint8List(0),
      );
      expect(frame.toSlcanCommand(), 'r0450\r');
    });

    test('扩展远程帧编码正确', () {
      final frame = CanFrame(
        id: 0x18FEF100,
        extended: true,
        remote: true,
        data: Uint8List(0),
      );
      expect(frame.toSlcanCommand(), 'R18FEF1000\r');
    });

    test('零字节数据帧编码正确', () {
      final frame = CanFrame(
        id: 0x100,
        extended: false,
        remote: false,
        data: Uint8List(0),
      );
      expect(frame.toSlcanCommand(), 't1000\r');
    });

    test('8 字节数据帧编码正确', () {
      final frame = CanFrame(
        id: 0x7FF,
        extended: false,
        remote: false,
        data: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      );
      expect(frame.toSlcanCommand(), 't7FF80102030405060708\r');
    });

    test('ID 超范围抛出 RangeError', () {
      expect(
        () => CanFrame(id: 0x800, extended: false, remote: false, data: Uint8List(0)),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => CanFrame(id: 0x20000000, extended: true, remote: false, data: Uint8List(0)),
        throwsA(isA<RangeError>()),
      );
    });

    test('数据超过 8 字节抛出 RangeError', () {
      expect(
        () => CanFrame(
          id: 0x100,
          extended: false,
          remote: false,
          data: Uint8List(9),
        ),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('CanFrame SLCAN 解码', () {
    test('解析标准数据帧', () {
      final frame = CanFrame.fromSlcan('t1233112233');
      expect(frame, isNotNull);
      expect(frame!.id, 0x123);
      expect(frame.extended, isFalse);
      expect(frame.remote, isFalse);
      expect(frame.data, [0x11, 0x22, 0x33]);
    });

    test('解析扩展数据帧', () {
      final frame = CanFrame.fromSlcan('T1A2B3C4D2AABB');
      expect(frame, isNotNull);
      expect(frame!.id, 0x1A2B3C4D);
      expect(frame.extended, isTrue);
      expect(frame.remote, isFalse);
      expect(frame.data, [0xAA, 0xBB]);
    });

    test('解析标准远程帧', () {
      final frame = CanFrame.fromSlcan('r0458');
      expect(frame, isNotNull);
      expect(frame!.id, 0x045);
      expect(frame.extended, isFalse);
      expect(frame.remote, isTrue);
      expect(frame.data, isEmpty);
    });

    test('解析扩展远程帧', () {
      final frame = CanFrame.fromSlcan('R18FEF1000');
      expect(frame, isNotNull);
      expect(frame!.id, 0x18FEF100);
      expect(frame.extended, isTrue);
      expect(frame.remote, isTrue);
      expect(frame.data, isEmpty);
    });

    test('非帧行返回 null', () {
      expect(CanFrame.fromSlcan(''), isNull);
      expect(CanFrame.fromSlcan('z'), isNull);
      expect(CanFrame.fromSlcan('hello'), isNull);
    });

    test('长度不匹配返回 null', () {
      // 声明 DLC=3 但数据只有 2 字节
      expect(CanFrame.fromSlcan('t12331122'), isNull);
    });

    test('编码/解码往返一致', () {
      final original = CanFrame(
        id: 0x555,
        extended: false,
        remote: false,
        data: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
      );
      final command = original.toSlcanCommand();
      // 去掉结尾 \r 再解码
      final decoded = CanFrame.fromSlcan(command.substring(0, command.length - 1));
      expect(decoded, isNotNull);
      expect(decoded!.id, original.id);
      expect(decoded.extended, original.extended);
      expect(decoded.remote, original.remote);
      expect(decoded.data, original.data);
    });
  });

  group('CanSession', () {
    test('初始状态为未连接', () {
      final session = CanSession(
        id: 'test1',
        config: const CanConfig(portName: 'COM99'),
      );
      expect(session.isConnected, isFalse);
      expect(session.logs, isEmpty);
      expect(session.rxBytes, 0);
      expect(session.txBytes, 0);
      expect(session.frameId, isNonZero);
      expect(session.extended, isFalse);
      expect(session.remote, isFalse);
      session.dispose();
    });

    test('sendAsHex 默认为 true（CAN 数据为二进制）', () {
      final session = CanSession(
        id: 'test2',
        config: const CanConfig(portName: 'COM99'),
      );
      expect(session.sendAsHex, isTrue);
      session.dispose();
    });

    test('lineEnding 默认为 none（SLCAN 自带 CR）', () {
      final session = CanSession(
        id: 'test3',
        config: const CanConfig(portName: 'COM99'),
      );
      expect(session.lineEnding, LineEnding.none);
      session.dispose();
    });

    test('clearLogs 清空日志并归零计数', () {
      final session = CanSession(
        id: 'test4',
        config: const CanConfig(portName: 'COM99'),
      );
      session.clearLogs();
      expect(session.logs, isEmpty);
      expect(session.rxBytes, 0);
      expect(session.txBytes, 0);
      session.dispose();
    });

    test('updateConfig 在未连接时生效', () {
      final session = CanSession(
        id: 'test5',
        config: const CanConfig(portName: 'COM99'),
      );
      session.updateConfig(const CanConfig(
        portName: 'COM100',
        canBitrate: CanBitrate.speed250K,
      ));
      expect(session.config.portName, 'COM100');
      expect(session.config.canBitrate, CanBitrate.speed250K);
      session.dispose();
    });

    test('帧 ID 属性变更触发通知', () {
      final session = CanSession(
        id: 'test6',
        config: const CanConfig(portName: 'COM99'),
      );
      var notified = false;
      session.addListener(() => notified = true);
      session.frameId = 0x456;
      expect(notified, isTrue);
      expect(session.frameId, 0x456);
      session.dispose();
    });

    test('扩展帧/远程帧属性变更触发通知', () {
      final session = CanSession(
        id: 'test7',
        config: const CanConfig(portName: 'COM99'),
      );
      var notifyCount = 0;
      session.addListener(() => notifyCount++);
      session.extended = true;
      session.remote = true;
      expect(notifyCount, 2);
      expect(session.extended, isTrue);
      expect(session.remote, isTrue);
      session.dispose();
    });

    test('未连接时 sendContent 抛出 StateError', () {
      final session = CanSession(
        id: 'test8',
        config: const CanConfig(portName: 'COM99'),
      );
      expect(
        () => session.sendContent('11 22', asHex: true),
        throwsA(isA<StateError>()),
      );
      session.dispose();
    });

    test('未连接时 startLoopSend 不启动循环', () {
      final session = CanSession(
        id: 'test9',
        config: const CanConfig(portName: 'COM99'),
      );
      session.startLoopSend('11 22');
      expect(session.loopSending, isFalse);
      session.dispose();
    });
  });

  group('CanFrame sourceTag', () {
    test('标准帧 ID 标签为 3 位 hex', () {
      final frame = CanFrame(
        id: 0x5,
        extended: false,
        remote: false,
        data: Uint8List(0),
      );
      expect(frame.sourceTag, 'ID:0x005');
    });

    test('扩展帧 ID 标签为 8 位 hex', () {
      final frame = CanFrame(
        id: 0x1A2B3C4D,
        extended: true,
        remote: false,
        data: Uint8List(0),
      );
      expect(frame.sourceTag, 'ID:0x1A2B3C4D');
    });
  });
}
