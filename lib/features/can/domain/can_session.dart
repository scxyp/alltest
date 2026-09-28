import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../../core/ui/line_ending.dart';
import '../../../core/ui/send_contracts.dart';
import '../../../core/util/data_format.dart';
import '../data/can_transport_registry.dart';
import '../domain/can_transport.dart';
import 'can_config.dart';
import 'can_frame.dart';

export '../../../core/ui/debug_log_entry.dart' show friendlyError;

enum CanSessionState { disconnected, connected }

/// 一个 CAN 适配器连接对应一个会话。
///
/// 通过 [CanTransport] 抽象接口与底层传输层解耦——可以是 SLCAN 串口协议、
/// PCAN-USB、Kvaser 或自研 USB-CAN 协议，会话代码无需改动。
///
/// 发送侧：用户在发送面板输入 HEX 数据，结合会话的帧 ID / 帧类型属性
/// 构造 [CanFrame]，交给 [CanTransport.sendFrame] 编码发送。
///
/// 接收侧：[CanTransport] 按传输层协议解析原始数据为 [CanFrame]，
/// 通过 [CanTransport.open] 的 onFrame 回调上屏。
class CanSession extends ChangeNotifier implements SendPanelController {
  CanSession({required this.id, required CanConfig config})
      // ignore: prefer_initializing_formals
      : _config = config;

  static const int maxLogEntries = 5000;

  final String id;
  CanTransport? _transport;

  /// 成功发送后通知管理器记录历史。
  void Function(String content, bool asHex)? onSent;

  CanConfig _config;
  CanConfig get config => _config;

  CanSessionState _state = CanSessionState.disconnected;
  CanSessionState get state => _state;
  @override
  bool get isConnected => _state == CanSessionState.connected;

  String? lastError;

  final List<DebugLogEntry> logs = [];
  int rxBytes = 0;
  int txBytes = 0;

  // --- 发送选项（实现 SendPanelController）---
  @override
  bool sendAsHex = true; // CAN 数据是二进制，默认 HEX 模式
  @override
  LineEnding lineEnding = LineEnding.none;
  @override
  int loopIntervalMs = 1000;
  @override
  bool loopSending = false;
  Timer? _loopTimer;

  // --- CAN 帧属性（会话级，类似 MQTT 的 publishTopic）---
  int _frameId = 0x123;
  int get frameId => _frameId;
  set frameId(int value) {
    _frameId = value;
    notifyListeners();
  }

  bool _extended = false;
  bool get extended => _extended;
  set extended(bool value) {
    _extended = value;
    notifyListeners();
  }

  bool _remote = false;
  bool get remote => _remote;
  set remote(bool value) {
    _remote = value;
    notifyListeners();
  }

  /// 会话建立时间（用于导出文件命名等）。
  DateTime? openedAt;

  /// 更新连接参数（仅在断开状态下允许）。
  void updateConfig(CanConfig config) {
    if (isConnected) return;
    _config = config;
    notifyListeners();
  }

  // --- 连接管理 ---

  Future<void> connect() async {
    if (isConnected) return;
    lastError = null;
    try {
      // 确保传输层已注册
      registerCanTransports();

      _transport = CanTransportRegistry.create(_config.transportType);
      await _transport!.open(
        config: _config.toTransportConfig(),
        onFrame: _onFrame,
        onError: _onConnectionError,
      );

      _state = CanSessionState.connected;
      openedAt = DateTime.now();
      _appendLog(DebugLogEntry.system(
        '已连接 ${_config.portName}（${_config.canBitrate.label}，传输层：${_config.transportType}）',
      ));
      notifyListeners();
    } catch (e) {
      final message = friendlyError(e);
      lastError = message;
      _appendLog(DebugLogEntry.system(message));
      if (_transport != null) {
        try {
          await _transport!.close();
          await _transport!.dispose();
        } catch (_) {}
        _transport = null;
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final transport = _transport;
    if (!isConnected && (transport == null || !transport.isOpen)) {
      _state = CanSessionState.disconnected;
      return;
    }
    stopLoopSend();
    try {
      await transport?.close();
      await transport?.dispose();
    } catch (_) {}
    _transport = null;
    _state = CanSessionState.disconnected;
    _appendLog(DebugLogEntry.system('已断开 ${_config.portName}'));
    notifyListeners();
  }

  // --- 发送（实现 SendPanelController）---

  @override
  void sendContent(String raw, {required bool asHex}) {
    sendAsHex = asHex;
    final bytes = _encodePayload(raw, asHex);
    if (bytes.isEmpty && !remote) {
      throw const FormatException('发送内容为空');
    }
    if (bytes.length > 8) {
      throw const FormatException('CAN 数据帧最多 8 字节');
    }
    _sendFrame(bytes);
    onSent?.call(raw, asHex);
  }

  @override
  void startLoopSend(String raw) {
    if (loopSending || !isConnected) return;
    final bytes = _encodePayload(raw, sendAsHex);
    if (bytes.isEmpty && !remote) throw const FormatException('发送内容为空');
    if (bytes.length > 8) {
      throw const FormatException('CAN 数据帧最多 8 字节');
    }

    loopSending = true;
    onSent?.call(raw, sendAsHex);
    _loopTimer = Timer.periodic(
      Duration(milliseconds: loopIntervalMs <= 0 ? 1000 : loopIntervalMs),
      (_) {
        try {
          _sendFrame(bytes);
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

  /// 将用户输入编码为 CAN 帧数据负载。
  Uint8List _encodePayload(String raw, bool asHex) {
    if (asHex) return DataFormat.hexToBytes(raw);
    return DataFormat.textToBytes(raw);
  }

  /// 构造 CAN 帧并交给传输层发送。
  void _sendFrame(Uint8List data) {
    final transport = _transport;
    if (transport == null || !isConnected) {
      throw StateError('CAN 适配器未连接');
    }
    final frame = CanFrame(
      id: _frameId,
      extended: _extended,
      remote: _remote,
      data: _remote ? Uint8List(0) : data,
    );
    transport.sendFrame(frame).then((bytes) {
      txBytes += bytes;
      notifyListeners();
    }).catchError((e) {
      final message = friendlyError(e);
      _markDisconnected('连接已断开：$message');
    });
    _appendLog(DebugLogEntry.transmit(
      _remote ? Uint8List(0) : data,
      source: frame.sourceTag,
    ));
    notifyListeners();
  }

  // --- 接收 ---

  /// 传输层解析好的 CAN 帧回调。
  void _onFrame(CanFrame frame) {
    rxBytes += frame.data.length;
    _appendLog(DebugLogEntry.receive(
      frame.data,
      source: frame.sourceTag,
    ));
    notifyListeners();
  }

  void _onConnectionError(Object error) {
    _markDisconnected('连接异常：${friendlyError(error)}');
  }

  /// 端口已从系统中消失（设备被外部拔出）时由管理器调用。
  void onDeviceRemoved() {
    _markDisconnected('CAN 适配器已被拔出');
  }

  /// 统一的"连接已中断"处理，幂等：重复调用不会产生重复日志。
  void _markDisconnected(String reason) {
    if (_state == CanSessionState.disconnected) return;
    stopLoopSend();
    final transport = _transport;
    unawaited(() async {
      try {
        await transport?.close();
        await transport?.dispose();
      } catch (_) {}
    }());
    _transport = null;
    lastError = reason;
    _appendLog(DebugLogEntry.system(reason));
    _state = CanSessionState.disconnected;
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
    logs.clear();
    rxBytes = 0;
    txBytes = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    unawaited(disconnect());
    super.dispose();
  }
}
