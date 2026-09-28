import 'can_config.dart';
import 'can_frame.dart';

/// CAN 传输层抽象接口。
///
/// 将 CAN 帧的收发与底层传输协议（SLCAN / PCAN-USB / Kvaser / 自研 FFI DLL）解耦。
/// CAN 会话和 CANopen 会话只依赖此接口，不关心帧如何被编码和传输。
///
/// 新增传输层只需：
/// 1. 实现本接口的 open / sendFrame / close / dispose
/// 2. 构造时传入 [CanTransportConfig] 的对应实现
/// 3. 通过 [CanTransportRegistry.register] 注册工厂
///
/// 收到的 CAN 帧通过 [onFrame] 回调（参数为已解析的 [CanFrame]），
/// 传输层内部负责原始字节 → 帧解析（如 SLCAN 的 ASCII 行解析）。
abstract class CanTransport {
  const CanTransport();

  /// 传输层类型标识（如 `'slcan'`、`'pcan'`、`'kvaser'`）。
  String get transportType;

  /// 传输层简介，用于 UI 展示。
  String get transportLabel;

  /// 是否已打开（可以收发）。
  bool get isOpen;

  /// 打开适配器并开始收发。
  ///
  /// [config] 中 [CanTransportConfig.portName] 表示适配器标识（如串口名 / PCAN 通道号），
  /// [CanTransportConfig.canBitrate] 是 CAN 总线波特率，
  /// [CanTransportConfig.rawConfig] 携带传输层特有的参数（如 PCAN 的 USB 设备索引）。
  ///
  /// [onFrame] 每收到一帧完整 CAN 数据时回调，传入已解析的 [CanFrame]。
  /// [onError] 在连接致命错误（如设备拔出、驱动初始化失败）时回调。
  Future<void> open({
    required CanTransportConfig config,
    required void Function(CanFrame frame) onFrame,
    required void Function(Object error) onError,
  });

  /// 发送一帧 CAN 数据。
  ///
  /// 传输层负责将 [frame] 编码为对应协议的原始字节（如 SLCAN 的 ASCII 命令、
  /// PCAN 的 PCANBasic 调用）。返回成功写出的字节数（或帧计数，用于统计）。
  Future<int> sendFrame(CanFrame frame);

  /// 关闭适配器，释放全部资源。可重复调用。
  Future<void> close();

  /// 彻底释放（如 FFI isolate / native handle）。dispose 后不可再 open。
  Future<void> dispose();
}

/// 传输层配置：通用字段 + 传输层特有字段。
class CanTransportConfig {
  const CanTransportConfig({
    required this.transportType,
    required this.portName,
    required this.canBitrate,
    this.rawConfig = const {},
  });

  /// 传输层类型，对应 [CanTransport.transportType]。
  final String transportType;

  /// 适配器标识（如 `COM5`、`PCAN-USB1`）。
  final String portName;

  /// CAN 总线波特率（SLCAN 的 S0~S9、PCAN 的枚举等）。
  final CanBitrate canBitrate;

  /// 传输层特有的参数（如 PCAN 的 USB 设备索引、Kvaser 的通道号）。
  final Map<String, dynamic> rawConfig;

  CanTransportConfig copyWith({
    String? transportType,
    String? portName,
    CanBitrate? canBitrate,
    Map<String, dynamic>? rawConfig,
  }) {
    return CanTransportConfig(
      transportType: transportType ?? this.transportType,
      portName: portName ?? this.portName,
      canBitrate: canBitrate ?? this.canBitrate,
      rawConfig: rawConfig ?? this.rawConfig,
    );
  }

  Map<String, dynamic> toJson() => {
        'transportType': transportType,
        'portName': portName,
        'canBitrate': canBitrate.name,
        'rawConfig': rawConfig,
      };

  factory CanTransportConfig.fromJson(Map<String, dynamic> json) {
    return CanTransportConfig(
      transportType: json['transportType'] as String? ?? 'slcan',
      portName: json['portName'] as String? ?? '',
      canBitrate: CanBitrate.values.firstWhere(
        (e) => e.name == json['canBitrate'],
        orElse: () => CanBitrate.speed500K,
      ),
      rawConfig: Map<String, dynamic>.from(json['rawConfig'] as Map? ?? {}),
    );
  }
}

typedef CanTransportFactory = CanTransport Function();

/// 传输层工厂注册表。
///
/// 新增传输层：`CanTransportRegistry.register('myprotocol', () => MyTransport(), availableAdapters: () async => ['COM5'])`。
/// 连接对话框通过 [CanTransportRegistry.create] 按类型创建实例。
class CanTransportRegistry {
  CanTransportRegistry._();

  static final _registry = CanTransportRegistry._();

  final Map<String, _CanTransportEntry> _entries = {};

  /// 注册传输层工厂。覆盖已注册的同类型。
  ///
  /// [availableAdapters] 可选，提供系统当前可用的适配器列表。
  /// 返回空列表或 null 时连接对话框会隐藏适配器下拉框。
  static void register(
    String type,
    CanTransportFactory factory, {
    required String label,
    List<String> Function()? availableAdapters,
  }) {
    _registry._entries[type] =
        _CanTransportEntry(type, factory, label, availableAdapters);
  }

  /// 按类型创建传输层实例。未知类型抛出 [StateError]。
  static CanTransport create(String type) {
    final entry = _registry._entries[type];
    if (entry == null) {
      throw StateError(
        '未知传输层类型 "$type"，已注册：${_registry._entries.keys.join(', ')}',
      );
    }
    return entry.factory();
  }

  /// 已注册的传输层类型列表。
  static List<String> get registeredTypes =>
      List.unmodifiable(_registry._entries.keys);

  /// 已注册传输层的类型 + 标签映射（用于 UI 下拉框）。
  static List<(String type, String label)> get registeredOptions {
    return _registry._entries.values
        .map((e) => (e.type, e.label))
        .toList();
  }

  /// 查询指定传输层的可用适配器列表（如 SLCAN 返回串口列表）。
  static List<String> getAvailableAdapters(String type) {
    final entry = _registry._entries[type];
    if (entry == null || entry.availableAdapters == null) {
      return const [];
    }
    try {
      return entry.availableAdapters!();
    } catch (_) {
      return const [];
    }
  }

  /// 查询指定传输层是否可用（驱动加载成功、硬件存在）。
  static bool isTypeAvailable(String type) {
    final entry = _registry._entries[type];
    if (entry == null) return false;
    return true; // 只要注册了就认为可用；硬件检测在连接时
  }
}

class _CanTransportEntry {
  _CanTransportEntry(this.type, this.factory, this.label, this.availableAdapters);
  final String type;
  final CanTransportFactory factory;
  final String label;
  final List<String> Function()? availableAdapters;
}
