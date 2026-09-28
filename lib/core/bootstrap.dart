import '../features/bluetooth/presentation/bluetooth_feature.dart';
import '../features/can/presentation/can_feature.dart';
import '../features/canopen/presentation/canopen_feature.dart';
import '../features/modbus/presentation/modbus_feature.dart';
import '../features/mqtt/presentation/mqtt_feature.dart';
import '../features/network/presentation/network_feature.dart';
import '../features/serial/presentation/serial_feature.dart';
import '../features/usb/presentation/usb_feature.dart';
import 'feature/feature_registry.dart';

/// 构建功能注册表。
///
/// === 如何扩展新功能 ===
/// 实现 `DebugFeature` 接口后，在此处添加一行：
///   registry.register(TcpDebugFeature());
/// 主页将自动出现对应入口。
FeatureRegistry buildFeatureRegistry() {
  return FeatureRegistry()
    ..register(SerialFeature())
    ..register(NetworkFeature())
    ..register(ModbusFeature())
    ..register(BluetoothFeature())
    ..register(UsbFeature())
    ..register(MqttFeature())
    ..register(CanFeature())
    ..register(CanOpenFeature());
  }


