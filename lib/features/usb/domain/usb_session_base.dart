import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../../core/ui/line_ending.dart';
import '../../../core/ui/send_contracts.dart';
import '../../../core/util/data_format.dart';

export '../../../core/ui/debug_log_entry.dart' show friendlyError;

/// HID / 通用 USB 会话的公共基类。
///
/// 负责收发日志、字节统计、接收静默判帧（30ms 合并，与串口/BLE 一致）、
/// 发送编码与循环发送；子类只需实现 [open] / [close] / [writeBytes]。
abstract class UsbSessionBase extends ChangeNotifier
    implements SendPanelController {
  UsbSessionBase({required this.id, required this.title});

  static const int maxLogEntries = 5000;

  // --- 接收合并（静默判帧）---
  static const int rxSettleMs = 30;
  static const int rxMaxBatchBytes = 4096;
  static const int rxMaxWaitMs = 200;

  /// 会话唯一 ID。
  final String id;

  /// 设备显示名。
  String title;

  /// 成功发送后通知管理器记录历史。
  void Function(String content, bool asHex)? onSent;

  String? lastError;

  /// 设备是否已打开。
  @override
  bool get isConnected;

  /// 打开设备。
  Future<void> open();

  /// 关闭设备。
  Future<void> close();

  /// 向设备写入一帧数据（子类按 HID Report / Bulk 传输实现）。
  Future<void> writeBytes(Uint8List bytes);

  // --- 日志 / 统计 ---

  final List<DebugLogEntry> logs = [];
  int rxBytes = 0;
  int txBytes = 0;

  final List<int> _rxBuffer = [];
  int? _rxFirstAtMs;
  Timer? _rxFlushTimer;

  // --- 发送选项（实现 SendPanelController）---
  @override
  bool sendAsHex = true;
  @override
  LineEnding lineEnding = LineEnding.crLf;
  @override
  int loopIntervalMs = 1000;
  @override
  bool loopSending = false;
  Timer? _loopTimer;

  DateTime? openedAt;

  String get displayName => title;

  // --- 发送 ---

  @override
  void sendContent(String raw, {required bool asHex}) {
    sendAsHex = asHex;
    final bytes = _encode(raw, asHex);
    if (bytes.isEmpty) {
      throw const FormatException('发送内容为空');
    }
    if (!isConnected) {
      throw StateError('设备未打开');
    }
    unawaited(_writeAndLog(bytes, raw: raw));
  }

  @override
  void startLoopSend(String raw) {
    if (loopSending || !isConnected) return;
    final bytes = _encode(raw, sendAsHex);
    if (bytes.isEmpty) throw const FormatException('发送内容为空');

    loopSending = true;
    onSent?.call(raw, sendAsHex);
    _loopTimer = Timer.periodic(
      Duration(milliseconds: loopIntervalMs <= 0 ? 1000 : loopIntervalMs),
      (_) async {
        try {
          await _writeAndLog(bytes);
        } catch (_) {
          stopLoopSend();
        }
      },
    );
    notifyListeners();
  }

  @override
  void stopLoopSend() {
    _loopTimer?.cancel();
    _loopTimer = null;
    if (loopSending) {
      loopSending = false;
      notifyListeners();
    }
  }

  Uint8List _encode(String raw, bool asHex) {
    if (asHex) return DataFormat.hexToBytes(raw);
    return DataFormat.textToBytes(raw + lineEnding.suffix);
  }

  Future<void> _writeAndLog(Uint8List bytes, {String? raw}) async {
    if (!isConnected) {
      throw StateError('设备未打开');
    }
    await writeBytes(bytes);
    txBytes += bytes.length;
    _appendLog(DebugLogEntry.transmit(bytes, source: txSource));
    if (raw != null) onSent?.call(raw, sendAsHex);
    notifyListeners();
  }

  /// TX 日志来源标签（如 `OUT 0x02`），子类可覆盖。
  String? get txSource => null;

  // --- 接收 ---

  /// 子类收到原始字节后调用，进入静默判帧缓冲。
  void ingestReceived(Uint8List data) {
    if (data.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _rxFirstAtMs ??= now;
    _rxBuffer.addAll(data);

    final waited = now - _rxFirstAtMs!;
    if (_rxBuffer.length >= rxMaxBatchBytes || waited >= rxMaxWaitMs) {
      _flushRxBuffer();
    } else {
      _rxFlushTimer?.cancel();
      _rxFlushTimer =
          Timer(const Duration(milliseconds: rxSettleMs), _flushRxBuffer);
    }
  }

  void _flushRxBuffer() {
    _rxFlushTimer?.cancel();
    _rxFlushTimer = null;
    if (_rxBuffer.isEmpty) {
      _rxFirstAtMs = null;
      return;
    }
    final bytes = Uint8List.fromList(_rxBuffer);
    _rxBuffer.clear();
    _rxFirstAtMs = null;
    rxBytes += bytes.length;
    _appendLog(DebugLogEntry.receive(bytes, source: rxSource));
    notifyListeners();
  }

  /// RX 日志来源标签（如 `IN 0x81` / `FEATURE RID=01`），子类可覆盖。
  String? get rxSource => null;

  /// 设备异常断开的统一处理（幂等）。
  void markDisconnected(String reason) {
    if (!isConnected) return;
    stopLoopSend();
    _flushRxBuffer();
    lastError = reason;
    _appendLog(DebugLogEntry.system(reason));
    onDeviceLost();
    notifyListeners();
  }

  /// 子类感知设备丢失（释放底层句柄等），由 [markDisconnected] 触发。
  void onDeviceLost() {}

  // --- 日志 ---

  void appendReceiveLog(Uint8List data, {String? source}) {
    rxBytes += data.length;
    _appendLog(DebugLogEntry.receive(data, source: source));
    notifyListeners();
  }

  void appendTransmitLog(Uint8List data, {String? source}) {
    txBytes += data.length;
    _appendLog(DebugLogEntry.transmit(data, source: source));
    notifyListeners();
  }

  void appendSystemLog(String message) {
    _appendLog(DebugLogEntry.system(message));
    notifyListeners();
  }

  void _appendLog(DebugLogEntry entry) {
    logs.add(entry);
    if (logs.length > maxLogEntries) {
      logs.removeRange(0, logs.length - maxLogEntries);
    }
  }

  void clearLogs() {
    _rxFlushTimer?.cancel();
    _rxFlushTimer = null;
    _rxBuffer.clear();
    _rxFirstAtMs = null;
    logs.clear();
    rxBytes = 0;
    txBytes = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _rxFlushTimer?.cancel();
    super.dispose();
  }
}
