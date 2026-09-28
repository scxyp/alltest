import 'dart:async';
import 'dart:typed_data';

import '../data/raw_usb_service.dart';
import 'usb_device_info.dart';
import 'usb_session_base.dart';

/// 一个通用 USB 设备（libusb 裸传输）对应一个会话：
/// 选择接口 / 端点 → claim → Bulk OUT 发送、Bulk IN 轮询接收。
class RawUsbSession extends UsbSessionBase {
  RawUsbSession({required super.id, required this.device})
      : super(title: device.displayName);

  /// 单次发送与手动读取的超时（毫秒）。
  static const int transferTimeoutMs = 1000;

  final UsbDeviceInfo device;
  final RawUsbService _service = RawUsbService.instance;

  RawUsbDevice get _raw => device.nativeDevice! as RawUsbDevice;

  int? _handle;
  bool _opened = false;

  /// 配置 0 下的全部接口与端点。
  List<RawInterfaceInfo> interfaces = const [];

  /// 当前已 claim 的接口号。
  int? claimedInterface;

  /// 发送 / 接收端点地址（如 0x02 / 0x81）。
  int? outEndpoint;
  int? inEndpoint;

  /// 是否正在连续接收。
  bool receiving = false;

  /// 单次 IN 传输申请的最大字节数。
  int readSize = 64;

  /// 连续轮询间隔（毫秒）。
  int pollIntervalMs = 10;

  /// 手动读取的超时时间（毫秒）。
  int readTimeoutMs = 100;

  Timer? _pollTimer;
  bool _pollInFlight = false;

  @override
  bool get isConnected => _opened;

  @override
  String? get txSource {
    final ep = outEndpoint;
    return ep == null ? 'BULK OUT' : 'BULK OUT ${_epHex(ep)}';
  }

  @override
  String? get rxSource {
    final ep = inEndpoint;
    return ep == null ? 'BULK IN' : 'BULK IN ${_epHex(ep)}';
  }

  static String _epHex(int address) =>
      '0x${address.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  // --- 打开 / 关闭 ---

  @override
  Future<void> open() async {
    if (_opened) return;
    lastError = null;

    final handle = await _service.openDevice(_raw);
    _handle = handle;
    try {
      interfaces = await _service.getInterfaces(_raw);
      await _autoSetup(handle);
      _opened = true;
      openedAt = DateTime.now();
      final epInfo = <String>[
        if (claimedInterface != null) '接口 $claimedInterface',
        if (outEndpoint != null) 'OUT ${_epHex(outEndpoint!)}',
        if (inEndpoint != null) 'IN ${_epHex(inEndpoint!)}',
      ];
      appendSystemLog('已打开 USB 设备（${epInfo.join('，')}）');
    } catch (e) {
      // 打开成功但后续配置失败：回收句柄，避免 worker 中残留。
      try {
        await _service.closeDevice(
          handle: handle,
          devicePointer: _raw.pointer,
        );
      } catch (_) {}
      _handle = null;
      rethrow;
    }
  }

  /// 自动选择第一个同时具备 Bulk OUT / IN 的接口并 claim。
  Future<void> _autoSetup(int handle) async {
    RawInterfaceInfo? preferred;
    for (final iface in interfaces) {
      final hasOut = iface.endpoints.any((e) =>
          !e.isIn && (e.attributes & 0x03) == RawEndpointType.bulk);
      final hasIn = iface.endpoints.any(
          (e) => e.isIn && (e.attributes & 0x03) == RawEndpointType.bulk);
      if (hasOut && hasIn) {
        preferred = iface;
        break;
      }
    }
    preferred ??= interfaces.isNotEmpty ? interfaces.first : null;
    if (preferred == null) return;

    await _service.claimInterface(handle, preferred.number);
    claimedInterface = preferred.number;
    final eps = preferred.endpoints;
    outEndpoint = _firstEndpoint(eps, isIn: false);
    inEndpoint = _firstEndpoint(eps, isIn: true);
  }

  /// 返回指定方向的第一个端点地址，没有则返回 null。
  int? _firstEndpoint(List<RawEndpointInfo> endpoints, {required bool isIn}) {
    for (final ep in endpoints) {
      if (ep.isIn == isIn) return ep.address;
    }
    return null;
  }

  @override
  Future<void> close() async {
    if (!_opened && _handle == null) return;
    stopReceiving();
    final handle = _handle;
    if (handle != null) {
      final iface = claimedInterface;
      if (iface != null) {
        try {
          await _service.releaseInterface(handle, iface);
        } catch (_) {}
      }
      try {
        await _service.closeDevice(
          handle: handle,
          devicePointer: _raw.pointer,
        );
      } catch (_) {}
    }
    _handle = null;
    _opened = false;
    claimedInterface = null;
    outEndpoint = null;
    inEndpoint = null;
    appendSystemLog('已关闭 USB 设备');
  }

  @override
  void onDeviceLost() {
    receiving = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _opened = false;
    _handle = null;
    claimedInterface = null;
  }

  // --- 接口 / 端点选择 ---

  /// 切换工作接口（自动 release 旧接口、claim 新接口）。
  Future<void> selectInterface(int interfaceNumber) async {
    if (!_opened) throw StateError('设备未打开');
    if (interfaceNumber == claimedInterface) return;
    if (receiving) stopReceiving();

    final handle = _handle!;
    final old = claimedInterface;
    if (old != null) {
      try {
        await _service.releaseInterface(handle, old);
      } catch (_) {}
    }
    await _service.claimInterface(handle, interfaceNumber);
    claimedInterface = interfaceNumber;
    final iface = interfaces.firstWhere(
      (i) => i.number == interfaceNumber,
      orElse: () => RawInterfaceInfo(number: interfaceNumber, endpoints: const []),
    );
    outEndpoint = _firstEndpoint(iface.endpoints, isIn: false);
    inEndpoint = _firstEndpoint(iface.endpoints, isIn: true);
    appendSystemLog('已切换到接口 $interfaceNumber');
    notifyListeners();
  }

  void selectOutEndpoint(int? address) {
    if (address == outEndpoint) return;
    outEndpoint = address;
    notifyListeners();
  }

  void selectInEndpoint(int? address) {
    if (address == inEndpoint) return;
    inEndpoint = address;
    notifyListeners();
  }

  RawEndpointInfo? findEndpoint(int address) {
    for (final iface in interfaces) {
      for (final ep in iface.endpoints) {
        if (ep.address == address) return ep;
      }
    }
    return null;
  }

  // --- 收发 ---

  @override
  Future<void> writeBytes(Uint8List bytes) async {
    final handle = _handle;
    final ep = outEndpoint;
    if (handle == null) throw StateError('设备未打开');
    if (ep == null) throw StateError('未选择 OUT 端点');
    await _service.bulkOut(handle, ep, bytes, transferTimeoutMs);
  }

  /// 开始按固定间隔连续 Bulk IN 轮询（每次传输零超时立即返回，
  /// 避免阻塞 worker，节奏由 [pollIntervalMs] 控制）。
  void startReceiving() {
    if (receiving || !_opened) return;
    if (inEndpoint == null) {
      throw StateError('未选择 IN 端点');
    }
    receiving = true;
    appendSystemLog('开始连续接收（每次 $readSize 字节，间隔 ${pollIntervalMs}ms）');
    _schedulePoll();
    notifyListeners();
  }

  void stopReceiving() {
    if (!receiving && _pollTimer == null) return;
    receiving = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    notifyListeners();
  }

  void _schedulePoll() {
    if (!receiving || !_opened) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(
      Duration(milliseconds: pollIntervalMs <= 0 ? 10 : pollIntervalMs),
      _pollTick,
    );
  }

  Future<void> _pollTick() async {
    if (!receiving || !_opened || _pollInFlight) {
      _schedulePoll();
      return;
    }
    final handle = _handle;
    final ep = inEndpoint;
    if (handle == null || ep == null) {
      stopReceiving();
      return;
    }
    _pollInFlight = true;
    try {
      final data =
          await _service.bulkIn(handle, ep, readSize, 0);
      if (data.isNotEmpty) ingestReceived(data);
    } catch (e) {
      receiving = false;
      _pollTimer?.cancel();
      _pollTimer = null;
      markDisconnected('Bulk IN 异常：${friendlyError(e)}');
      return;
    } finally {
      _pollInFlight = false;
    }
    _schedulePoll();
  }

  /// 手动读取一次（使用 [readTimeoutMs] 超时）。
  Future<void> readOnce() async {
    final handle = _handle;
    final ep = inEndpoint;
    if (handle == null) throw StateError('设备未打开');
    if (ep == null) throw StateError('未选择 IN 端点');
    final data =
        await _service.bulkIn(handle, ep, readSize, readTimeoutMs);
    if (data.isEmpty) {
      appendSystemLog('手动读取：超时无数据');
    } else {
      appendReceiveLog(data);
    }
  }

  // --- 参数更新（UI 调用）---

  void updatePollConfig({int? readSize, int? intervalMs, int? timeoutMs}) {
    if (readSize != null && readSize > 0) this.readSize = readSize;
    if (intervalMs != null && intervalMs > 0) pollIntervalMs = intervalMs;
    if (timeoutMs != null && timeoutMs >= 0) readTimeoutMs = timeoutMs;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// libusb 传输类型常量（bmAttributes 低 2 位）。
class RawEndpointType {
  static const int control = 0;
  static const int isochronous = 1;
  static const int bulk = 2;
  static const int interrupt = 3;
}
