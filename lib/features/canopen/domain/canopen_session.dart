import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../../core/ui/line_ending.dart';
import '../../../core/ui/send_contracts.dart';
import '../../../core/util/data_format.dart';
import '../../can/data/can_transport_registry.dart';
import '../../can/domain/can_frame.dart';
import '../../can/domain/can_transport.dart';
import 'canopen_config.dart';
import 'canopen_nmt.dart';
import 'canopen_sdo.dart';

export '../../../core/ui/debug_log_entry.dart' show friendlyError;

enum CanOpenSessionState { disconnected, connecting, connected }

/// CANopen 节点的 Heartbeat 状态记录。
class NodeHeartbeat {
  NodeHeartbeat({required this.lastState, required this.lastHeartbeatAt});
  NmtState lastState;
  DateTime lastHeartbeatAt;
}

/// 一个 CANopen 会话：通过 [CanTransport] 抽象接口连接 CAN 适配器，
/// 实现 CANopen 协议层的帧路由与 SDO/NMT 交互。
///
/// 传输层插件化后，底层可以是 SLCAN 串口协议、PCAN-USB、
/// Kvaser 或自研 USB-CAN 协议——会话代码无需改动。
///
/// 接收侧由传输层解析原始数据为 [CanFrame]，会话根据帧 ID（COB-ID）前缀
/// 分发到不同的 CANopen 协议处理器（SDO 响应 / Heartbeat / EMCY / PDO）。
///
/// 发送面板的功能：
/// - 用户输入 HEX 数据 → 构造 CanFrame → 交给传输层编码发送
/// - 帧 ID 由会话属性 frameId 决定，默认指向 SDO Request COB-ID
class CanOpenSession extends ChangeNotifier implements SendPanelController {
  CanOpenSession({required this.id, required CanOpenConfig config})
      // ignore: prefer_initializing_formals
      : _config = config,
        _frameId = SdoCodec.requestCobIdBase + config.nodeId;

  static const int maxLogEntries = 5000;

  /// SDO 响应等待超时（毫秒）。
  static const int sdoTimeoutMs = 2000;

  final String id;
  CanTransport? _transport;

  void Function(String content, bool asHex)? onSent;

  CanOpenConfig _config;
  CanOpenConfig get config => _config;

  CanOpenSessionState _state = CanOpenSessionState.disconnected;
  CanOpenSessionState get state => _state;
  @override
  bool get isConnected => _state == CanOpenSessionState.connected;

  String? lastError;

  final List<DebugLogEntry> logs = [];
  int rxBytes = 0;
  int txBytes = 0;

  // --- 发送选项（实现 SendPanelController）---
  @override
  bool sendAsHex = true;
  @override
  LineEnding lineEnding = LineEnding.none;
  @override
  int loopIntervalMs = 1000;
  @override
  bool loopSending = false;
  Timer? _loopTimer;

  // --- 帧属性 ---
  int _frameId;
  int get frameId => _frameId;
  set frameId(int value) {
    _frameId = value;
    notifyListeners();
  }

  // CANopen 帧几乎都用标准帧（11-bit ID），无需扩展帧开关。

  // --- 节点状态表（Node ID → Heartbeat 记录）---
  final Map<int, NodeHeartbeat> _nodeStates = {};
  Map<int, NodeHeartbeat> get nodeStates => Map.unmodifiable(_nodeStates);

  // --- SDO 待处理请求 ---
  final pendingSdos = <PendingSdo>{};

  DateTime? openedAt;

  void updateConfig(CanOpenConfig config) {
    if (isConnected) return;
    _config = config;
    _frameId = SdoCodec.requestCobIdBase + config.nodeId;
    notifyListeners();
  }

  // --- 连接管理 ---

  Future<void> connect() async {
    if (isConnected) return;
    lastError = null;
    try {
      registerCanTransports();

      _transport = CanTransportRegistry.create(_config.transportType);
      await _transport!.open(
        config: _config.toTransportConfig(),
        onFrame: routeFrame,
        onError: _onConnectionError,
      );

      _frameId = SdoCodec.requestCobIdBase + _config.nodeId;
      _state = CanOpenSessionState.connected;
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
      _state = CanOpenSessionState.disconnected;
      return;
    }
    stopLoopSend();
    try {
      await transport?.close();
      await transport?.dispose();
    } catch (_) {}
    _transport = null;
    _cancelAllPendingSdos();
    _state = CanOpenSessionState.disconnected;
    _nodeStates.clear();
    _appendLog(DebugLogEntry.system('已断开 ${_config.portName}'));
    notifyListeners();
  }

  // --- NMT 命令 ---

  /// 发送 NMT 命令到指定节点（0 = 广播所有节点）。
  void sendNmt(NmtCommand cmd, {int targetNodeId = 0}) {
    if (!isConnected) throw StateError('CANopen 未连接');
    final nmtData = NmtCodec.buildNmtCommand(cmd, targetNodeId);
    final frame = CanFrame(
      id: NmtCodec.controlCobId,
      extended: false,
      remote: false,
      data: nmtData,
    );
    _sendCanFrame(frame);
    _appendLog(DebugLogEntry.transmit(
      nmtData,
      source: 'NMT ${cmd.name} → Node $targetNodeId',
    ));
    notifyListeners();
  }

  // --- SDO 快速传输（Expedited）---

  /// 发送 SDO Expedited 读取请求，返回 Future，解析到响应后 completed。
  Future<SdoResponseResult> sdoRead(int index, int subindex) {
    if (!isConnected) return Future.error(StateError('CANopen 未连接'));
    final data = SdoCodec.buildReadRequest(index, subindex);
    final frame = CanFrame(
      id: SdoCodec.requestCobIdBase + _config.nodeId,
      extended: false,
      remote: false,
      data: data,
    );
    _sendCanFrame(frame);
    _appendLog(DebugLogEntry.transmit(
      data,
      source: 'SDO R:0x${index.toRadixString(16).toUpperCase().padLeft(4, '0')}:'
          '0x${subindex.toRadixString(16).toUpperCase().padLeft(2, '0')} → Node ${_config.nodeId}',
    ));
    final pending = PendingSdo.read(index, subindex, _config.nodeId);
    pendingSdos.add(pending);
    notifyListeners();
    return pending.completer.future.timeout(
      Duration(milliseconds: sdoTimeoutMs),
      onTimeout: () {
        pendingSdos.remove(pending);
        final err = TimeoutException('SDO 请求超时（${sdoTimeoutMs}ms）');
        _appendLog(DebugLogEntry.system(err.toString()));
        notifyListeners();
        throw err;
      },
    );
  }

  /// 发送 SDO Expedited 写入请求（≤4 字节），不等待响应。
  void sdoWrite(int index, int subindex, Uint8List value) {
    if (!isConnected) throw StateError('CANopen 未连接');
    final data = SdoCodec.buildWriteRequest(index, subindex, value);
    if (data == null) {
      throw StateError('SDO Expedited 仅支持 ≤4 字节数据，'
          '检测到 ${value.length} 字节，请改用分段传输（暂不支持）');
    }
    final frame = CanFrame(
      id: SdoCodec.requestCobIdBase + _config.nodeId,
      extended: false,
      remote: false,
      data: data,
    );
    _sendCanFrame(frame);
    _appendLog(DebugLogEntry.transmit(
      data,
      source: 'SDO W:0x${index.toRadixString(16).toUpperCase().padLeft(4, '0')}:'
          '0x${subindex.toRadixString(16).toUpperCase().padLeft(2, '0')} = '
          '${value.isEmpty ? '(空)' : DataFormat.bytesToHex(value)} → Node ${_config.nodeId}',
    ));
    notifyListeners();
  }

  // --- 发送面板 ---

  @override
  void sendContent(String raw, {required bool asHex}) {
    sendAsHex = asHex;
    final bytes = _encodePayload(raw, asHex);
    if (bytes.isEmpty) throw const FormatException('发送内容为空');
    _sendFrame(bytes);
    onSent?.call(raw, asHex);
  }

  @override
  void startLoopSend(String raw) {
    if (loopSending || !isConnected) return;
    final bytes = _encodePayload(raw, sendAsHex);
    if (bytes.isEmpty) throw const FormatException('发送内容为空');

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

  Uint8List _encodePayload(String raw, bool asHex) {
    if (asHex) return DataFormat.hexToBytes(raw);
    return DataFormat.textToBytes(raw);
  }

  /// 构造 CanFrame 并通过传输层发送。
  void _sendFrame(Uint8List data) {
    final frame = CanFrame(
      id: _frameId,
      extended: false,
      remote: false,
      data: data,
    );
    _sendCanFrame(frame);
    _appendLog(DebugLogEntry.transmit(data, source: frame.sourceTag));
    notifyListeners();
  }

  void _sendCanFrame(CanFrame frame) {
    final transport = _transport;
    if (transport == null || !isConnected) {
      throw StateError('CANopen 未连接');
    }
    transport.sendFrame(frame).then((bytes) {
      txBytes += bytes;
      notifyListeners();
    }).catchError((e) {
      _markDisconnected('连接已断开：${friendlyError(e)}');
    });
  }

  // --- 接收（帧路由）---

  /// 传输层解析好的 CAN 帧回调。
  /// 公开方法，也供测试直接构造帧后调用验证路由逻辑。
  void routeFrame(CanFrame frame) {
    rxBytes += frame.data.length;
    final id = frame.id;

    // Heartbeat: 0x700 + NID
    if ((id & 0x780) == 0x700) {
      final nodeId = id & 0x7F;
      final state = NmtCodec.parseHeartbeat(frame.data);
      if (state != null) {
        _nodeStates[nodeId] = NodeHeartbeat(
          lastState: state,
          lastHeartbeatAt: DateTime.now(),
        );
        _appendLog(DebugLogEntry.receive(
          frame.data,
          source: 'Heartbeat Node $nodeId: ${state.label}',
        ));
      } else {
        _appendLog(DebugLogEntry.receive(
          frame.data,
          source: 'Heartbeat Node $nodeId',
        ));
      }
      notifyListeners();
      return;
    }

    // SDO Response: 0x580 + NID
    if ((id & 0x780) == 0x580) {
      final nodeId = id & 0x7F;
      _handleSdoResponse(frame.data, nodeId);
      return;
    }

    // SYNC: 0x080 广播
    if ((id & 0x780) == 0x080) {
      _appendLog(DebugLogEntry.system('SYNC（帧同步）'));
      notifyListeners();
      return;
    }
    // EMCY: 0x100 + NID
    if ((id & 0x780) == 0x100) {
      final nodeId = id & 0x7F;
      _appendLog(DebugLogEntry.receive(
        frame.data,
        source: 'EMCY Node $nodeId',
      ));
      notifyListeners();
      return;
    }

    // PDO Receive: 0x180+NID / 0x200+NID / 0x280+NID / 0x300+NID
    if ((id & 0x700) == 0x180 ||
        (id & 0x700) == 0x200 ||
        (id & 0x700) == 0x280 ||
        (id & 0x700) == 0x300) {
      final nodeId = id & 0x7F;
      final pdoNum = switch (id & 0x700) {
        0x180 => 1,
        0x200 => 2,
        0x280 => 3,
        0x300 => 4,
        _ => 0,
      };
      _appendLog(DebugLogEntry.receive(
        frame.data,
        source: 'PDO$pdoNum Node $nodeId',
      ));
      notifyListeners();
      return;
    }

    _appendLog(DebugLogEntry.receive(
      frame.data,
      source: 'ID:0x${frame.idHex}',
    ));
    notifyListeners();
  }

  void _handleSdoResponse(Uint8List data, int nodeId) {
    final result = SdoCodec.parseResponse(data);
    if (result == null) {
      _appendLog(DebugLogEntry.receive(
        data,
        source: 'SDO R Node $nodeId（无法解析，可能为分段传输）',
      ));
      notifyListeners();
      return;
    }
    result.fromNodeId = nodeId;

    if (result.type == SdoResponse.abort) {
      final abortDesc = SdoCodec.describeAbort(result.abortCode ?? 0);
      _appendLog(DebugLogEntry.system(
        'SDO Abort Node $nodeId: '
        'Index=0x${result.index.toRadixString(16).toUpperCase().padLeft(4, '0')}:'
        'Sub=0x${result.subindex.toRadixString(16).toUpperCase().padLeft(2, '0')} → $abortDesc',
      ));
    } else if (result.type == SdoResponse.readOk) {
      _appendLog(DebugLogEntry.receive(
        result.data,
        source: 'SDO R Node $nodeId: '
            'Index=0x${result.index.toRadixString(16).toUpperCase().padLeft(4, '0')}:'
            'Sub=0x${result.subindex.toRadixString(16).toUpperCase().padLeft(2, '0')}',
      ));
    } else {
      _appendLog(DebugLogEntry.system(
        'SDO Write OK Node $nodeId: '
        'Index=0x${result.index.toRadixString(16).toUpperCase().padLeft(4, '0')}:'
        'Sub=0x${result.subindex.toRadixString(16).toUpperCase().padLeft(2, '0')}',
      ));
    }

    _resolvePendingSdo(result);
    notifyListeners();
  }

  void _resolvePendingSdo(SdoResponseResult response) {
    for (final pending in List<PendingSdo>.of(pendingSdos)) {
      if (pending.index == response.index &&
          pending.subindex == response.subindex &&
          (pending.targetNodeId == response.fromNodeId ||
              pending.targetNodeId == -1)) {
        pendingSdos.remove(pending);
        if (response.type == SdoResponse.abort) {
          pending.completer.completeError(StateError(
            'SDO Abort: ${SdoCodec.describeAbort(response.abortCode ?? 0)}',
          ));
        } else {
          pending.completer.complete(response);
        }
        return;
      }
    }
  }

  void _cancelAllPendingSdos() {
    for (final p in List<PendingSdo>.of(pendingSdos)) {
      if (!p.completer.isCompleted) {
        p.completer.completeError(StateError('会话已关闭'));
      }
    }
    pendingSdos.clear();
  }

  void _onConnectionError(Object error) {
    _markDisconnected('连接异常：${friendlyError(error)}');
  }

  void onDeviceRemoved() {
    _markDisconnected('CAN 适配器已被拔出');
  }

  void _markDisconnected(String reason) {
    if (_state == CanOpenSessionState.disconnected) return;
    stopLoopSend();
    final transport = _transport;
    unawaited(() async {
      try {
        await transport?.close();
        await transport?.dispose();
      } catch (_) {}
    }());
    _transport = null;
    _cancelAllPendingSdos();
    lastError = reason;
    _appendLog(DebugLogEntry.system(reason));
    _state = CanOpenSessionState.disconnected;
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
    _cancelAllPendingSdos();
    unawaited(disconnect());
    super.dispose();
  }
}

/// SDO 待处理请求记录。
class PendingSdo {
  PendingSdo.read(this.index, this.subindex, this.targetNodeId);

  final int index;
  final int subindex;
  final int targetNodeId;
  final completer = Completer<SdoResponseResult>();
}
