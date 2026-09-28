/// 扫描发现的 BLE 设备信息（UI 层使用，从 universal_ble 的 BleDevice 转换）。
///
/// 与 `package:universal_ble` 的 `BleDevice` 解耦：domain 层不直接依赖
/// 第三方类型，便于测试与跨层传递。
class BleDeviceInfo {
  const BleDeviceInfo({
    required this.deviceId,
    this.name,
    this.rssi,
  });

  /// 系统分配的设备唯一标识（平台相关：mac/uuid 等）。
  final String deviceId;

  /// 设备广播名（可能为空）。
  final String? name;

  /// 最近一次扫描时的信号强度（dBm，可能为空）。
  final int? rssi;

  /// UI 显示名：优先使用广播名，否则退回 deviceId。
  String get displayName => (name != null && name!.isNotEmpty) ? name! : deviceId;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'rssi': rssi,
      };

  factory BleDeviceInfo.fromJson(Map<String, dynamic> json) => BleDeviceInfo(
        deviceId: json['deviceId'] as String? ?? '',
        name: json['name'] as String?,
        rssi: (json['rssi'] as num?)?.toInt(),
      );

  BleDeviceInfo copyWith({
    String? deviceId,
    String? name,
    int? rssi,
  }) =>
      BleDeviceInfo(
        deviceId: deviceId ?? this.deviceId,
        name: name ?? this.name,
        rssi: rssi ?? this.rssi,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BleDeviceInfo && other.deviceId == deviceId);

  @override
  int get hashCode => deviceId.hashCode;
}
