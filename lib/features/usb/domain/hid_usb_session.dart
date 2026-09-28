import 'dart:async';
import 'dart:typed_data';

import 'package:hid_tool/hid_tool.dart';

import 'usb_device_info.dart';
import 'usb_session_base.dart';

/// 一个 HID 设备对应一个会话：Output Report 发送、Input Report 接收、
/// Feature Report 读写与报告描述符查看。
class HidUsbSession extends UsbSessionBase {
  HidUsbSession({
    required super.id,
    required this.device,
    required super.title,
  });

  /// 枚举时得到的 HID 设备对象（hid_tool 支持同一对象反复 open/close）。
  final UsbDeviceInfo device;
  HidDevice get _hid => device.nativeDevice! as HidDevice;

  StreamSubscription<int>? _inputSub;
  bool _intentionalClose = false;

  /// 发送 Output Report 时使用的 Report ID（0 表示设备不使用 Report ID）。
  int reportId = 0;

  /// true 时走 hid_send_output_report（强制中断 OUT 端点），
  /// false 时走常规 hid_write。
  bool useInterruptOut = false;

  HidReportDescriptor? _descriptor;
  HidReportDescriptor? get descriptor => _descriptor;

  @override
  bool get isConnected => _hid.isOpen;

  @override
  String? get rxSource => 'HID IN';

  @override
  String? get txSource =>
      'HID OUT RID=${reportId.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  @override
  Future<void> open() async {
    if (_hid.isOpen) return;
    lastError = null;
    _intentionalClose = false;
    await _hid.open();
    openedAt = DateTime.now();
    _subscribeInput();
    appendSystemLog('已打开 HID 设备 ${device.displayName}');
  }

  void _subscribeInput() {
    _inputSub = _hid.inputStream().listen(
      (int byte) {
        // inputStream 逐字节产出；同一次 hid_read 的字节连续到达，
        // 经基类 30ms 静默判帧后按整帧上屏。
        ingestReceived(Uint8List.fromList([byte]));
      },
      onError: (Object e) {
        if (!_intentionalClose) {
          markDisconnected('HID 接收异常：${friendlyError(e)}');
        }
      },
      cancelOnError: true,
    );
  }

  @override
  Future<void> close() async {
    if (!_hid.isOpen && _inputSub == null) return;
    stopLoopSend();
    _intentionalClose = true;
    await _inputSub?.cancel();
    _inputSub = null;
    try {
      await _hid.close();
    } catch (_) {
      // 设备可能已拔出，忽略关闭异常。
    }
    appendSystemLog('已关闭 HID 设备');
  }

  @override
  void onDeviceLost() {
    _intentionalClose = true;
    unawaited(_inputSub?.cancel());
    _inputSub = null;
  }

  @override
  Future<void> writeBytes(Uint8List bytes) async {
    if (useInterruptOut) {
      await _hid.sendOutputReport(bytes, reportId: reportId);
    } else {
      await _hid.sendReport(bytes, reportId: reportId);
    }
  }

  /// 读取 Feature Report。返回的首字节为 Report ID。
  Future<Uint8List> readFeatureReport(
    int reportId, {
    int bufferSize = 1024,
  }) async {
    if (!isConnected) throw StateError('设备未打开');
    final data = await _hid.receiveFeatureReport(
      reportId,
      bufferSize: bufferSize,
    );
    appendReceiveLog(
      data,
      source:
          'FEATURE RID=${reportId.toRadixString(16).toUpperCase().padLeft(2, '0')}',
    );
    return data;
  }

  /// 写入 Feature Report（hidapi 自动前缀 Report ID）。
  Future<void> writeFeatureReport(Uint8List bytes, int reportId) async {
    if (!isConnected) throw StateError('设备未打开');
    await _hid.sendFeatureReport(bytes, reportId: reportId);
    final full = Uint8List(bytes.length + 1)
      ..[0] = reportId
      ..setAll(1, bytes);
    appendTransmitLog(
      full,
      source:
          'FEATURE RID=${reportId.toRadixString(16).toUpperCase().padLeft(2, '0')}',
    );
  }

  /// 读取并缓存报告描述符。
  Future<HidReportDescriptor> loadDescriptor() async {
    if (!isConnected) throw StateError('设备未打开');
    final descriptor = await _hid.getReportDescriptor();
    _descriptor = descriptor;
    appendSystemLog(
      '已读取报告描述符（${descriptor.rawBytes.length} 字节，'
      'Input ${descriptor.inputs.length} / Output ${descriptor.outputs.length} '
      '/ Feature ${descriptor.features.length}）',
    );
    return descriptor;
  }

  void setReportId(int value) {
    final clamped = value & 0xFF;
    if (clamped == reportId) return;
    reportId = clamped;
    notifyListeners();
  }

  void setUseInterruptOut(bool value) {
    if (value == useInterruptOut) return;
    useInterruptOut = value;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_inputSub?.cancel());
    super.dispose();
  }
}
