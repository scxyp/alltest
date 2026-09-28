import 'package:debug_assistant/core/ui/quick_command.dart';
import 'package:debug_assistant/features/usb/data/usb_store.dart';
import 'package:debug_assistant/features/usb/domain/usb_device_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UsbDeviceInfo', () {
    test('toJson / fromJson 往返', () {
      final device = UsbDeviceInfo(
        kind: UsbDeviceKind.hid,
        id: r'\\?\hid#vid_04d8&pid_fc00',
        vendorId: 0x04D8,
        productId: 0xFC00,
        manufacturer: 'Acme',
        product: 'Gadget',
        serial: 'SN-1',
        usagePage: 0x0001,
        usage: 0x0006,
      );
      final json = device.toJson();
      final restored = UsbDeviceInfo.fromJson(json);
      expect(restored.kind, UsbDeviceKind.hid);
      expect(restored.id, device.id);
      expect(restored.vendorId, 0x04D8);
      expect(restored.productId, 0xFC00);
      expect(restored.manufacturer, 'Acme');
      expect(restored.product, 'Gadget');
      expect(restored.serial, 'SN-1');
      expect(restored.usagePage, 0x0001);
      expect(restored.nativeDevice, isNull);
    });

    test('vidPidHex 固定四位大写', () {
      final device = UsbDeviceInfo(
        kind: UsbDeviceKind.raw,
        id: '1_3_4d8_fc00',
        vendorId: 0x04D8,
        productId: 0xFC00,
      );
      expect(device.vidPidHex, '04D8:FC00');
    });

    test('displayName 依次回退：产品名 → 厂商 → 序列号 → VID:PID', () {
      expect(
        UsbDeviceInfo(
            kind: UsbDeviceKind.hid,
            id: 'a',
            vendorId: 1,
            productId: 2,
            product: 'P')
            .displayName,
        'P',
      );
      expect(
        UsbDeviceInfo(
            kind: UsbDeviceKind.hid,
            id: 'b',
            vendorId: 1,
            productId: 2,
            manufacturer: 'M')
            .displayName,
        'M',
      );
      expect(
        UsbDeviceInfo(
            kind: UsbDeviceKind.hid,
            id: 'c',
            vendorId: 1,
            productId: 2,
            serial: 'S')
            .displayName,
        'S',
      );
      final fallback = UsbDeviceInfo(
        kind: UsbDeviceKind.raw,
        id: 'd',
        vendorId: 0x12,
        productId: 0xAB,
      );
      expect(fallback.displayName, 'USB 设备 0012:00AB');
    });

    test('按 kind + id 判等', () {
      final a = UsbDeviceInfo(
        kind: UsbDeviceKind.hid,
        id: 'same',
        vendorId: 1,
        productId: 2,
        product: 'A',
      );
      final b = UsbDeviceInfo(
        kind: UsbDeviceKind.hid,
        id: 'same',
        vendorId: 3,
        productId: 4,
        product: 'B',
      );
      final raw = UsbDeviceInfo(
        kind: UsbDeviceKind.raw,
        id: 'same',
        vendorId: 1,
        productId: 2,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == raw, isFalse);
    });

    test('subtitle 包含 VID:PID 与 UsagePage', () {
      final device = UsbDeviceInfo(
        kind: UsbDeviceKind.hid,
        id: 'e',
        vendorId: 0x04D8,
        productId: 0xFC00,
        manufacturer: 'Acme',
        serial: '123',
        usagePage: 0x0001,
      );
      final subtitle = device.subtitle;
      expect(subtitle, contains('04D8:FC00'));
      expect(subtitle, contains('Acme'));
      expect(subtitle, contains('SN:123'));
      expect(subtitle, contains('UsagePage:0x0001'));
    });
  });

  group('UsbStore', () {
    late UsbStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = await UsbStore.create();
    });

    test('快捷指令 round-trip', () async {
      final commands = [
        QuickCommand(id: 'cmd1', name: '指令一', content: '01 02', asHex: true),
        QuickCommand(id: 'cmd2', name: '指令二', content: 'Hello', asHex: false),
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
        SendHistoryItem(content: '01 02', asHex: true, time: DateTime.now()),
        SendHistoryItem(content: 'test', asHex: false, time: DateTime.now()),
      ];
      await store.saveSendHistory(history);
      final loaded = store.loadSendHistory();
      expect(loaded.length, 2);
      expect(loaded[0].content, '01 02');
      expect(loaded[0].asHex, isTrue);
    });

    test('上次设备 ID（HID / 通用 USB 分别持久化）', () async {
      expect(store.loadLastHidDeviceId(), isNull);
      expect(store.loadLastRawDeviceId(), isNull);
      await store.saveLastHidDeviceId('hid-path');
      await store.saveLastRawDeviceId('raw-id');
      expect(store.loadLastHidDeviceId(), 'hid-path');
      expect(store.loadLastRawDeviceId(), 'raw-id');
    });

    test('损坏的 JSON 返回空列表', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('usb_quick_commands', '{not json');
      expect(store.loadQuickCommands(), isEmpty);
    });
  });
}
