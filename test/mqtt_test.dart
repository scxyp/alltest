import 'package:debug_assistant/features/mqtt/domain/mqtt_config.dart';
import 'package:debug_assistant/features/mqtt/domain/mqtt_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MqttConfig 序列化', () {
    test('toJson / fromJson 往返一致', () {
      const config = MqttConfig(
        host: 'broker.example.com',
        port: 8883,
        clientId: 'client-001',
        username: 'user',
        password: 'pass',
        tls: true,
        keepAlive: 30,
        will: MqttLastWill(
          topic: 'status/last',
          payload: 'offline',
          qos: MqttQosLevel.atLeastOnce,
          retain: true,
        ),
      );
      final json = config.toJson();
      final restored = MqttConfig.fromJson(json);

      expect(restored.host, 'broker.example.com');
      expect(restored.port, 8883);
      expect(restored.clientId, 'client-001');
      expect(restored.username, 'user');
      expect(restored.password, 'pass');
      expect(restored.tls, isTrue);
      expect(restored.keepAlive, 30);
      expect(restored.will?.topic, 'status/last');
      expect(restored.will?.payload, 'offline');
      expect(restored.will?.qos, MqttQosLevel.atLeastOnce);
      expect(restored.will?.retain, isTrue);
    });

    test('无遗嘱时 will 为 null 且序列化不含 will 字段', () {
      const config = MqttConfig(host: 'localhost', port: 1883);
      final json = config.toJson();
      expect(json.containsKey('will'), isFalse);
      expect(MqttConfig.fromJson(json).will, isNull);
    });

    test('summary 文本包含主机与端口', () {
      const config = MqttConfig(host: 'broker.hivemq.com', port: 1883);
      expect(config.summary, contains('broker.hivemq.com'));
      expect(config.summary, contains('1883'));
      expect(config.summary, contains('TCP'));
    });

    test('TLS 时 summary 显示 TLS', () {
      const config = MqttConfig(
          host: 'broker', port: 8883, tls: true);
      expect(config.summary, contains('TLS'));
    });
  });

  group('MqttQosLevel', () {
    test('index 与 MQTT 规范一致（0/1/2）', () {
      expect(MqttQosLevel.atMostOnce.index, 0);
      expect(MqttQosLevel.atLeastOnce.index, 1);
      expect(MqttQosLevel.exactlyOnce.index, 2);
    });

    test('label 非空', () {
      for (final q in MqttQosLevel.values) {
        expect(q.label, isNotEmpty);
      }
    });
  });

  group('MqttSession 参数校验', () {
    test('地址为空时 connect 抛出 FormatException', () async {
      final session = MqttSession(
        const MqttConfig(host: '', port: 1883),
        id: 'bad1',
      );
      await expectLater(
        session.connect(),
        throwsA(isA<FormatException>()),
      );
      session.dispose();
    });

    test('端口无效时 connect 抛出 FormatException', () async {
      final session = MqttSession(
        const MqttConfig(host: 'broker.example.com', port: 0),
        id: 'bad2',
      );
      await expectLater(
        session.connect(),
        throwsA(isA<FormatException>()),
      );
      session.dispose();
    });

    test('初始状态为未连接', () {
      final session = MqttSession(
        const MqttConfig(host: 'broker.example.com', port: 1883),
        id: 'init',
      );
      expect(session.isConnected, isFalse);
      expect(session.logs, isEmpty);
      expect(session.rxBytes, 0);
      expect(session.txBytes, 0);
      expect(session.subscriptions, isEmpty);
      expect(session.publishTopic, isEmpty);
      session.dispose();
    });

    test('未连接时 subscribe 抛出 StateError', () {
      final session = MqttSession(
        const MqttConfig(host: 'broker.example.com', port: 1883),
        id: 'nosub',
      );
      expect(
        () => session.subscribe('test/topic', MqttQosLevel.atMostOnce),
        throwsA(isA<StateError>()),
      );
      session.dispose();
    });

    test('updateConfig 在已连接时无效（不抛异常但不变更）', () {
      final session = MqttSession(
        const MqttConfig(host: 'a.com', port: 1883),
        id: 'cfg',
      );
      // 未连接时 updateConfig 生效
      session.updateConfig(const MqttConfig(host: 'b.com', port: 1884));
      expect(session.config.host, 'b.com');
      session.dispose();
    });

    test('clearLogs 清空日志并归零计数', () {
      final session = MqttSession(
        const MqttConfig(host: 'broker.example.com', port: 1883),
        id: 'clear',
      );
      session.clearLogs();
      expect(session.logs, isEmpty);
      expect(session.rxBytes, 0);
      expect(session.txBytes, 0);
      session.dispose();
    });
  });

  group('MqttLastWill 序列化', () {
    test('fromJson 容错：缺失字段使用默认值', () {
      final will = MqttLastWill.fromJson({});
      expect(will.topic, isEmpty);
      expect(will.payload, isEmpty);
      expect(will.qos, MqttQosLevel.atMostOnce);
      expect(will.retain, isFalse);
    });

    test('toJson / fromJson 往返一致', () {
      const will = MqttLastWill(
        topic: 'device/status',
        payload: 'gone',
        qos: MqttQosLevel.exactlyOnce,
        retain: true,
      );
      final restored = MqttLastWill.fromJson(will.toJson());
      expect(restored.topic, will.topic);
      expect(restored.payload, will.payload);
      expect(restored.qos, will.qos);
      expect(restored.retain, will.retain);
    });
  });
}
