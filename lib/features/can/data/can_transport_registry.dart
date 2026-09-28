import '../data/slcan_transport.dart';
import '../domain/can_transport.dart';

/// CAN 传输层注册入口。
///
/// 在 CAN 模块初始化（CanFeature / CanOpenFeature 首次加载）时调用，
/// 将 [SlcanTransport] 注册为可用的 CAN 传输层。
///
/// 新增传输层（如 PCAN / Kvaser）时在此文件追加一行即可：
/// ```dart
/// CanTransportRegistry.register(
///   'pcan', () => PcanTransport(),
///   label: 'PCAN-USB（PEAK 系统）',
///   availableAdapters: () => PcanTransport.availableAdapters,
/// );
/// ```
void registerCanTransports() {
  CanTransportRegistry.register(
    'slcan',
    () => SlcanTransport(),
    label: 'SLCAN 串口（Lawicel 协议）',
    availableAdapters: () => SlcanTransport.availableAdapters,
  );
}
