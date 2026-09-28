import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../../core/ui/debug_log_entry.dart';
import '../../../core/ui/line_ending.dart';
import '../../../core/ui/send_contracts.dart';
import '../../../core/util/data_format.dart';
import 'mqtt_config.dart';

export '../../../core/ui/debug_log_entry.dart' show friendlyError;

enum MqttSessionState { disconnected, connected }

/// 一个 MQTT 会话：与一个 Broker 的连接，含订阅 / 发布 / 消息日志。
class MqttSession extends ChangeNotifier implements SendPanelController {
  MqttSession(this._config, {required this.id});

  static const int maxLogEntries = 5000;

  final String id;

  MqttConfig _config;
  MqttConfig get config => _config;

  MqttSessionState _state = MqttSessionState.disconnected;
  @override
  bool get isConnected => _state == MqttSessionState.connected;

  String? lastError;

  final List<DebugLogEntry> logs = [];
  int rxBytes = 0;
  int txBytes = 0;

  // --- 发送选项（实现 SendPanelController）---
  @override
  bool sendAsHex = false;
  @override
  LineEnding lineEnding = LineEnding.none;
  @override
  int loopIntervalMs = 1000;
  @override
  bool loopSending = false;
  Timer? _loopTimer;

  // --- 发布选项（MQTT 特有）---
  String _publishTopic = '';
  String get publishTopic => _publishTopic;
  set publishTopic(String value) {
    _publishTopic = value;
    notifyListeners();
  }

  MqttQosLevel _publishQos = MqttQosLevel.atMostOnce;
  MqttQosLevel get publishQos => _publishQos;
  set publishQos(MqttQosLevel value) {
    _publishQos = value;
    notifyListeners();
  }

  bool _retain = false;
  bool get retain => _retain;
  set retain(bool value) {
    _retain = value;
    notifyListeners();
  }

  // --- 订阅列表 ---
  final Map<String, MqttQosLevel> _subscriptions = {};
  Map<String, MqttQosLevel> get subscriptions =>
      Map.unmodifiable(_subscriptions);

  // --- MQTT 客户端资源 ---
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  /// 成功发送后通知管理器记录历史。
  void Function(String content, bool asHex)? onSent;

  void updateConfig(MqttConfig config) {
    if (isConnected) return;
    _config = config;
    notifyListeners();
  }

  // --- 连接管理 ---

  Future<void> connect() async {
    lastError = null;
    try {
      final cfg = _config;
      _validateConfig(cfg);

      final clientId = cfg.clientId.isEmpty
          ? 'debug_assistant_${DateTime.now().millisecondsSinceEpoch}'
          : cfg.clientId;

      final client = MqttServerClient(cfg.host, clientId,
          maxConnectionAttempts: 1);
      client.port = cfg.port;
      client.keepAlivePeriod = cfg.keepAlive;
      client.secure = cfg.tls;
      client.autoReconnect = false;
      client.logging(on: false);

      // 连接消息（含可选遗嘱）
      final connMessage =
          MqttConnectMessage().withClientIdentifier(clientId).startClean();
      if (cfg.will != null && cfg.will!.topic.isNotEmpty) {
        connMessage
          ..withWillTopic(cfg.will!.topic)
          ..withWillMessage(cfg.will!.payload)
          ..withWillQos(_toMqttQos(cfg.will!.qos));
        if (cfg.will!.retain) connMessage.withWillRetain();
      }
      client.connectionMessage = connMessage;

      client.onDisconnected = _onBrokerDisconnected;
      client.onSubscribed = (topic) {
        _appendLog(DebugLogEntry.system('订阅确认：$topic'));
        notifyListeners();
      };
      client.onUnsubscribed = (topic) {
        _appendLog(DebugLogEntry.system('已退订：$topic'));
        notifyListeners();
      };

      _client = client;

      final username = cfg.username.isEmpty ? null : cfg.username;
      final password = cfg.password.isEmpty ? null : cfg.password;

      final status = await client.connect(username, password);
      if (status == null || status.state != MqttConnectionState.connected) {
        throw StateError('连接被拒绝：${status?.returnCode ?? "未知错误"}');
      }

      _updatesSub = client.updates?.listen(_onMessages);

      _state = MqttSessionState.connected;
      _appendLog(DebugLogEntry.system('已连接到 Broker（${cfg.summary}）'));
      notifyListeners();
    } catch (e) {
      final message = friendlyError(e);
      lastError = message;
      _appendLog(DebugLogEntry.system(message));
      _cleanupClient();
      notifyListeners();
      rethrow;
    }
  }

  /// Broker 主动断开时统一处理，幂等。
  void _onBrokerDisconnected() {
    if (_state == MqttSessionState.disconnected) return;
    stopLoopSend();
    _state = MqttSessionState.disconnected;
    _subscriptions.clear();
    lastError = 'Broker 已断开连接';
    _appendLog(DebugLogEntry.system('Broker 已断开连接'));
    unawaited(_releaseResources());
    notifyListeners();
  }

  void _validateConfig(MqttConfig cfg) {
    if (cfg.host.isEmpty) {
      throw const FormatException('请填写 Broker 地址');
    }
    if (cfg.port <= 0 || cfg.port > 65535) {
      throw const FormatException('请填写有效的端口（1-65535）');
    }
  }

  // --- 订阅管理 ---

  void subscribe(String topic, MqttQosLevel qos) {
    if (!isConnected) throw StateError('连接未建立');
    if (topic.isEmpty) throw const FormatException('请填写主题过滤器');
    _client!.subscribe(topic, _toMqttQos(qos));
    _subscriptions[topic] = qos;
    notifyListeners();
  }

  void unsubscribe(String topic) {
    if (!isConnected) return;
    _client!.unsubscribe(topic);
    _subscriptions.remove(topic);
    notifyListeners();
  }

  // --- 接收（MQTT 消息是离散的，无需静默判帧）---

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final publishMsg = msg.payload as MqttPublishMessage;
      final bytes = Uint8List.fromList(publishMsg.payload.message);
      if (bytes.isEmpty) continue;
      rxBytes += bytes.length;
      _appendLog(DebugLogEntry.receive(bytes, source: msg.topic));
    }
    notifyListeners();
  }

  // --- 发送（实现 SendPanelController）---

  @override
  void sendContent(String raw, {required bool asHex}) {
    sendAsHex = asHex;
    final bytes = _encode(raw, asHex);
    if (bytes.isEmpty) throw const FormatException('发送内容为空');
    _publishAndLog(bytes);
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
          _publishAndLog(bytes);
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

  void _publishAndLog(Uint8List bytes) {
    if (!isConnected) throw StateError('连接未建立');
    if (publishTopic.isEmpty) {
      throw const FormatException('请先填写发布主题');
    }
    final builder = MqttClientPayloadBuilder();
    for (final b in bytes) {
      builder.addByte(b);
    }
    _client!.publishMessage(
      publishTopic,
      _toMqttQos(publishQos),
      builder.payload!,
      retain: retain,
    );
    txBytes += bytes.length;
    _appendLog(DebugLogEntry.transmit(bytes, source: publishTopic));
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (!isConnected) {
      _state = MqttSessionState.disconnected;
      return;
    }
    stopLoopSend();
    _state = MqttSessionState.disconnected; // 置先，确保回调幂等
    _subscriptions.clear();
    await _releaseResources();
    _appendLog(DebugLogEntry.system('连接已关闭'));
    notifyListeners();
  }

  Future<void> _releaseResources() async {
    final sub = _updatesSub;
    _updatesSub = null;
    await sub?.cancel();
    final client = _client;
    _client = null;
    client?.disconnect();
  }

  void _cleanupClient() {
    _updatesSub = null;
    _client = null;
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

  // --- QoS 枚举转换 ---

  static MqttQos _toMqttQos(MqttQosLevel level) => switch (level) {
        MqttQosLevel.atMostOnce => MqttQos.atMostOnce,
        MqttQosLevel.atLeastOnce => MqttQos.atLeastOnce,
        MqttQosLevel.exactlyOnce => MqttQos.exactlyOnce,
      };

  @override
  void dispose() {
    _loopTimer?.cancel();
    unawaited(_releaseResources());
    super.dispose();
  }
}
