import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../../core/ui/line_ending.dart';
import '../../../core/ui/send_contracts.dart';
import '../../../core/util/data_format.dart';
import '../data/serial_port_service.dart';
import 'serial_config.dart';

export '../../../core/ui/debug_log_entry.dart' show friendlyError;

enum SessionState { disconnected, connected }

/// 一个串口连接对应一个会话：持有连接、数据日志、收发统计与发送选项。
class SerialSession extends ChangeNotifier implements SendPanelController {
  SerialSession({required this.id, required SerialConfig config})
      // ignore: prefer_initializing_formals
      : _config = config;

  static const int maxLogEntries = 5000;

  // --- 接收合并（静默判帧）---
  /// 收到数据后静默 [rxSettleMs] 毫秒再上屏，避免一帧数据被拆成
  /// 一两个字符逐条显示。
  static const int rxSettleMs = 30;
  /// 单条记录的最大合并字节数（连续流式数据时按此上限切分）。
  static const int rxMaxBatchBytes = 4096;
  /// 连续不断的数据流最长合并等待，防止缓冲无限增长。
  static const int rxMaxWaitMs = 200;

  final String id;
  final SerialPortService _service = SerialPortService();

  /// 成功发送后通知管理器记录历史。
  void Function(String content, bool asHex)? onSent;

  SerialConfig _config;
  SerialConfig get config => _config;

  SessionState _state = SessionState.disconnected;
  SessionState get state => _state;
  @override
  bool get isConnected => _state == SessionState.connected;

  String? lastError;

  final List<DebugLogEntry> logs = [];
  int rxBytes = 0;
  int txBytes = 0;

  final List<int> _rxBuffer = [];
  int? _rxFirstAtMs;
  Timer? _rxFlushTimer;

  // --- 发送选项（实现 SendPanelController）---
  @override
  bool sendAsHex = false;
  @override
  LineEnding lineEnding = LineEnding.crLf;
  @override
  int loopIntervalMs = 1000;
  @override
  bool loopSending = false;
  Timer? _loopTimer;

  /// 会话建立时间（用于导出文件命名等）。
  DateTime? openedAt;

  /// 更新连接参数（仅在断开状态下允许）。
  void updateConfig(SerialConfig config) {
    if (isConnected) return;
    _config = config;
    notifyListeners();
  }

  Future<void> connect() async {
    if (isConnected) return;
    lastError = null;
    try {
      _service.open(
        _config,
        onData: _onDataReceived,
        onError: _onConnectionError,
      );
      _state = SessionState.connected;
      openedAt = DateTime.now();
      _appendLog(DebugLogEntry.system(
        '已连接 ${_config.portName}（${_config.summary}）',
      ));
      notifyListeners();
    } catch (e) {
      final message = friendlyError(e);
      lastError = message;
      _appendLog(DebugLogEntry.system(message));
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (!isConnected && !_service.isOpen) {
      _state = SessionState.disconnected;
      return;
    }
    stopLoopSend();
    _flushRxBuffer();
    await _service.close();
    _state = SessionState.disconnected;
    _appendLog(DebugLogEntry.system('已断开 ${_config.portName}'));
    notifyListeners();
  }

  // --- 发送 ---

  /// 按当前发送模式（HEX / 文本 + 行结束符）发送输入内容。
  @override
  void sendContent(String raw, {required bool asHex}) {
    sendAsHex = asHex;
    final bytes = _encode(raw, asHex);
    if (bytes.isEmpty) {
      throw const FormatException('发送内容为空');
    }
    _writeAndLog(bytes);
    onSent?.call(raw, asHex);
  }

  /// 开始按固定间隔循环发送当前输入内容。
  @override
  void startLoopSend(String raw) {
    if (loopSending || !isConnected) return;
    final bytes = _encode(raw, sendAsHex);
    if (bytes.isEmpty) throw const FormatException('发送内容为空');

    loopSending = true;
    onSent?.call(raw, sendAsHex);
    _loopTimer = Timer.periodic(
      Duration(milliseconds: loopIntervalMs <= 0 ? 1000 : loopIntervalMs),
      (_) {
        try {
          _writeAndLog(bytes);
        } catch (_) {
          // _writeAndLog 内部已标记断开并停止循环发送，这里兜底停止。
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

  void _writeAndLog(Uint8List bytes) {
    if (!isConnected) {
      throw StateError('串口未连接');
    }
    int written;
    try {
      written = _service.write(bytes);
    } catch (e) {
      // 写入失败基本意味着底层连接已失效（如设备被拔出），
      // 直接将会话标记为断开，避免状态栏一直显示"已连接"。
      final message = friendlyError(e);
      _markDisconnected('连接已断开：$message');
      throw StateError(message);
    }
    if (written <= 0) {
      throw StateError('写入失败：数据未发出');
    }
    txBytes += written;
    _appendLog(DebugLogEntry.transmit(bytes));
    notifyListeners();
  }

  // --- 接收 ---

  /// 原始数据先进入合并缓冲，静默 [rxSettleMs] 后作为一帧上屏。
  void _onDataReceived(Uint8List data) {
    if (data.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _rxFirstAtMs ??= now;
    _rxBuffer.addAll(data);

    final waited = now - _rxFirstAtMs!;
    if (_rxBuffer.length >= rxMaxBatchBytes || waited >= rxMaxWaitMs) {
      _flushRxBuffer();
    } else {
      // 每次收到新数据都重置静默计时器，实现"等最后一字节后再打印"。
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
    _appendLog(DebugLogEntry.receive(bytes));
    notifyListeners();
  }

  void _onConnectionError(Object error) {
    _markDisconnected('连接异常：${friendlyError(error)}');
  }

  /// 端口已从系统中消失（设备被外部拔出）时由管理器调用。
  void onDeviceRemoved() {
    _markDisconnected('串口设备已被拔出');
  }

  /// 统一的"连接已中断"处理，幂等：重复调用不会产生重复日志。
  void _markDisconnected(String reason) {
    if (_state == SessionState.disconnected) return;
    stopLoopSend();
    unawaited(_service.close());
    _flushRxBuffer();
    lastError = reason;
    _appendLog(DebugLogEntry.system(reason));
    _state = SessionState.disconnected;
    notifyListeners();
  }

  // --- 日志 ---

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
    unawaited(_service.close());
    super.dispose();
  }
}
