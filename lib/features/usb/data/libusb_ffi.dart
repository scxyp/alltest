import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ============================================================================
// libusb-1.0 的精简 dart:ffi 绑定
//
// 仅绑定通用 USB 调试所需的十余个函数（枚举 / 打开 / 配置描述符 /
// claim / bulk 传输 / 字符串描述符）。libusb 的 C ABI 自 1.0.9 起保持
// 稳定，随程序分发的 libusb-1.0.dll（1.0.23, x64）可直接使用。
//
// 所有调用均在独立的 worker isolate 中执行（见 raw_usb_service.dart），
// 避免 bulk 传输超时阻塞 UI 线程。
// ============================================================================

/// libusb 上下文（不透明）。
final class LibUsbContext extends Opaque {}

/// libusb 设备（不透明）。
final class LibUsbDevice extends Opaque {}

/// 已打开的设备句柄（不透明）。
final class LibUsbDeviceHandle extends Opaque {}

/// 对应 C 结构体 `struct libusb_device_descriptor`（14 字节）。
final class LibUsbDeviceDescriptor extends Struct {
  @Uint8()
  external int bLength;
  @Uint8()
  external int bDescriptorType;
  @Uint16()
  external int bcdUsb;
  @Uint16()
  external int idVendor;
  @Uint16()
  external int idProduct;
  @Uint16()
  external int bcdDevice;
  @Uint8()
  external int iManufacturer;
  @Uint8()
  external int iProduct;
  @Uint8()
  external int iSerialNumber;
  @Uint8()
  external int bNumConfigurations;
}

/// 对应 `struct libusb_endpoint_descriptor`。
final class LibUsbEndpointDescriptor extends Struct {
  @Uint8()
  external int bLength;
  @Uint8()
  external int bDescriptorType;
  @Uint8()
  external int bEndpointAddress;
  @Uint8()
  external int bmAttributes;
  @Uint16()
  external int wMaxPacketSize;
  @Uint8()
  external int bInterval;
  @Uint8()
  external int bRefresh;
  @Uint8()
  external int bSynchAddress;
  external Pointer<Uint8> extra;
  @Int32()
  external int extraLength;
}

/// 对应 `struct libusb_interface_descriptor`（只声明前导公共字段，
/// 结构体由 libusb 内部分配，Dart 侧不负责其大小）。
final class LibUsbInterfaceDescriptor extends Struct {
  @Uint8()
  external int bLength;
  @Uint8()
  external int bDescriptorType;
  @Uint8()
  external int bInterfaceNumber;
  @Uint8()
  external int bAlternateSetting;
  @Uint8()
  external int bNumEndpoints;
  @Uint8()
  external int bInterfaceClass;
  @Uint8()
  external int bInterfaceSubClass;
  @Uint8()
  external int bInterfaceProtocol;
  @Uint8()
  external int iInterface;
  external Pointer<LibUsbEndpointDescriptor> endpoint;
  external Pointer<Uint8> extra;
  @Int32()
  external int extraLength;
}

/// 对应 `struct libusb_interface`。
final class LibUsbInterface extends Struct {
  external Pointer<LibUsbInterfaceDescriptor> altsetting;
  @Int32()
  external int numAltsetting;
}

/// 对应 `struct libusb_config_descriptor`。
final class LibUsbConfigDescriptor extends Struct {
  @Uint8()
  external int bLength;
  @Uint8()
  external int bDescriptorType;
  @Uint16()
  external int wTotalLength;
  @Uint8()
  external int bNumInterfaces;
  @Uint8()
  external int bConfigurationValue;
  @Uint8()
  external int iConfiguration;
  @Uint8()
  external int bmAttributes;
  @Uint8()
  external int maxPower;
  external Pointer<LibUsbInterface> interface;
  external Pointer<Uint8> extra;
  @Int32()
  external int extraLength;
}

/// libusb 原生函数绑定。
class LibUsbBindings {
  LibUsbBindings._(this._lib);

  final DynamicLibrary _lib;

  /// 从可执行文件同目录加载 libusb-1.0.dll。
  factory LibUsbBindings.open() {
    final lib = DynamicLibrary.open('libusb-1.0.dll');
    return LibUsbBindings._(lib);
  }

  late final init = _lib.lookupFunction<
      Int32 Function(Pointer<Pointer<LibUsbContext>>),
      int Function(Pointer<Pointer<LibUsbContext>>)>('libusb_init');

  late final exit = _lib.lookupFunction<
      Void Function(Pointer<LibUsbContext>),
      void Function(Pointer<LibUsbContext>)>('libusb_exit');

  /// 返回 ssize_t（64 位 Windows 为 Int64，用 IntPtr 对应）。
  late final getDeviceList = _lib.lookupFunction<
      IntPtr Function(Pointer<LibUsbContext>,
          Pointer<Pointer<Pointer<LibUsbDevice>>>),
      int Function(Pointer<LibUsbContext>,
          Pointer<Pointer<Pointer<LibUsbDevice>>>)>('libusb_get_device_list');

  late final freeDeviceList = _lib.lookupFunction<
      Void Function(Pointer<Pointer<LibUsbDevice>>, Int32),
      void Function(Pointer<Pointer<LibUsbDevice>>,
          int)>('libusb_free_device_list');

  late final refDevice = _lib.lookupFunction<
      Pointer<LibUsbDevice> Function(Pointer<LibUsbDevice>),
      Pointer<LibUsbDevice> Function(Pointer<LibUsbDevice>)>(
      'libusb_ref_device');

  late final unrefDevice = _lib.lookupFunction<
      Void Function(Pointer<LibUsbDevice>),
      void Function(Pointer<LibUsbDevice>)>('libusb_unref_device');

  late final getBusNumber = _lib.lookupFunction<
      Uint8 Function(Pointer<LibUsbDevice>),
      int Function(Pointer<LibUsbDevice>)>('libusb_get_bus_number');

  late final getDeviceAddress = _lib.lookupFunction<
      Uint8 Function(Pointer<LibUsbDevice>),
      int Function(Pointer<LibUsbDevice>)>('libusb_get_device_address');

  late final getDeviceDescriptor = _lib.lookupFunction<
      Int32 Function(Pointer<LibUsbDevice>, Pointer<LibUsbDeviceDescriptor>),
      int Function(Pointer<LibUsbDevice>,
          Pointer<LibUsbDeviceDescriptor>)>('libusb_get_device_descriptor');

  late final getConfigDescriptor = _lib.lookupFunction<
      Int32 Function(Pointer<LibUsbDevice>, Uint8,
          Pointer<Pointer<LibUsbConfigDescriptor>>),
      int Function(Pointer<LibUsbDevice>, int,
          Pointer<Pointer<LibUsbConfigDescriptor>>)>('libusb_get_config_descriptor');

  late final freeConfigDescriptor = _lib.lookupFunction<
      Void Function(Pointer<LibUsbConfigDescriptor>),
      void Function(Pointer<LibUsbConfigDescriptor>)>(
      'libusb_free_config_descriptor');

  late final openDevice = _lib.lookupFunction<
      Int32 Function(Pointer<LibUsbDevice>,
          Pointer<Pointer<LibUsbDeviceHandle>>),
      int Function(Pointer<LibUsbDevice>,
          Pointer<Pointer<LibUsbDeviceHandle>>)>('libusb_open');

  late final closeDevice = _lib.lookupFunction<
      Void Function(Pointer<LibUsbDeviceHandle>),
      void Function(Pointer<LibUsbDeviceHandle>)>('libusb_close');

  late final getStringDescriptorAscii = _lib.lookupFunction<
      Int32 Function(Pointer<LibUsbDeviceHandle>, Uint8, Pointer<Uint8>, Int32),
      int Function(Pointer<LibUsbDeviceHandle>, int, Pointer<Uint8>,
          int)>('libusb_get_string_descriptor_ascii');

  late final claimInterface = _lib.lookupFunction<
      Int32 Function(Pointer<LibUsbDeviceHandle>, Int32),
      int Function(Pointer<LibUsbDeviceHandle>, int)>('libusb_claim_interface');

  late final releaseInterface = _lib.lookupFunction<
      Int32 Function(Pointer<LibUsbDeviceHandle>, Int32),
      int Function(Pointer<LibUsbDeviceHandle>, int)>('libusb_release_interface');

  late final bulkTransfer = _lib.lookupFunction<
      Int32 Function(Pointer<LibUsbDeviceHandle>, Uint8, Pointer<Uint8>, Int32,
          Pointer<Int32>, Uint32),
      int Function(Pointer<LibUsbDeviceHandle>, int, Pointer<Uint8>, int,
          Pointer<Int32>, int)>('libusb_bulk_transfer');

  late final strerror = _lib.lookupFunction<
      Pointer<Utf8> Function(Int32),
      Pointer<Utf8> Function(int)>('libusb_strerror');

  /// 端点方向：IN（设备到主机）。
  static const int endpointIn = 0x80;

  /// bmAttributes 低 2 位：传输类型。
  static const int transferControl = 0;
  static const int transferIsochronous = 1;
  static const int transferBulk = 2;
  static const int transferInterrupt = 3;

  /// 将 libusb 负错误码转换为可读中文说明。
  String errorText(int code) {
    final name = switch (code) {
      -1 => 'LIBUSB_ERROR_IO（输入输出错误）',
      -2 => 'LIBUSB_ERROR_INVALID_PARAM（参数无效）',
      -3 => 'LIBUSB_ERROR_ACCESS（访问被拒绝，可能被占用或权限不足）',
      -4 => 'LIBUSB_ERROR_NO_DEVICE（设备已断开）',
      -5 => 'LIBUSB_ERROR_NOT_FOUND（未找到）',
      -6 => 'LIBUSB_ERROR_BUSY（设备忙）',
      -7 => 'LIBUSB_ERROR_TIMEOUT（传输超时，无数据）',
      -9 => 'LIBUSB_ERROR_PIPE（端点停止）',
      -10 => 'LIBUSB_ERROR_INTERRUPTED（调用被中断）',
      -11 => 'LIBUSB_ERROR_NO_MEM（内存不足）',
      -12 => 'LIBUSB_ERROR_NOT_SUPPORTED（操作不被支持）',
      _ => 'LIBUSB_ERROR($code)',
    };
    final detail = strerror(code).toDartString();
    return detail.isEmpty ? name : '$name：$detail';
  }
}
