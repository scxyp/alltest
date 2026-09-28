import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hid_tool/hid_tool.dart';

import '../../../core/ui/quick_command.dart';
import '../../../core/ui/send_contracts.dart';
import '../data/raw_usb_service.dart';
import '../data/usb_store.dart';
import 'hid_usb_session.dart';
import 'raw_usb_session.dart';
import 'usb_device_info.dart';
import 'usb_session_base.dart';

/// 管理 HID / 通用 USB 两类会话、设备枚举与热插拔，以及共享的
/// 快捷指令 / 发送历史。
class UsbSessionManager extends ChangeNotifier implements QuickCommandStore {
  UsbSessionManager._(this._store);

  final UsbStore _store;
  final RawUsbService _rawService = RawUsbService.instance;

  static const int historyLimit = 30;

  /// 最多同时打开的会话数（HID / 通用 USB 合计）。
  static const int maxSessions = 4;

  /// 后台轮询设备变更的间隔（HID 热插拔另有原生事件，此处仅兜底）。
  static const Duration _pollInterval = Duration(seconds: 5);

  final List<UsbSessionBase> sessions = [];

  List<UsbDeviceInfo> hidDevices = [];
  List<UsbDeviceInfo> rawDevices = [];
  bool isEnumerating = false;
  String? hidEnumerateError;
  String? rawEnumerateError;

  StreamSubscription<HidDeviceEvent>? _hidConnectedSub;
  StreamSubscription<HidDeviceEvent>? _hidDisconnectedSub;
  Timer? _eventDebounce;
  Timer? _pollTimer;
  bool _listeningStarted = false;

  @override
  List<QuickCommand> quickCommands = [];
  @override
  List<SendHistoryItem> history = [];

  int _sessionSeq = 0;

  static Future<UsbSessionManager> create() async {
    final store = await UsbStore.create();
    final manager = UsbSessionManager._(store);
    manager.quickCommands = store.loadQuickCommands();
    manager.history = store.loadSendHistory();
    manager._startHotplug();
    // 首次枚举（不等待，页面/对话框可直接看到刷新状态）。
    unawaited(manager.refresh());
    return manager;
  }

  /// 当前已被会话占用的设备标识。
  Set<String> get busyIds => sessions.map((s) => _deviceIdOf(s)).toSet();

  String _deviceIdOf(UsbSessionBase session) {
    if (session is HidUsbSession) return session.device.id;
    if (session is RawUsbSession) return session.device.id;
    return session.id;
  }

  String? get lastHidDeviceId => _store.loadLastHidDeviceId();
  String? get lastRawDeviceId => _store.loadLastRawDeviceId();

  // --- 枚举 / 热插拔 ---

  void _startHotplug() {
    if (_listeningStarted) return;
    _listeningStarted = true;
    Hid.startListening().catchError((Object _) {
      // 个别平台不支持时忽略，仍有轮询兜底。
    });
    _hidConnectedSub = HidDeviceEvents.onConnected.listen((_) => _onHidChanged());
    _hidDisconnectedSub =
        HidDeviceEvents.onDisconnected.listen((_) => _onHidChanged());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollRawDevices());
  }

  void _onHidChanged() {
    _eventDebounce?.cancel();
    _eventDebounce = Timer(const Duration(milliseconds: 500), () => refresh());
  }

  /// 后台低成本检查 raw 设备增减（不读取字符串描述符），
  /// 集合变化时再做一次完整枚举。
  Future<void> _pollRawDevices() async {
    try {
      final devices = await _rawService.enumerate(fetchStrings: false);
      final newIds = devices.map((d) => d.id).toSet();
      final oldIds = rawDevices.map((d) => d.id).toSet();
      if (!_setEquals(newIds, oldIds)) {
        await refresh();
      }
    } catch (_) {
      // 轮询失败静默（可能是尚未安装 WinUSB 驱动，错误由对话框显式展示）。
    }
  }

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// 重新枚举两类设备。[fetchStrings] 为 false 时不读取 raw 字符串描述符。
  Future<void> refresh({bool fetchStrings = true}) async {
    if (isEnumerating) return;
    isEnumerating = true;
    notifyListeners();

    // HID 枚举（本地 hidapi，快速且不依赖驱动）。
    try {
      final devices = await Hid.getDevices();
      hidDevices = devices.map(UsbDeviceInfo.fromHid).toList();
      hidEnumerateError = null;
    } catch (e) {
      hidEnumerateError = friendlyError(e);
    }
    notifyListeners();

    // 通用 USB 枚举（worker isolate；失败不影响 HID 列表）。
    try {
      final devices = await _rawService.enumerate(fetchStrings: fetchStrings);
      rawDevices = devices.map(UsbDeviceInfo.fromRaw).toList();
      rawEnumerateError = null;
    } catch (e) {
      rawEnumerateError = friendlyError(e);
    }

    isEnumerating = false;
    notifyListeners();
  }

  // --- 会话管理 ---

  /// 创建设备会话并立即打开。
  Future<UsbSessionBase> openSession(UsbDeviceInfo info) async {
    if (sessions.length >= maxSessions) {
      throw StateError('最多支持同时打开 $maxSessions 个 USB 会话');
    }
    if (busyIds.contains(info.id)) {
      throw StateError('${info.displayName} 已在另一个会话中打开');
    }

    _sessionSeq++;
    final sessionId =
        'usb_session_${DateTime.now().microsecondsSinceEpoch}_$_sessionSeq';
    final UsbSessionBase session;
    switch (info.kind) {
      case UsbDeviceKind.hid:
        if (info.nativeDevice is! HidDevice) {
          throw StateError('HID 设备信息已失效，请重新枚举');
        }
        session = HidUsbSession(
          id: sessionId,
          device: info,
          title: info.displayName,
        );
        unawaited(_store.saveLastHidDeviceId(info.id));
      case UsbDeviceKind.raw:
        if (info.nativeDevice is! RawUsbDevice) {
          throw StateError('USB 设备信息已失效，请重新枚举');
        }
        session = RawUsbSession(id: sessionId, device: info);
        unawaited(_store.saveLastRawDeviceId(info.id));
    }
    session.onSent = _recordHistory;

    sessions.add(session);
    notifyListeners();

    try {
      await session.open();
    } catch (_) {
      // 失败的会话保留在视图中，错误展示在日志区，用户可重试。
    }
    return session;
  }

  Future<void> closeSession(String id) async {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final session = sessions.removeAt(index);
    try {
      await session.close();
    } catch (_) {}
    session.dispose();
    notifyListeners();
  }

  // --- 发送历史 ---

  void _recordHistory(String content, bool asHex) {
    if (content.isEmpty) return;
    history.removeWhere((h) => h.content == content && h.asHex == asHex);
    history.insert(
      0,
      SendHistoryItem(content: content, asHex: asHex, time: DateTime.now()),
    );
    if (history.length > historyLimit) {
      history = history.sublist(0, historyLimit);
    }
    final snapshot = List<SendHistoryItem>.from(history);
    unawaited(_store.saveSendHistory(snapshot));
    notifyListeners();
  }

  @override
  void clearHistory() {
    history.clear();
    unawaited(_store.saveSendHistory(const []));
    notifyListeners();
  }

  // --- 快捷指令 ---

  @override
  Future<void> addQuickCommand(QuickCommand command) async {
    quickCommands.add(command);
    await _persistQuickCommands();
  }

  @override
  Future<void> updateQuickCommand(QuickCommand command) async {
    final index = quickCommands.indexWhere((c) => c.id == command.id);
    if (index >= 0) quickCommands[index] = command;
    await _persistQuickCommands();
  }

  @override
  Future<void> removeQuickCommand(String id) async {
    quickCommands.removeWhere((c) => c.id == id);
    await _persistQuickCommands();
  }

  @override
  String newCommandId() =>
      'cmd_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _persistQuickCommands() async {
    final snapshot = List<QuickCommand>.from(quickCommands);
    await _store.saveQuickCommands(snapshot);
    notifyListeners();
  }

  @override
  void dispose() {
    _eventDebounce?.cancel();
    _pollTimer?.cancel();
    unawaited(_hidConnectedSub?.cancel());
    unawaited(_hidDisconnectedSub?.cancel());
    if (_listeningStarted) {
      unawaited(Hid.stopListening());
    }
    super.dispose();
  }
}
