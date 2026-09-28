import 'package:hid_tool/hid_tool.dart';

import '../data/raw_usb_service.dart';

/// USB 设备类型：HID 设备或通用 USB（libusb 裸传输）设备。
enum UsbDeviceKind {
  hid('HID'),
  raw('通用');

  const UsbDeviceKind(this.label);

  final String label;
}

/// 统一的 USB 设备展示模型，屏蔽 HID / libusb 两套枚举结果的差异。
class UsbDeviceInfo {
  UsbDeviceInfo({
    required this.kind,
    required this.id,
    required this.vendorId,
    required this.productId,
    this.manufacturer,
    this.product,
    this.serial,
    this.usagePage,
    this.usage,
    this.nativeDevice,
  });

  /// 从 hid_tool 枚举结果构造。
  factory UsbDeviceInfo.fromHid(HidDevice device) {
    return UsbDeviceInfo(
      kind: UsbDeviceKind.hid,
      id: device.path,
      vendorId: device.vendorId,
      productId: device.productId,
      manufacturer: device.manufacturer,
      product: device.productName,
      serial: device.serialNumber,
      usagePage: device.usagePage,
      usage: device.usage,
      nativeDevice: device,
    );
  }

  /// 从自研 libusb 枚举结果构造。
  factory UsbDeviceInfo.fromRaw(RawUsbDevice device) {
    return UsbDeviceInfo(
      kind: UsbDeviceKind.raw,
      id: device.id,
      vendorId: device.vendorId,
      productId: device.productId,
      manufacturer: device.manufacturer,
      product: device.product,
      serial: device.serial,
      nativeDevice: device,
    );
  }

  final UsbDeviceKind kind;

  /// 设备唯一标识：HID 用设备路径，raw 用 `总线-地址-VID-PID`。
  final String id;

  final int vendorId;
  final int productId;
  final String? manufacturer;
  final String? product;
  final String? serial;

  /// HID 设备的 UsagePage / Usage（raw 设备为 null）。
  final int? usagePage;
  final int? usage;

  /// 底层原生设备对象（HidDevice / RawUsbDevice），不参与序列化与判等。
  final Object? nativeDevice;

  /// 形如 `04D8:FC00` 的 VID:PID 文本。
  String get vidPidHex {
    String h4(int v) =>
        v.toRadixString(16).toUpperCase().padLeft(4, '0');
    return '${h4(vendorId)}:${h4(productId)}';
  }

  /// UI 显示名：产品名 → 厂商名 → 序列号 → VID:PID。
  String get displayName {
    if (product != null && product!.isNotEmpty) return product!;
    if (manufacturer != null && manufacturer!.isNotEmpty) return manufacturer!;
    if (serial != null && serial!.isNotEmpty) return serial!;
    return 'USB 设备 $vidPidHex';
  }

  /// HID UsagePage 的 16 进制展示（如 `0001`）。
  String? get usagePageHex =>
      usagePage?.toRadixString(16).toUpperCase().padLeft(4, '0');

  /// 副标题文本：VID:PID + 厂商 / 序列号信息。
  String get subtitle {
    final parts = <String>[vidPidHex];
    if (manufacturer != null && manufacturer!.isNotEmpty) {
      parts.add(manufacturer!);
    }
    if (serial != null && serial!.isNotEmpty) parts.add('SN:${serial!}');
    if (kind == UsbDeviceKind.hid && usagePage != null && usagePage != 0) {
      parts.add('UsagePage:0x$usagePageHex');
    }
    return parts.join('  ');
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'id': id,
        'vendorId': vendorId,
        'productId': productId,
        'manufacturer': manufacturer,
        'product': product,
        'serial': serial,
        'usagePage': usagePage,
        'usage': usage,
      };

  factory UsbDeviceInfo.fromJson(Map<String, Object?> json) {
    return UsbDeviceInfo(
      kind: UsbDeviceKind.values.byName(json['kind'] as String? ?? 'hid'),
      id: json['id'] as String,
      vendorId: json['vendorId'] as int? ?? 0,
      productId: json['productId'] as int? ?? 0,
      manufacturer: json['manufacturer'] as String?,
      product: json['product'] as String?,
      serial: json['serial'] as String?,
      usagePage: json['usagePage'] as int?,
      usage: json['usage'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UsbDeviceInfo && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}
