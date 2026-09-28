import 'package:debug_assistant/features/bluetooth/data/ble_store.dart';
import 'package:debug_assistant/features/bluetooth/domain/ble_device_info.dart';
import 'package:debug_assistant/core/ui/quick_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BleDeviceInfo', () {
    test('toJson / fromJson 往返', () {
      const device = BleDeviceInfo(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        name: 'TestDevice',
        rssi: -65,
      );
      final json = device.toJson();
      final restored = BleDeviceInfo.fromJson(json);
      expect(restored.deviceId, device.deviceId);
      expect(restored.name, device.name);
      expect(restored.rssi, device.rssi);
    });

    test('displayName 优先 name，否则退回 deviceId', () {
      expect(
        const BleDeviceInfo(deviceId: 'id1', name: 'MyBLE').displayName,
        'MyBLE',
      );
      expect(
        const BleDeviceInfo(deviceId: 'id2', name: null).displayName,
        'id2',
      );
      expect(
        const BleDeviceInfo(deviceId: 'id3', name: '').displayName,
        'id3',
      );
    });

    test('按 deviceId 判等', () {
      const a = BleDeviceInfo(deviceId: 'same', name: 'A', rssi: -50);
      const b = BleDeviceInfo(deviceId: 'same', name: 'B', rssi: -70);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith 仅覆盖传入字段', () {
      const original = BleDeviceInfo(
        deviceId: 'dev1',
        name: 'OldName',
        rssi: -60,
      );
      final updated = original.copyWith(name: 'NewName');
      expect(updated.deviceId, 'dev1');
      expect(updated.name, 'NewName');
      expect(updated.rssi, -60);
    });
  });

  group('BleStore', () {
    late BleStore store;

    setUp(() async {
      // SharedPreferences 需要 mock 初始值才能在测试中使用
      SharedPreferences.setMockInitialValues({});
      store = await BleStore.create();
    });

    test('快捷指令 round-trip', () async {
      final commands = [
        QuickCommand(
          id: 'cmd1',
          name: '指令一',
          content: 'AA BB',
          asHex: true,
        ),
        QuickCommand(
          id: 'cmd2',
          name: '指令二',
          content: 'Hello',
          asHex: false,
        ),
      ];
      await store.saveQuickCommands(commands);
      final loaded = store.loadQuickCommands();
      expect(loaded.length, 2);
      expect(loaded[0].name, '指令一');
      expect(loaded[0].asHex, isTrue);
      expect(loaded[1].content, 'Hello');
    });

    test('发送历史 round-trip', () async {
      final history = [
        SendHistoryItem(content: 'AA BB', asHex: true, time: DateTime.now()),
        SendHistoryItem(content: 'test', asHex: false, time: DateTime.now()),
      ];
      await store.saveSendHistory(history);
      final loaded = store.loadSendHistory();
      expect(loaded.length, 2);
      expect(loaded[0].content, 'AA BB');
      expect(loaded[0].asHex, isTrue);
      expect(loaded[1].content, 'test');
    });

    test('上次连接设备 ID round-trip', () async {
      await store.saveLastDeviceId('AA:BB:CC:DD:EE:FF');
      expect(store.loadLastDeviceId(), 'AA:BB:CC:DD:EE:FF');
    });

    test('空数据返回默认值', () {
      expect(store.loadQuickCommands(), isEmpty);
      expect(store.loadSendHistory(), isEmpty);
      expect(store.loadLastDeviceId(), isNull);
    });
  });
}
