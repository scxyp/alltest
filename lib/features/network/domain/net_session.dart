import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../../core/ui/line_ending.dart';
import '../../../core/ui/send_contracts.dart';
import '../../../core/util/data_format.dart';
import 'net_config.dart';

export '../../../core/ui/debug_log_entry.dart' show friendlyError;

enum NetState { disconnected, connected }

/// 一个 TCP 服务端当前接受的客户端连接。
class NetPeer {
  NetPeer({required this.id, required this.address, required this.port});

  final String id;
  final String address;
  final int port;

  String get label => '$address:$port';
}

/// 一个网络会话：TCP 客户端 / TCP 服务端 / UDP，三态合一。
class NetSession extends ChangeNotifier implements SendPanelController {
  NetSession(this._config, {required this.id});

  static const int maxLogEntries = 5000;

  // --- 接收合并（静默判帧，与串口一致，解决 TCP 粘包 / 分片显示）---
  static const int rxSettleMs = 30;
  static const int rxMaxBatchBytes = 4096;
  static const int rxMaxWaitMs = 200;

  final String id;

  NetConfig _config;
  NetConfig get config => _config;

  NetState _state = NetState.disconnected;
  @override
  bool get isConnected => _state == NetState.connected;

  String? lastError;

  final List<DebugLogEntry> logs = [];
  int rxBytes = 0;
  int txBytes = 0;

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

  // --- Socket 资源 ---
  Socket? _tcpSocket; // TCP 客户端
  ServerSocket? _server; // TCP 服务端
  RawDatagramSocket? _udp;
  final Map<String, _PeerConn> _peers = {};
  StreamSubscription<List<int>>? _tcpSub;
  StreamSubscription<RawSocketEvent>? _udpSub;
  StreamSubscription<Socket>? _acceptSub;

  /// 成功发送后通知管理器记录历史。
  void Function(String content, bool asHex)? onSent;

  // --- TCP 服务端的发送目标：null 表示发给全部客户端 ---
  String? _targetPeerId;
  String? get targetPeerId => _targetPeerId;

  /// 当前已连接的客户端（仅 TCP 服务端模式有内容）。
  List<NetPeer> get peers =>
      _peers.values.map((c) => c.peer).toList(growable: false);

  /// 接收合并缓冲。
  final List<int> _rxBuffer = [];
  String? _rxSource;
  int? _rxFirstAtMs;
  Timer? _rxFlushTimer;

  /// 更新连接参数（仅断开状态下允许）。
  void updateConfig(NetConfig config) {
    if (isConnected) return;
    _config = config;
    notifyListeners();
  }

  // --- 连接管理 ---

  Future<void> connect() async {
    lastError = null;
    try {
      switch (_config.mode) {
        case NetMode.tcpClient:
          await _connectTcpClient();
        case NetMode.tcpServer:
          await _connectTcpServer();
        case NetMode.udp:
          await _connectUdp();
      }
      _state = NetState.connected;
      _appendLog(DebugLogEntry.system('已建立连接（${_config.summary}）'));
      notifyListeners();
    } catch (e) {
      final message = friendlyError(e);
      lastError = message;
      _appendLog(DebugLogEntry.system(message));
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _connectTcpClient() async {
    final cfg = _config;
    _validateRemote(cfg);
    final socket = await Socket.connect(
      cfg.remoteHost,
      cfg.remotePort,
      sourceAddress: cfg.bindAddress.isEmpty ? null : cfg.bindAddress,
    );
    _tcpSocket = socket;
    _tcpSub = socket.listen(
      (data) => _enqueueRx(Uint8List.fromList(data), null),
      onError: (Object e) => _markDisconnected('连接异常：${friendlyError(e)}'),
      onDone: () {
        if (_state == NetState.connected) {
          _markDisconnected('远端已关闭连接');
        }
      },
      cancelOnError: true,
    );
  }

  Future<void> _connectTcpServer() async {
    final cfg = _config;
    if (cfg.localPort <= 0 || cfg.localPort > 65535) {
      throw const FormatException('请填写有效的本地监听端口（1-65535）');
    }
    final server = await ServerSocket.bind(
      cfg.bindAddress.isEmpty
          ? InternetAddress.anyIPv4
          : InternetAddress(cfg.bindAddress),
      cfg.localPort,
    );
    _server = server;
    _acceptSub = server.listen(_onPeerAccepted, onError: (Object e) {
      _markDisconnected('监听异常：${friendlyError(e)}');
    });
  }

  void _onPeerAccepted(Socket socket) {
    final peer = NetPeer(
      id: '${socket.remoteAddress.address}:${socket.remotePort}',
      address: socket.remoteAddress.address,
      port: socket.remotePort,
    );
    _peers[peer.id] = _PeerConn(
      peer: peer,
      socket: socket,
      subscription: socket.listen(
        (data) =>
            _enqueueRx(Uint8List.fromList(data), peer.label),
        onError: (Object e) {
          _appendLog(DebugLogEntry.system(
              '客户端 ${peer.label} 异常：${friendlyError(e)}'));
          _removePeer(peer.id);
        },
        onDone: () {
          _appendLog(DebugLogEntry.system('客户端 ${peer.label} 已断开'));
          _removePeer(peer.id);
        },
        cancelOnError: true,
      ),
    );
    _appendLog(DebugLogEntry.system('客户端 ${peer.label} 已接入'));
    notifyListeners();
  }

  Future<void> _removePeer(String id) async {
    final conn = _peers.remove(id);
    if (conn == null) return;
    await conn.subscription.cancel();
    conn.socket.destroy();
    if (_targetPeerId == id) _targetPeerId = null;
    notifyListeners();
  }

  Future<void> _connectUdp() async {
    final cfg = _config;
    _validateRemote(cfg);
    final socket = await RawDatagramSocket.bind(
      cfg.bindAddress.isEmpty
          ? InternetAddress.anyIPv4
          : InternetAddress(cfg.bindAddress),
      cfg.localPort,
    );
    socket.broadcastEnabled = cfg.broadcast;
    _udp = socket;
    _udpSub = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          _enqueueRx(
            datagram.data,
            '${datagram.address.address}:${datagram.port}',
          );
        }
      }
    }, onError: (Object e) {
      _markDisconnected('UDP 异常：${friendlyError(e)}');
    });
  }

  void _validateRemote(NetConfig cfg) {
    if (cfg.remoteHost.isEmpty) {
      throw const FormatException('请填写目标主机地址');
    }
    if (cfg.remotePort <= 0 || cfg.remotePort > 65535) {
      throw const FormatException('请填写有效的目标端口（1-65535）');
    }
    // 校验目标地址格式（域名允许由系统解析，这里仅校验字面 IP 合法性）。
    if (cfg.remoteHost.contains('.') &&
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(cfg.remoteHost)) {
      final parts = cfg.remoteHost.split('.').map(int.tryParse);
      final invalid = parts.any((p) => p == null || p < 0 || p > 255);
      if (invalid) throw const FormatException('目标 IP 地址格式不正确');
    }
  }

  Future<void> disconnect() async {
    if (!isConnected) {
      _state = NetState.disconnected;
      return;
    }
    stopLoopSend();
    await _releaseResources();
    _state = NetState.disconnected;
    _appendLog(DebugLogEntry.system('连接已关闭'));
    notifyListeners();
  }

  Future<void> _releaseResources() async {
    _rxFlushTimer?.cancel();
    _rxFlushTimer = null;
    await _tcpSub?.cancel();
    _tcpSub = null;
    await _acceptSub?.cancel();
    _acceptSub = null;
    await _udpSub?.cancel();
    _udpSub = null;
    for (final conn in List.of(_peers.values)) {
      await conn.subscription.cancel();
      conn.socket.destroy();
    }
    _peers.clear();
    _tcpSocket?.destroy();
    _tcpSocket = null;
    await _server?.close();
    _server = null;
    _udp?.close();
    _udp = null;
  }

  // --- 发送（实现 SendPanelController）---

  @override
  void sendContent(String raw, {required bool asHex}) {
    sendAsHex = asHex;
    final bytes = _encode(raw, asHex);
    if (bytes.isEmpty) throw const FormatException('发送内容为空');
    _writeAndLog(bytes);
    onSent?.call(raw, asHex);
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
      (_) {
        try {
          _writeAndLog(bytes);
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

  void setTargetPeer(String? peerId) {
    _targetPeerId = peerId;
    notifyListeners();
  }

  Uint8List _encode(String raw, bool asHex) {
    if (asHex) return DataFormat.hexToBytes(raw);
    return DataFormat.textToBytes(raw + lineEnding.suffix);
  }

  void _writeAndLog(Uint8List bytes) {
    if (!isConnected) throw StateError('连接未建立');
    switch (_config.mode) {
      case NetMode.tcpClient:
        _tcpSocket!.add(bytes);
        txBytes += bytes.length;
        _appendLog(DebugLogEntry.transmit(bytes));
      case NetMode.tcpServer:
        final targets = _targetPeerId == null
            ? List.of(_peers.values)
            : [if (_peers[_targetPeerId] != null) _peers[_targetPeerId]!];
        if (targets.isEmpty) {
          throw StateError('没有已连接的客户端');
        }
        for (final conn in targets) {
          conn.socket.add(bytes);
          _appendLog(DebugLogEntry.transmit(bytes, source: conn.peer.label));
        }
        txBytes += bytes.length * targets.length;
      case NetMode.udp:
        final sent = _udp!.send(bytes, InternetAddress(_config.remoteHost),
            _config.remotePort);
        if (sent <= 0) throw StateError('发送失败：数据未发出');
        txBytes += sent;
        _appendLog(DebugLogEntry.transmit(bytes,
            source: '${_config.remoteHost}:${_config.remotePort}'));
    }
    notifyListeners();
  }

  // --- 接收合并（静默判帧，按来源分别成帧）---

  void _enqueueRx(Uint8List data, String? source) {
    if (data.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 不同来源的数据不能合并进同一帧。
    if (_rxSource != source && _rxBuffer.isNotEmpty) {
      _flushRxBuffer();
    }
    _rxSource ??= source;
    _rxFirstAtMs ??= now;
    _rxBuffer.addAll(data);

    final waited = now - _rxFirstAtMs!;
    if (_rxBuffer.length >= rxMaxBatchBytes || waited >= rxMaxWaitMs) {
      _flushRxBuffer();
    } else {
      _rxFlushTimer?.cancel();
      _rxFlushTimer = Timer(
        const Duration(milliseconds: rxSettleMs),
        _flushRxBuffer,
      );
    }
  }

  void _flushRxBuffer() {
    _rxFlushTimer?.cancel();
    _rxFlushTimer = null;
    if (_rxBuffer.isEmpty) {
      _rxSource = null;
      _rxFirstAtMs = null;
      return;
    }
    final bytes = Uint8List.fromList(_rxBuffer);
    final source = _rxSource;
    _rxBuffer.clear();
    _rxSource = null;
    _rxFirstAtMs = null;
    rxBytes += bytes.length;
    _appendLog(DebugLogEntry.receive(bytes, source: source));
    notifyListeners();
  }

  /// 连接被远端关闭 / 异常中断时统一处理，幂等。
  void _markDisconnected(String reason) {
    if (_state == NetState.disconnected) return;
    stopLoopSend();
    _flushRxBuffer();
    lastError = reason;
    _appendLog(DebugLogEntry.system(reason));
    _state = NetState.disconnected;
    unawaited(_releaseResources());
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
    unawaited(_releaseResources());
    super.dispose();
  }
}

class _PeerConn {
  _PeerConn({
    required this.peer,
    required this.socket,
    required this.subscription,
  });

  final NetPeer peer;
  final Socket socket;
  final StreamSubscription<List<int>> subscription;
}
