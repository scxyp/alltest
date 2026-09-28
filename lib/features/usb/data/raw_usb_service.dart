import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'libusb_ffi.dart';

// ============================================================================
// 通用 USB 服务：在独立 worker isolate 中调用 libusb。
//
// libusb 的 bulk 传输是阻塞式同步调用，直接在 UI isolate 中执行会导致
// 界面卡顿，因此所有原生调用都通过消息派发给常驻 worker isolate。
// 设备指针以地址整数（int）形式跨 isolate 传递（同一进程地址空间，
// 且枚举结果均通过 libusb_ref_device 保持引用有效）。
// ============================================================================

/// 枚举到的原始 USB 设备（描述符信息，未打开）。
class RawUsbDevice {
  RawUsbDevice({
    required this.pointer,
    required this.bus,
    required this.address,
    required this.vendorId,
    required this.productId,
    this.manufacturer,
    this.product,
    this.serial,
  });

  /// worker isolate 内 `libusb_device*` 的地址。
  final int pointer;
  final int bus;
  final int address;
  final int vendorId;
  final int productId;
  final String? manufacturer;
  final String? product;
  final String? serial;

  /// 稳定标识（同一枚举周期内唯一）。
  String get id =>
      '${bus}_${address}_${vendorId.toRadixString(16)}_${productId.toRadixString(16)}';
}

/// USB 接口描述信息。
class RawInterfaceInfo {
  RawInterfaceInfo({required this.number, required this.endpoints});

  final int number;
  final List<RawEndpointInfo> endpoints;
}

/// USB 端点描述信息。
class RawEndpointInfo {
  RawEndpointInfo({
    required this.interfaceNumber,
    required this.address,
    required this.attributes,
    required this.maxPacketSize,
  });

  final int interfaceNumber;

  /// 端点地址（含方向位，如 0x81）。
  final int address;

  /// bmAttributes（低 2 位为传输类型）。
  final int attributes;
  final int maxPacketSize;

  bool get isIn => (address & LibUsbBindings.endpointIn) != 0;

  String get addressHex =>
      '0x${address.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  /// 传输类型名称（控制 / 同步 / 批量 / 中断）。
  String get transferTypeLabel {
    switch (attributes & 0x03) {
      case LibUsbBindings.transferBulk:
        return '批量';
      case LibUsbBindings.transferInterrupt:
        return '中断';
      case LibUsbBindings.transferIsochronous:
        return '同步';
      default:
        return '控制';
    }
  }
}

/// 通用 USB 服务单例。
class RawUsbService {
  RawUsbService._();

  static final RawUsbService instance = RawUsbService._();

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _workerPort;
  final Map<int, Completer<Object?>> _pending = {};
  int _seq = 0;
  Future<void>? _starting;

  bool get isRunning => _workerPort != null;

  /// 启动 worker（幂等）。
  Future<void> ensureStarted() {
    if (_workerPort != null) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    _isolate = await Isolate.spawn(_workerMain, receivePort.sendPort);
    final workerCompleter = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        workerCompleter.complete(message);
        return;
      }
      if (message is Map) {
        final id = message['id'] as int;
        final completer = _pending.remove(id);
        if (completer == null) return;
        if (message['ok'] == true) {
          completer.complete(message['result']);
        } else {
          completer.completeError(
            StateError(message['error'] as String? ?? '未知 USB 错误'),
          );
        }
      }
    });
    _workerPort = await workerCompleter.future;
  }

  Future<T> _call<T>(String cmd, [Map<String, Object?> args = const {}]) async {
    await ensureStarted();
    final id = ++_seq;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _workerPort!.send(<String, Object?>{'id': id, 'cmd': cmd, ...args});
    return await completer.future as T;
  }

  /// 枚举设备。[fetchStrings] 为 false 时跳过需要临时打开设备的
  /// 厂商 / 产品 / 序列号读取（用于低成本的后台轮询）。
  Future<List<RawUsbDevice>> enumerate({bool fetchStrings = true}) async {
    final result = await _call<List<Object?>>(
      'enumerate',
      {'strings': fetchStrings},
    );
    return result
        .cast<Map>()
        .map((m) => RawUsbDevice(
              pointer: m['ptr'] as int,
              bus: m['bus'] as int,
              address: m['addr'] as int,
              vendorId: m['vid'] as int,
              productId: m['pid'] as int,
              manufacturer: m['manufacturer'] as String?,
              product: m['product'] as String?,
              serial: m['serial'] as String?,
            ))
        .toList();
  }

  /// 打开设备，返回设备句柄地址。
  Future<int> openDevice(RawUsbDevice device) =>
      _call<int>('open', {'ptr': device.pointer});

  /// 关闭设备并释放会话持有的设备引用。
  Future<void> closeDevice({
    required int handle,
    required int devicePointer,
  }) =>
      _call('close', {'handle': handle, 'ptr': devicePointer});

  /// 读取配置 0 的全部接口与端点。
  Future<List<RawInterfaceInfo>> getInterfaces(RawUsbDevice device) async {
    final result = await _call<List<Object?>>(
      'interfaces',
      {'ptr': device.pointer},
    );
    return result.cast<Map>().map((im) {
      final endpoints = (im['endpoints'] as List<Object?>).cast<Map>().map((em) {
        return RawEndpointInfo(
          interfaceNumber: im['number'] as int,
          address: em['address'] as int,
          attributes: em['attributes'] as int,
          maxPacketSize: em['maxPacketSize'] as int,
        );
      }).toList();
      return RawInterfaceInfo(number: im['number'] as int, endpoints: endpoints);
    }).toList();
  }

  Future<void> claimInterface(int handle, int interfaceNumber) =>
      _call('claim', {'handle': handle, 'iface': interfaceNumber});

  Future<void> releaseInterface(int handle, int interfaceNumber) =>
      _call('release', {'handle': handle, 'iface': interfaceNumber});

  /// Bulk IN 传输。超时无数据时返回空字节数组（不视为错误）。
  Future<Uint8List> bulkIn(
    int handle,
    int endpoint,
    int length,
    int timeoutMs,
  ) async {
    final result = await _call<Uint8List>('bulkIn', {
      'handle': handle,
      'ep': endpoint,
      'len': length,
      'timeout': timeoutMs,
    });
    return result;
  }

  /// Bulk OUT 传输，返回实际发送字节数。
  Future<int> bulkOut(
    int handle,
    int endpoint,
    Uint8List data,
    int timeoutMs,
  ) =>
      _call<int>('bulkOut', {
        'handle': handle,
        'ep': endpoint,
        'data': data,
        'timeout': timeoutMs,
      });

  /// 关闭 worker（应用退出时调用）。
  Future<void> dispose() async {
    if (_workerPort != null) {
      try {
        await _call('exit').timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    _isolate?.kill();
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _workerPort = null;
    _starting = null;
  }

  // ------------------------------------------------------------------------
  // worker isolate
  // ------------------------------------------------------------------------

  static Future<void> _workerMain(SendPort mainPort) async {
    final receivePort = ReceivePort();
    mainPort.send(receivePort.sendPort);

    final lib = LibUsbBindings.open();
    // 使用默认上下文（传 nullptr 作为出参，由库内部创建）。
    final ctxOut = calloc<Pointer<LibUsbContext>>();
    final initResult = lib.init(ctxOut);
    if (initResult != 0) {
      mainPort.send({
        'id': -1,
        'ok': false,
        'error': 'libusb 初始化失败：${lib.errorText(initResult)}',
      });
      calloc.free(ctxOut);
      return;
    }
    calloc.free(ctxOut);

    /// 当前通过枚举交给主 isolate 持有的设备引用（地址集合）。
    final heldRefs = <int>{};

    /// 已被会话打开的设备地址（重新枚举时不释放其引用）。
    final openedDevices = <int>{};

    await for (final message in receivePort) {
      final request = message as Map;
      final id = request['id'] as int;
      if (id == -1) continue;
      Object? result;
      String? error;
      try {
        result = await _dispatch(lib, request, heldRefs, openedDevices);
      } catch (e) {
        error = '$e';
      }
      mainPort.send({'id': id, 'ok': error == null, 'result': result, 'error': error});
      if (request['cmd'] == 'exit') break;
    }

    // 退出前释放所有设备引用并销毁默认上下文。
    for (final address in heldRefs) {
      lib.unrefDevice(Pointer<LibUsbDevice>.fromAddress(address));
    }
    heldRefs.clear();
    lib.exit(nullptr);
    Isolate.exit();
  }

  static Future<Object?> _dispatch(
    LibUsbBindings lib,
    Map request,
    Set<int> heldRefs,
    Set<int> openedDevices,
  ) async {
    switch (request['cmd']) {
      case 'exit':
        return null;

      case 'enumerate':
        return _enumerate(
          lib,
          heldRefs,
          openedDevices,
          fetchStrings: request['strings'] as bool? ?? true,
        );

      case 'open':
        final ptr = request['ptr'] as int;
        final device = Pointer<LibUsbDevice>.fromAddress(ptr);
        final handleOut = calloc<Pointer<LibUsbDeviceHandle>>();
        try {
          final rc = lib.openDevice(device, handleOut);
          if (rc != 0) {
            throw StateError('打开 USB 设备失败：${lib.errorText(rc)}');
          }
          openedDevices.add(ptr);
          return handleOut.value.address;
        } finally {
          calloc.free(handleOut);
        }

      case 'close':
        final handle = Pointer<LibUsbDeviceHandle>.fromAddress(
          request['handle'] as int,
        );
        final ptr = request['ptr'] as int;
        // 释放接口失败不影响关闭流程。
        lib.closeDevice(handle);
        openedDevices.remove(ptr);
        if (heldRefs.remove(ptr)) {
          lib.unrefDevice(Pointer<LibUsbDevice>.fromAddress(ptr));
        }
        return null;

      case 'interfaces':
        return _readInterfaces(lib, request['ptr'] as int);

      case 'claim':
        final rc = lib.claimInterface(
          Pointer<LibUsbDeviceHandle>.fromAddress(request['handle'] as int),
          request['iface'] as int,
        );
        if (rc != 0) throw StateError('认领接口失败：${lib.errorText(rc)}');
        return null;

      case 'release':
        lib.releaseInterface(
          Pointer<LibUsbDeviceHandle>.fromAddress(request['handle'] as int),
          request['iface'] as int,
        );
        return null;

      case 'bulkIn':
        return _bulkIn(lib, request);

      case 'bulkOut':
        return _bulkOut(lib, request);

      default:
        throw StateError('未知的 USB 命令：${request['cmd']}');
    }
  }

  static List<Map<String, Object?>> _enumerate(
    LibUsbBindings lib,
    Set<int> heldRefs,
    Set<int> openedDevices, {
    required bool fetchStrings,
  }) {
    // 释放上一轮枚举的引用（仍被会话占用的除外）。
    final stale = heldRefs.where((p) => !openedDevices.contains(p)).toList();
    for (final address in stale) {
      lib.unrefDevice(Pointer<LibUsbDevice>.fromAddress(address));
    }
    heldRefs.removeAll(stale);

    final listOut = calloc<Pointer<Pointer<LibUsbDevice>>>();
    final count = lib.getDeviceList(nullptr, listOut);
    if (count < 0) {
      calloc.free(listOut);
      throw StateError('枚举 USB 设备失败：${lib.errorText(count)}');
    }

    final devices = <Map<String, Object?>>[];
    final descriptor = calloc<LibUsbDeviceDescriptor>();
    try {
      final list = listOut.value;
      for (var i = 0; i < count; i++) {
        final device = list[i];

        String? manufacturer;
        String? product;
        String? serial;
        var vid = 0;
        var pid = 0;
        var bus = 0;
        var addr = 0;

        final rc = lib.getDeviceDescriptor(device, descriptor);
        if (rc == 0) {
          final d = descriptor.ref;
          vid = d.idVendor;
          pid = d.idProduct;
          bus = lib.getBusNumber(device);
          addr = lib.getDeviceAddress(device);

          if (fetchStrings) {
            final handleOut = calloc<Pointer<LibUsbDeviceHandle>>();
            if (lib.openDevice(device, handleOut) == 0) {
              final handle = handleOut.value;
              manufacturer = _readString(lib, handle, d.iManufacturer);
              product = _readString(lib, handle, d.iProduct);
              serial = _readString(lib, handle, d.iSerialNumber);
              lib.closeDevice(handle);
            }
            calloc.free(handleOut);
          }
        }

        // 额外持有一份引用，使其在 freeDeviceList 后仍有效。
        final kept = lib.refDevice(device);
        heldRefs.add(kept.address);
        devices.add({
          'ptr': kept.address,
          'bus': bus,
          'addr': addr,
          'vid': vid,
          'pid': pid,
          'manufacturer': manufacturer,
          'product': product,
          'serial': serial,
        });
      }
    } finally {
      lib.freeDeviceList(listOut.value, 1);
      calloc.free(descriptor);
      calloc.free(listOut);
    }
    return devices;
  }

  static String? _readString(
    LibUsbBindings lib,
    Pointer<LibUsbDeviceHandle> handle,
    int index,
  ) {
    if (index == 0) return null;
    const bufferSize = 256;
    final buffer = calloc<Uint8>(bufferSize);
    try {
      final length =
          lib.getStringDescriptorAscii(handle, index, buffer, bufferSize);
      if (length <= 0) return null;
      final bytes = buffer.asTypedList(length);
      final text = String.fromCharCodes(bytes).trim();
      return text.isEmpty ? null : text;
    } finally {
      calloc.free(buffer);
    }
  }

  static List<Map<String, Object?>> _readInterfaces(
    LibUsbBindings lib,
    int deviceAddress,
  ) {
    final configOut = calloc<Pointer<LibUsbConfigDescriptor>>();
    final rc = lib.getConfigDescriptor(
      Pointer<LibUsbDevice>.fromAddress(deviceAddress),
      0,
      configOut,
    );
    if (rc != 0) {
      calloc.free(configOut);
      throw StateError('读取配置描述符失败：${lib.errorText(rc)}');
    }

    final result = <Map<String, Object?>>[];
    try {
      final config = configOut.value.ref;
      for (var i = 0; i < config.bNumInterfaces; i++) {
        // 仅展示每个接口的 altsetting 0（Windows bulk 调试的常规形态）。
        final iface = config.interface[i].altsetting[0];
        final endpoints = <Map<String, Object?>>[];
        for (var e = 0; e < iface.bNumEndpoints; e++) {
          final ep = iface.endpoint[e];
          endpoints.add({
            'address': ep.bEndpointAddress,
            'attributes': ep.bmAttributes,
            'maxPacketSize': ep.wMaxPacketSize & 0x07FF,
          });
        }
        result.add({'number': iface.bInterfaceNumber, 'endpoints': endpoints});
      }
    } finally {
      lib.freeConfigDescriptor(configOut.value);
      calloc.free(configOut);
    }
    return result;
  }

  static Uint8List _bulkIn(LibUsbBindings lib, Map request) {
    final handle = Pointer<LibUsbDeviceHandle>.fromAddress(
      request['handle'] as int,
    );
    final length = request['len'] as int;
    if (length <= 0) return Uint8List(0);

    final buffer = calloc<Uint8>(length);
    final transferred = calloc<Int32>();
    try {
      final rc = lib.bulkTransfer(
        handle,
        request['ep'] as int,
        buffer,
        length,
        transferred,
        request['timeout'] as int,
      );
      // -7 为超时：轮询场景下属于正常情况，返回空数据。
      if (rc == -7) return Uint8List(0);
      if (rc != 0) throw StateError('Bulk IN 失败：${lib.errorText(rc)}');
      final count = transferred.value;
      return Uint8List.fromList(buffer.asTypedList(count));
    } finally {
      calloc.free(transferred);
      calloc.free(buffer);
    }
  }

  static int _bulkOut(LibUsbBindings lib, Map request) {
    final data = request['data'] as Uint8List;
    if (data.isEmpty) return 0;

    final handle = Pointer<LibUsbDeviceHandle>.fromAddress(
      request['handle'] as int,
    );
    final buffer = calloc<Uint8>(data.length);
    final transferred = calloc<Int32>();
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      final rc = lib.bulkTransfer(
        handle,
        request['ep'] as int,
        buffer,
        data.length,
        transferred,
        request['timeout'] as int,
      );
      if (rc != 0) throw StateError('Bulk OUT 失败：${lib.errorText(rc)}');
      return transferred.value;
    } finally {
      calloc.free(transferred);
      calloc.free(buffer);
    }
  }
}
