# USB 调试模块开发计划

## Context

项目已实现串口、网络、Modbus、蓝牙（BLE）四个调试模块，均通过 `DebugFeature` 接口注册。用户要求开发 USB 调试模块，经确认需要同时支持：

1. **USB HID 设备**：设备枚举过滤、Input/Output/Feature Report 收发、报告描述符解析、热插拔检测
2. **通用 USB（libusb 裸传输）**：设备枚举、接口认领、Bulk IN/OUT 传输、连续接收轮询

USB CDC 虚拟串口（CH340/CP2102/FT232 等）在 Windows 上枚举为 COM 口，已由现有串口模块覆盖，本模块不重复。

技术选型：
- HID：`hid_tool: ^0.1.3`（hidapi 0.15 FFI，Windows 自动编译，维护活跃，3 周前更新）
- 通用 USB：`quick_usb: ^0.4.0`（libusb FFI 封装，插件自动打包 libusb-1.0.dll，支持 Windows bulk 传输；包虽 4 年未更新但 API 稳定可用）

**Windows 使用前提**（UI 中给出提示）：通用 USB 模式要求设备驱动为 WinUSB（可用 Zadig 替换）；HID 设备使用系统自带 HID 驱动，无需额外配置。

**quick_usb 限制**：其高层 API 全局只允许打开一个设备句柄（openDevice/closeDevice 无句柄返回），因此通用 USB 会话同时只允许 1 个；HID 会话最多 4 个。

## 依赖

- `hid_tool: ^0.1.3`
- `quick_usb: ^0.4.0`（传递依赖 libusb 0.3.23+2 / ffi 1.x，pub get 时验证与现有依赖无冲突）

## 文件清单

### domain 层
- `lib/features/usb/domain/usb_device_info.dart` — 统一设备模型 `UsbDeviceInfo`：`UsbDeviceKind { hid, raw }`、kind、id（HID 用 path，raw 用 identifier）、vid/pid/manufacturer/product/serial、usagePage/usage（HID）、`displayName`、`vidPidHex`（如 `04D8:FC00`）、toJson/fromJson/按 id 判等
- `lib/features/usb/domain/usb_session_base.dart` — 抽象基类 `UsbSessionBase extends ChangeNotifier implements SendPanelController`，抽取两个会话的公共逻辑（仿 [ble_session.dart](lib/features/bluetooth/domain/ble_session.dart)）：
  - logs / rxBytes / txBytes / clearLogs / maxLogEntries=5000
  - 接收静默判帧（30ms / 4096B / 200ms 常量与串口一致）
  - sendAsHex / lineEnding / loopIntervalMs / loopSending / startLoopSend / stopLoopSend
  - 抽象 `FutureOr<void> writeBytes(Uint8List bytes)`，由子类实现
  - 状态、lastError、appendReceiveLog/appendSystemLog
- `lib/features/usb/domain/hid_usb_session.dart` — `HidUsbSession extends UsbSessionBase`：
  - 持有 hid_tool 的 `HidDevice`；open/close、isConnected
  - `int reportId = 0`（发送 Output Report 的 Report ID，UI 可调）
  - writeBytes → `device.sendReport(bytes, reportId: reportId)`（hidapi 自动前缀 Report ID，按设备报告长度补零由调用方负责，不做隐式截断）
  - 打开后通过 `device.inputStream()` 监听 Input Report 进入静默判帧（实现时先读包源码确认流元素类型；若不可用则降级为 receiveReport 短超时循环）
  - `readFeatureReport(reportId, bufferSize)` / `writeFeatureReport(bytes, reportId)` → 结果写入日志
  - `Future<HidReportDescriptor> loadReportDescriptor()` 供描述符对话框使用
- `lib/features/usb/domain/raw_usb_session.dart` — `RawUsbSession extends UsbSessionBase`：
  - 持有 `UsbDevice`；openDevice → getConfiguration(0) 解析接口/端点树（暴露 `List<RawEndpointInfo>`：interfaceId、address、direction、maxPacketSize、attributes 传输类型）
  - claimInterface/releaseInterface（选择接口时自动 claim，支持接口切换）
  - 选定 OUT 端点后 writeBytes → `QuickUsb.bulkTransferOut(ep, bytes, timeout: timeoutMs)`
  - IN 连续接收：Timer 周期调用 `QuickUsb.bulkTransferIn(ep, readSize, timeout)`，可配 readSize（默认 64）、轮询间隔（默认 10ms）、超时（默认 100ms）；空数据不上屏；异常时停止轮询并标记断开
  - 单次"手动读一次"按钮
  - closeDevice 时 releaseInterface + closeDevice
- `lib/features/usb/domain/usb_session_manager.dart` — `extends ChangeNotifier implements QuickCommandStore`（仿 [ble_session_manager.dart](lib/features/bluetooth/domain/ble_session_manager.dart)）：
  - `QuickUsb.init()` 在 create() 中执行一次
  - 枚举：`enumerate()` 合并 HID 列表（`Hid.getDevices()` → UsbDeviceInfo）与 raw 列表（`QuickUsb.getDevicesWithDescription()`），按 id 去重；raw 枚举失败（无 WinUSB 设备/DLL 异常）不影响 HID 列表，错误在 raw 标签页内提示
  - 热插拔：`Hid.startListening()` + `HidDeviceEvents.onConnected/onDisconnected` 驱动刷新；另设 2 秒轮询兜底 raw 设备变更
  - openHidSession / openRawSession；maxSessions=4；raw 会话全局最多 1 个（占用时其余 raw 项禁用并提示）；busyIds
  - 快捷指令 + 发送历史（与其它模块同构，key 前缀 usb_）

### data 层
- `lib/features/usb/data/usb_store.dart` — 仿 [ble_store.dart](lib/features/bluetooth/data/ble_store.dart)：`usb_quick_commands` / `usb_send_history` / `usb_last_hid_device` / `usb_last_raw_device`

### presentation 层
- `lib/features/usb/presentation/usb_feature.dart` — `DebugFeature`：id='usb'，紫色 0xFF6C5CE7，Icons.usb；FutureBuilder 装配 manager（仿 bluetooth_feature.dart）
- `lib/features/usb/presentation/usb_page.dart` — AppBar（刷新枚举 + 新建连接）；空态引导；TiledLayout 多会话平铺（仿 bluetooth_page.dart）
- `lib/features/usb/presentation/widgets/device_picker_dialog.dart` — 顶部 SegmentedButton 切换「HID 设备 / 通用 USB」；设备列表显示 displayName + `VID:PID` + 厂商/序列号 + 信号无关信息；名称过滤；raw 标签页顶部黄色提示条「需先用 Zadig 将设备驱动替换为 WinUSB」；已占用设备禁用；raw 已有会话时其它 raw 项禁用
- `lib/features/usb/presentation/widgets/hid_session_view.dart` — 状态栏（仿 BLE SessionView）+ HID 工具条（Report ID 数字框 0-255、Feature Report 读/写按钮、报告描述符按钮、发送方式 sendReport/sendOutputReport 切换）+ ReceivePanel + SendPanel（disconnectedHint='请先打开 HID 设备'）。Feature 写用简单对话框输入 HEX + Report ID
- `lib/features/usb/presentation/widgets/raw_usb_session_view.dart` — 状态栏 + 端点配置面板（可折叠，约 200px）：接口/端点树形列表（标注 Bulk/Interrupt/IN/OUT、地址 0x81 形式、maxPacketSize），点 OUT 端点设为发送目标、点 IN 端点设为接收目标；"开始连续接收"开关 + readSize/间隔/超时输入；"读一次"按钮；其下 ReceivePanel + SendPanel（HEX 模式默认）
- `lib/features/usb/presentation/widgets/report_descriptor_dialog.dart` — 展示 HID 报告描述符：原始字节 HEX + 解析表（Input/Output/Feature 分组，列出 ReportId / UsagePage / ReportSize / ReportCount / logicalMin-Max）+ Collection 树文本

### 注册与测试
- [lib/core/bootstrap.dart](lib/core/bootstrap.dart) 添加 `..register(UsbFeature())`
- [test/widget_test.dart](test/widget_test.dart) 增加 `expect(find.text('USB 调试'), findsOneWidget)`
- `test/usb_test.dart`：
  - UsbDeviceInfo toJson/fromJson 往返、vidPidHex 格式化（0x04d8/0xfc00 → `04D8:FC00`）、displayName 回退、按 id 判等
  - UsbStore 快捷指令/历史/lastDeviceId round-trip（`SharedPreferences.setMockInitialValues({})`）

## 关键实现注意

1. **hid_tool API**（已核对）：`Hid.getDevices({vendorId,productId,usagePage,usage})`；`HidDevice` 字段 path/vendorId/productId/serialNumber/manufacturer/productName/usagePage/usage/interfaceNumber；`open/close/sendReport(data,{reportId})/sendOutputReport/receiveReport(len,{timeout})/inputStream()/sendFeatureReport/receiveFeatureReport(rid,bufferSize:)/getReportDescriptor()`；热插拔 `Hid.startListening()` + `HidDeviceEvents.onConnected/onDisconnected`（事件含 path/vendorId/productId，300ms 原生去抖）；异常类型 `HidException`
2. **quick_usb API**（已核对）：`QuickUsb.init/exit/getDeviceList/getDevicesWithDescription/openDevice(device)/closeDevice/getConfiguration(0)/claimInterface(iface)/releaseInterface/bulkTransferIn(endpoint,len,{timeout})→Uint8List/bulkTransferOut(endpoint,data,{timeout})→int`；`UsbConfiguration.interfaces[].endpoints[]`，端点有 `endpointAddress/direction(UsbEndpoint.DIRECTION_IN/OUT)/maxPacketSize`；全局单设备句柄 → raw 会话限 1 个
3. 两个会话都实现 SendPanelController 复用 SendPanel；Report ID / 端点选择等特有控件放在各自视图的工具条中，不改共享 SendPanel
4. 日志统一 DebugLogEntry；原始报文走 ReceivePanel 的 HEX 视图；Feature Report / Bulk 读写用 source 标签区分（如 `FEATURE RID=01`、`BULK IN 0x81`）
5. Windows 构建：hidapi 随 hid_tool 自动编译；quick_usb 自带 libusb-1.0.dll 打包。若遇 C4819 警告被当错误（代码页 936，与 universal_ble 相同问题），给两个插件 windows/CMakeLists.txt 追加 `target_compile_options(... PRIVATE "/utf-8")`；插件路径 `windows/flutter/ephemeral/.plugin_symlinks/<pkg>/windows/CMakeLists.txt`

## 验证

1. `flutter pub get` 无依赖冲突
2. `flutter analyze` — 零问题
3. `flutter test` — 全部通过（含新增 usb_test.dart）
4. `flutter build windows --debug` — 构建成功（必要时修补插件 CMake 的 /utf-8）
5. 启动冒烟：进程稳定运行、主页显示"USB 调试"入口
6. 有设备时手动验证：HID 枚举→打开→Output Report 发送/Input Report 接收/描述符查看；raw USB（Zadig 后）枚举→claim→bulk 收发
