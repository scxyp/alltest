# debug_assistant — 多功能调试助手

一款基于 Flutter 的 Windows 桌面调试工具，面向嵌入式 / 物联网 / 工控开发场景，集成串口调试、网络调试、Modbus 协议模拟、蓝牙调试、USB 调试、MQTT 调试、CAN 调试与 CANopen 调试八大功能模块。采用可扩展的功能注册架构，新增调试工具只需实现 `DebugFeature` 接口并在 `bootstrap.dart` 中注册一行即可。

### 模块概览

| # | 模块 | 传输方式 | 典型硬件 | 最大并行 | 核心协议 |
|---|------|----------|----------|----------|----------|
| 1 | 串口调试 | UART | USB 转串口（CH340/CP2102/FT232） | 4 | — |
| 2 | 网络调试 | TCP / UDP | 网卡 | 4 | — |
| 3 | Modbus 模拟器 | 串口 RTU / 网口 TCP | 串口 / 网卡 | 4 | Modbus FC1~FC16 |
| 4 | 蓝牙调试 | BLE | 内置蓝牙适配器 / USB BLE 适配器 | 4 | GATT |
| 5 | USB 调试 | HID / WinUSB / libusb | HID 设备 / 通用 USB 设备 | 4 | HID Report / Bulk |
| 6 | MQTT 调试 | TCP / TLS | 网络 | 4 | MQTT 3.1.1/5.0 |
| 7 | CAN 调试 | 传输层插件化（默认 SLCAN） | CANable / Lawicel / ESP32 / PCAN-USB / Kvaser | 4 | CAN 2.0B |
| 8 | CANopen 调试 | 传输层插件化 + CANopen | 同 CAN（需要目标 CANopen 节点） | 4 | CANopen SDO/NMT/PDO |

> CANopen 模块底层完全复用 CAN 模块的传输层抽象（`CanTransport` 接口），两者可共享同一个物理适配器但需要独立的会话实例。
> 传输层插件化：新增 USB-CAN 协议（如 PCAN-USB、Kvaser、自研 DLL）只需实现 `CanTransport` 接口并注册到 `CanTransportRegistry`，CAN / CANopen 会话代码零改动。

## 功能模块

### 1. 串口调试（Serial）

- **多串口并行连接**：最多同时打开 4 个串口会话，以标签页形式切换，互不干扰
- **完整串口参数配置**：端口、波特率（默认 115200）、数据位（5-8）、校验（None/Odd/Even/Mark/Space）、停止位（1/1.5/2）、流控（None/XON-XOFF/RTS-CTS/DTR-DSR）
- **HEX / 文本双模式收发**：发送支持 HEX 格式输入（如 `AA BB 01`）或 UTF-8 文本，可附加行结束符（无 / CR / LF / CRLF）
- **循环发送**：按设定间隔（默认 1000ms）自动重复发送当前输入内容
- **快捷指令**：可保存常用发送内容为快捷指令，跨会话共享，支持增删改
- **发送历史**：自动记录最近 30 条发送内容，去重排序，一键重发
- **接收静默判帧**：收到数据后等待 30ms 静默再上屏，避免一帧数据被逐字符显示；连续数据流按 4096 字节或 200ms 上限切分
- **设备热插拔检测**：轮询系统端口列表，串口设备被拔出时自动标记会话断开
- **日志导出**：可将接收 / 发送日志导出为文件
- **收发字节统计**：实时显示 RX / TX 字节数

### 2. 网络调试（Network）

- **三模式合一**：TCP 客户端、TCP 服务端、UDP 收发
- **多会话并行**：最多同时打开 4 个网络会话，标签页切换
- **TCP 客户端**：连接指定远程主机和端口，可选绑定本地网卡
- **TCP 服务端**：监听本地端口，支持多客户端同时接入，可向指定客户端或全部客户端发送数据
- **UDP**：绑定本地端口收发，支持广播模式发送，接收数据带对端地址标记
- **网卡自动识别**：枚举本机所有网卡的 IPv4 地址，供连接对话框选择
- **HEX / 文本双模式收发**：与串口模块一致
- **循环发送**：按固定间隔自动重复发送
- **快捷指令与发送历史**：与串口模块共享一致的交互
- **接收静默判帧**：解决 TCP 粘包 / 分片显示问题，按来源分别成帧
- **日志导出与字节统计**

### 3. Modbus 模拟器

支持 Modbus RTU（串口）与 Modbus TCP（网口）两种传输方式，主机和从机可独立运行。

#### 主机（Master）

- **连接管理**：RTU 模式使用串口通道，TCP 模式连接指定 IP 和端口（默认 502）
- **轮询表**：维护多条轮询请求项，每条可配置名称、从机地址（Unit ID 1-247）、功能码、起始地址、数量 / 写入值、启用开关
- **轮询调度**：按设定间隔（默认 1000ms）自动依次执行所有启用的轮询项
- **单次执行**：可手动执行单条轮询项
- **事务匹配**：RTU 按从机地址 + 功能码匹配响应，TCP 按事务 ID（Transaction ID）匹配；串行执行避免事务交叉
- **超时处理**：可配置响应超时时间（默认 1000ms），超时后记录错误并继续
- **RTU 广播**：从机地址为 0 且为写操作时以广播方式发送，不等待响应
- **结果显示**：读线圈 / 离散输入以位矩阵展示（带地址标注），读寄存器以 HEX / 有符号 / 无符号数值列表展示，写操作显示回显信息
- **异常响应**：解析从机返回的异常响应（功能码 | 0x80 + 异常码），显示对应异常含义
- **原始报文**：完整收发报文以 HEX 形式展示在报文面板

#### 从机（Slave）

- **连接管理**：RTU 模式监听串口（按从机地址过滤，支持广播地址 0），TCP 模式监听指定端口，逐连接处理
- **四区寄存器**：
  - 线圈（Coils，FC1 读 / FC5,15 写，位，默认 1000 点）
  - 离散输入（Discrete Inputs，FC2 只读，位，默认 1000 点）
  - 保持寄存器（Holding Registers，FC3 读 / FC6,16 写，uint16，默认 1000 点）
  - 输入寄存器（Input Registers，FC4 只读，uint16，默认 1000 点）
- **在线编辑**：运行时可直接在表格中编辑四区寄存器值，线圈区以开关切换，寄存器区支持 HEX / DEC 显示
- **请求处理**：自动解析请求 PDU，查表生成响应；地址越界返回异常码 0x02，数量超限返回 0x03，非法功能码返回 0x01
- **广播处理**：广播地址 0 仅接受写操作，不返回响应
- **收发统计**：记录请求 / 响应计数
- **原始报文**：完整收发 ADU（含地址 / CRC / MBAP 头）以 HEX 形式展示

#### 支持的功能码

| 功能码 | 名称 | 主机 | 从机 |
|--------|------|------|------|
| 0x01 (FC1) | 读线圈 | 支持 | 支持 |
| 0x02 (FC2) | 读离散输入 | 支持 | 支持 |
| 0x03 (FC3) | 读保持寄存器 | 支持 | 支持 |
| 0x04 (FC4) | 读输入寄存器 | 支持 | 支持 |
| 0x05 (FC5) | 写单个线圈 | 支持 | 支持 |
| 0x06 (FC6) | 写单个寄存器 | 支持 | 支持 |
| 0x0F (FC15) | 写多个线圈 | 支持 | 支持 |
| 0x10 (FC16) | 写多个寄存器 | 支持 | 支持 |

#### 协议实现细节

- **CRC-16**：多项式 0xA001，初始值 0xFFFF，低字节在前追加（已用权威 check value "123456789" → 0x4B37 验证）
- **RTU 分帧**：按 3.5 字符静默间隔分帧（每字符 11 bit，间隔 = 3.5 × 11 × 1000 / 波特率，钳制 16-100ms），CRC 校验失败的帧静默丢弃
- **TCP MBAP 分帧**：按 MBAP 头 length 字段处理粘包 / 半包
- **数量校验**：读位 ≤ 2000、读寄存器 ≤ 125、写线圈 ≤ 1968、写寄存器 ≤ 123

### 4. 蓝牙调试（Bluetooth BLE）

基于 `universal_ble` 包实现 BLE（低功耗蓝牙）设备调试，支持 Windows 桌面。

- **设备扫描**：实时搜索附近 BLE 设备，显示设备名称、地址、RSSI 信号强度（按强度着色），支持名称过滤，已连接设备自动标记
- **多设备并行连接**：最多同时连接 4 个 BLE 设备，以平铺方式同时展示，互不干扰
- **GATT 服务 / 特征浏览**：连接后自动发现 GATT 服务树，以可折叠列表展示，每个特征标注权限图标（可读 / 可写 / 可 Notify）
- **特征读写**：
  - **写**：选择可写特征作为发送目标，支持有响应（Write with Response）与无响应（Write without Response）两种模式，根据特征属性自动判断
  - **读**：对可读特征执行单次读取，结果直接写入日志面板
- **Notify / Indicate 订阅**：一键订阅或取消订阅 Notify / Indicate 特征，订阅期间持续接收数据并写入日志面板
- **HEX / 文本双模式收发**：与串口模块一致，支持 HEX 格式输入或 UTF-8 文本
- **循环发送**：按固定间隔自动重复发送
- **快捷指令与发送历史**：与串口模块共享一致的交互
- **接收静默判帧**：Notify 数据采用 30ms 静默判帧合并，避免一帧被逐包显示
- **自动选特征**：连接后自动选择第一个可写特征作为默认发送目标
- **连接状态监听**：自动检测对端断开，断开时停止循环发送、取消所有订阅
- **日志导出与字节统计**

### 5. USB 调试

支持 HID 设备与通用 USB 设备（WinUSB/libusb）两种通道，基于 `hid_tool` + 自研 libusb FFI 绑定实现。

#### HID 通道

- **设备枚举**：扫描系统 HID 设备，显示厂商 ID / 产品 ID / 产品名 / 路径
- **多设备并行**：最多同时打开 4 个 HID 设备会话
- **Report 收发**：
  - **Output Report**：向设备发送输出报告（Report ID + 数据）
  - **Input Report**：持续读取设备输入报告并写入日志
  - **Feature Report**：读写设备特征报告
- **热插拔检测**：定时轮询设备列表，设备被拔出时自动标记会话断开
- **Report Descriptor 解析**：可查看设备报告描述符的原始字节
- **HEX / 文本双模式收发**：与串口模块一致
- **循环发送、快捷指令、发送历史、日志导出**

#### 通用 USB 通道（Raw USB）

- **libusb FFI 绑定**：自研 14 函数的 libusb FFI 绑定（ffi 2.x，ABI 稳定），避免 `quick_usb` 的 ffi 版本冲突
- **Bulk 传输**：自动选择 Bulk 接口，管理 IN/OUT 端点
- **Isolate 隔离**：libusb 操作在独立 isolate 中执行，避免阻塞 UI
- **设备选择**：按 VID/PID 或总线路径选择设备
- **HEX / 文本收发、循环发送、快捷指令、发送历史、日志导出**

#### 原生依赖

- `hidapi.dll`（HID 通道，由 `hid_tool` 提供）
- `libusb-1.0.dll`（通用 USB 通道，官方 1.0.23 x64，放置于 `windows/libs/x64/`，由 CMakeLists 配置复制到输出目录）

### 6. MQTT 调试

基于 `mqtt_client` 包实现的 MQTT 客户端，支持与 MQTT Broker 的连接、订阅、发布。

- **多 Broker 并行连接**：最多同时打开 4 个 MQTT 会话，平铺展示
- **连接参数**：
  - Broker 地址 / 端口（默认 1883，TLS 时默认 8883）
  - ClientId（可空，空时自动生成）
  - 用户名 / 密码（可空，匿名连接）
  - KeepAlive 心跳间隔（默认 60s）
  - TLS 加密开关
- **遗嘱消息（Last Will）**：可配置遗嘱主题、负载、QoS、Retain 标志
- **订阅管理**：
  - 支持主题过滤器（通配符 `+` / `#`）
  - 每条订阅可选 QoS 0 / 1 / 2
  - 订阅列表以 Chip 形式展示，可一键退订
  - 订阅面板可折叠
- **发布**：
  - 发布主题、QoS、Retain 作为会话级属性
  - 支持 HEX / 文本双模式发布负载
- **消息接收**：MQTT 消息离散到达，无需静默判帧，直接上屏并标注来源主题
- **QoS 等级**：0（最多一次）/ 1（至少一次）/ 2（恰好一次）
- **循环发送、快捷指令、发送历史、日志导出与字节统计**
- **断线检测**：Broker 主动断开时自动标记会话断开，停止循环发送

### 7. CAN 调试

传输层插件化架构，默认使用 SLCAN（Lawicel）串口协议，支持 CANable / Lawicel CANUSB / ESP32 等适配器；未来可扩展 PCAN-USB、Kvaser、自研 USB-CAN 协议——会话代码零改动。

- **多适配器并行连接**：最多同时打开 4 个 CAN 会话
- **传输层插件化架构**：
  - `CanTransport` 抽象接口（`open` / `sendFrame` / `close` / `dispose`）
  - `CanTransportRegistry` 工厂注册表（按类型名创建实例）
  - `SlcanTransport`：SLCAN 串口协议实现（15ms 非阻塞轮询 + CR 分帧）
  - 连接对话框自动列出已注册的传输层，选 SLCAN 时显示串口参数，选 PCAN-USB 时显示通道号
- **连接参数**：
  - 传输层类型（默认 SLCAN，未来可扩展 PCAN-USB / Kvaser / 自研）
  - 适配器标识（SLCAN 时为串口名如 `COM5`，PCAN-USB 时为通道号）
  - 传输层特有参数（如 SLCAN 的串口波特率 115200）
  - CAN 总线波特率（S0~S9 预设：10K / 20K / 50K / 100K / 125K / 250K / 500K / 800K / 1M / 83.3K）
- **SLCAN 协议**：
  - 连接初始化序列：`C\r`（清理）→ `S<n>\r`（设置波特率）→ `O\r`（打开 CAN 通道）
  - 断开时发送 `C\r`（关闭 CAN 通道）
  - 适配器成功 ACK（CR）忽略，错误 ACK（BEL）记为系统消息
- **CAN 帧收发**：
  - **标准帧**（11-bit ID）/ **扩展帧**（29-bit ID）
  - **数据帧**（0~8 字节）/ **远程帧**（无数据，请求数据）
  - 发送编码：`t` + 3hexID + DLC + hexData + `\r`（标准数据帧）
  - 发送编码：`T` + 8hexID + DLC + hexData + `\r`（扩展数据帧）
  - 远程帧：`r` / `R` + ID + DLC + `\r`（无数据部分）
- **帧属性**：帧 ID / 扩展帧 / 远程帧为会话级属性（类似 MQTT 发布主题）
- **接收**：传输层按协议解析原始数据为 [CanFrame] 上屏，日志标注帧 ID（如 `ID:0x123`）
- **HEX / 文本双模式**：`sendAsHex` 默认 true（CAN 数据为二进制），`lineEnding` 默认 none
- **循环发送、快捷指令、发送历史、日志导出与字节统计**
- **设备热插拔检测**：轮询端口列表，适配器被拔出时自动标记断开

### 8. CANopen 调试

基于 CAN 模块的传输层抽象（`CanTransport` 接口），在 CAN 之上实现 CANopen 协议层。传输层可以是 SLCAN 串口协议（默认）、PCAN-USB、Kvaser 或自研 DLL——CANopen 会话代码零改动。

- **多适配器并行连接**：最多同时打开 4 个 CANopen 会话
- **连接参数**：
  - 传输层类型（同 CAN 模块）
  - 适配器标识 + 传输层特有参数
  - CAN 总线波特率（S0~S9 预设）
  - CANopen 目标 Node ID（1~127）
- **底层复用**：CANopen 模块直接依赖 `CanTransport` 接口，通过 `CanTransportRegistry` 创建实例，与 CAN 会话共享同一套传输层实现
- **CANopen 帧路由**：接收侧按 COB-ID 前缀自动分发：
  - `0x700+NID` → Heartbeat 节点状态（Operational / Pre-Op / Stopped / Boot-up）
  - `0x580+NID` → SDO 响应（匹配待处理的 SDO 请求）
  - `0x100+NID` → EMCY 紧急帧
  - `0x080` → SYNC 帧（广播，空数据）
  - `0x180+NID / 0x200+NID / 0x280+NID / 0x300+NID` → PDO1~PDO4 过程数据帧
- **SDO Expedited 传输**（≤4 字节，单帧完成）：
  - **读取**：输入 Index（4位HEX）、Subindex（2位HEX），点击"读取"后解析响应并填入数据字段
  - **写入**：输入 Index、Subindex、数据（HEX，≤4 字节），点击"写入"后发送
  - 命令码自动按数据长度选择：0x23（4字节）/ 0x2B（3字节）/ 0x2F（2字节）/ 0x27（1字节）
  - 响应超时 2s，超时记录错误；Abort 响应自动解码错误码含义（28 种标准错误码）
- **SDO Segmented 传输**（>4 字节）：暂不支持，检测到后提示"数据过长"
- **NMT 节点控制**：
  - **Start**（0x01）：进入 Operational 状态
  - **Stop**（0x02）：进入 Stopped 状态
  - **Pre-Op**（0x80）：进入 Pre-Operational 状态
  - **Reset**（0x81）：复位节点（恢复 Boot-up）
  - **Reset Comm**（0x82）：仅复位通信参数
  - 默认发往会话配置的 Node ID，可改目标
- **Heartbeat 状态表**：自动记录各节点最近一次 Heartbeat 的时间和状态
- **帧 ID 属性**：默认指向 SDO Request COB-ID（0x600 + Node ID），可改用于自定义发送
- **HEX / 文本双模式、循环发送、快捷指令、发送历史、日志导出与字节统计**

## 持久化

所有配置与数据通过 SharedPreferences 本地持久化：

- 串口 / 网络模块：上次连接参数、快捷指令、发送历史
- Modbus 模块：主机连接参数与轮询表即时保存，从机连接参数即时保存，寄存器 500ms 防抖保存
- 蓝牙模块：上次连接设备 ID、快捷指令、发送历史
- USB 模块：快捷指令、发送历史
- MQTT 模块：上次连接参数、快捷指令、发送历史
- CAN 模块：上次连接参数、快捷指令、发送历史
- CANopen 模块：上次连接参数、快捷指令、发送历史

## 架构

```
lib/
├── core/                          # 框架层
│   ├── feature/
│   │   ├── debug_feature.dart       # DebugFeature 接口定义
│   │   └── feature_registry.dart    # 功能注册表
│   ├── bootstrap.dart               # 功能注册入口（新增模块仅改此文件）
│   ├── ui/
│   │   ├── receive_panel.dart       # 通用接收 / 报文面板（HEX/文本切换、导出、自动滚动）
│   │   ├── send_panel.dart          # 通用发送面板（HEX/文本、循环发送、快捷指令、历史）
│   │   ├── quick_command.dart       # 快捷指令模型
│   │   ├── quick_command_strip.dart  # 快捷指令快捷栏
│   │   ├── quick_command_dialog.dart # 快捷指令编辑对话框
│   │   ├── send_contracts.dart       # 发送面板控制器接口
│   │   ├── line_ending.dart          # 行结束符枚举
│   │   ├── debug_log_entry.dart      # 统一日志条目模型
│   │   └── tiled_layout.dart        # 平铺布局工具
│   └── util/
│       └── data_format.dart          # HEX/文本转换、时间戳格式化
└── features/
    ├── serial/                     # 串口调试模块
    │   ├── data/                     # 串口服务、持久化
    │   ├── domain/                   # 会话管理、串口配置
    │   └── presentation/             # UI 页面与组件
    ├── network/                    # 网络调试模块
    │   ├── data/                     # 网络信息服务、持久化
    │   ├── domain/                   # 会话管理、网络配置
    │   └── presentation/             # UI 页面与组件
    ├── modbus/                     # Modbus 模拟器模块
    │   ├── data/                     # RTU/TCP 通道、持久化
    │   ├── domain/                   # CRC16、PDU编解码、寄存器库、主从控制器
    │   └── presentation/             # UI 页面与组件
    ├── bluetooth/                   # 蓝牙调试模块
    │   ├── data/                     # BLE 持久化
    │   ├── domain/                   # 会话管理、设备模型
    │   └── presentation/             # UI 页面与组件
    ├── usb/                         # USB 调试模块
    │   ├── data/                     # libusb FFI 绑定、HID 服务、持久化
    │   ├── domain/                   # HID/Raw USB 会话、设备模型
    │   └── presentation/             # UI 页面与组件
    ├── mqtt/                        # MQTT 调试模块
    │   ├── data/                     # MQTT 持久化
    │   ├── domain/                   # 会话管理、MQTT 配置
    │   └── presentation/             # UI 页面与组件
    ├── can/                         # CAN 调试模块
    │   ├── data/                     # SlcanTransport（SLCAN 串口实现）、注册入口、持久化
    │   ├── domain/                   # CanTransport 抽象接口 + CanTransportConfig + CanTransportRegistry、CanFrame、会话管理、配置
    │   └── presentation/             # UI 页面与组件
    └── canopen/                     # CANopen 调试模块
        ├── data/                     # 持久化（底层复用 CanTransport 接口）
        ├── domain/                   # SDO 编解码、NMT 编解码、会话管理、配置
        └── presentation/             # UI 页面与组件
```

### 扩展新功能

项目提供两种编译时插件化架构：

| | DebugFeature 插件 | CanTransport 插件 |
|---|---|---|
| **用途** | 新增调试模块（如 WebSocket、OPC UA） | 新增 USB-CAN 协议驱动（PCAN-USB、Kvaser、自研 DLL） |
| **改多少文件** | 3 个（feature + page + 注册行） | 2 个（transport + 注册行） |
| **会话代码改动** | 不涉及 | 零改动 |
| **UI 自动适配** | 主页新卡片 | 连接对话框传输层下拉框自动出现 |

---

#### 架构 A：新增调试模块（DebugFeature 插件）

##### 核心接口

定义于 `lib/core/feature/debug_feature.dart`：

```dart
abstract class DebugFeature {
  String get id;           // 全局唯一标识，如 'serial'
  String get title;        // 主页卡片标题
  String get description;  // 一句话功能描述
  IconData get icon;       // 入口图标
  Color get color;         // 主题色（卡片渐变 / 状态强调）
  Widget buildPage(BuildContext context);  // 主页面
}
```

##### 编写步骤（以 WebSocket 调试为例）

**1. 创建模块目录**（data / domain / presentation 三层）

```
lib/features/websocket/
├── data/
│   └── ws_store.dart           # SharedPreferences 持久化
├── domain/
│   ├── ws_config.dart          # 连接配置
│   ├── ws_session.dart         # 会话（extends ChangeNotifier implements SendPanelController）
│   └── ws_session_manager.dart # 多会话管理 + QuickCommandStore
└── presentation/
    ├── ws_feature.dart         # implements DebugFeature
    ├── ws_page.dart            # 主页面（TiledLayout 平铺）
    └── widgets/
        ├── ws_connection_dialog.dart
        └── ws_session_view.dart
```

**2. 实现 DebugFeature**

```dart
// lib/features/websocket/presentation/ws_feature.dart
class WsFeature implements DebugFeature {
  late final Future<WsSessionManager> managerFuture = WsSessionManager.create();

  @override String get id => 'websocket';
  @override String get title => 'WebSocket 调试';
  @override String get description => 'WebSocket 客户端，支持 ws:// 和 wss://';
  @override IconData get icon => Icons.connect_without_contact_outlined;
  @override Color get color => const Color(0xFF00CEC9);

  @override
  Widget buildPage(BuildContext context) {
    return FutureBuilder<WsSessionManager>(
      future: managerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return WsPage(manager: snapshot.data!);
      },
    );
  }
}
```

**3. 在 bootstrap.dart 注册**（改一行）

```dart
import '../features/websocket/presentation/ws_feature.dart';
// ...
void registerAllFeatures() {
  registry
    ..register(SerialFeature())
    // ... 其他模块
    ..register(WsFeature());   // ← 新增这一行
}
```

**4. widget_test.dart 加断言**（可选）

```dart
expect(find.text('WebSocket 调试'), findsOneWidget);
```

完成！主页自动出现入口卡片。

##### 模块实现模板

参考已有模块（串口 / MQTT / USB），标准实现范式：

| 组件 | 作用 | 必实现接口 |
|------|------|-----------|
| `XxxSession extends ChangeNotifier` | 单会话 | `SendPanelController`（isConnected / sendContent / startLoopSend / stopLoopSend / sendAsHex / lineEnding / loopIntervalMs / loopSending） |
| `XxxSessionManager extends ChangeNotifier` | 多会话管理 | `QuickCommandStore`（quickCommands / history / newCommandId / add-update-removeQuickCommand / clearHistory） |
| `XxxStore` | SharedPreferences 持久化 | 上次配置 + 快捷指令 + 发送历史 |
| `XxxConnectionDialog` | 连接参数对话框 | — |
| `XxxSessionView` | 单会话视图 | 状态栏 + 参数区 + ReceivePanel + SendPanel |
| `XxxPage` | 主页面 | AppBar + TiledLayout 平铺 + 空态引导 |
| `XxxFeature implements DebugFeature` | 注册入口 | — |

---

#### 架构 B：新增 CAN 传输层（CanTransport 插件）

##### 核心接口

定义于 `lib/features/can/domain/can_transport.dart`：

```dart
abstract class CanTransport {
  const CanTransport();

  String get transportType;     // 类型标识，如 'pcan'
  String get transportLabel;    // UI 显示文本
  bool get isOpen;              // 是否已打开

  Future<void> open({
    required CanTransportConfig config,
    required void Function(CanFrame frame) onFrame,
    required void Function(Object error) onError,
  });

  Future<int> sendFrame(CanFrame frame);
  Future<void> close();
  Future<void> dispose();
}
```

**`CanTransportConfig`** 通用配置：
- `transportType` — 传输层类型，如 `'slcan'` / `'pcan'`
- `portName` — 适配器标识（SLCAN 串口名 `COM5`，PCAN 通道名 `PCAN-USB1`）
- `canBitrate` — CAN 总线波特率（所有传输层共有，`CanBitrate` 枚举）
- `rawConfig` — 传输层特有参数（如 SLCAN 的 `{'baudRate': 115200}`）

**`CanFrame`** 传输层与会话层之间的帧模型：
- `id` — CAN 帧 ID（标准帧 11-bit / 扩展帧 29-bit）
- `extended` — 是否扩展帧
- `remote` — 是否远程帧
- `data` — 0~8 字节数据负载

##### 参考实现：SlcanTransport 的关键模式

| 关注点 | SlcanTransport 做法 |
|--------|---------------------|
| **适配器枚举** | `static List<String> get availableAdapters` → 注册时传入 `availableAdapters: () => SlcanTransport.availableAdapters` |
| **open 初始化** | 打开串口 → 配参数 → 发 SLCAN 命令（`C\r` / `S<n>\r` / `O\r`）→ 启动 15ms Timer 轮询 |
| **接收解析** | 轮询读原始字节 → 按协议分帧（SLCAN 用 CR）→ `CanFrame.fromSlcan(line)` → 调 `onFrame(frame)` |
| **发送编码** | `frame.toSlcanCommand()` → 写串口 |
| **致命错误** | `_dead = true` → 停 Timer → 释放资源 → 调 `onError(error)` |
| **close 幂等** | 发清理命令 → 停 Timer → 释放 native handle → `isOpen` 变 false |
| **dispose 彻底释放** | 调 close() 后标记不可再 open（如 FFI isolate 停止） |

##### 编写步骤（以 PCAN-USB 为例）

**1. 创建传输层文件**

```
lib/features/can/data/pcan_transport.dart
```

```dart
// lib/features/can/data/pcan_transport.dart
import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../domain/can_frame.dart';
import '../domain/can_transport.dart';

/// PCANBasic.dll 的 FFI 绑定（示意，实际用 ffi 2.x 编写）
final _pcan = _PcanBindings();

class PcanTransport implements CanTransport {
  PcanTransport();

  int? _channelHandle;
  Timer? _pollTimer;
  bool _dead = false;
  bool _initialized = false;

  static const Duration _pollInterval = Duration(milliseconds: 15);

  @override String get transportType => 'pcan';
  @override String get transportLabel => 'PCAN-USB（PEAK 系统）';
  @override bool get isOpen => _channelHandle != null && !_dead;

  /// 枚举系统中可用的 PCAN 通道，注册时传入。
  static List<String> get availableAdapters {
    final list = <String>[];
    try {
      for (var i = 0; i < 16; i++) {
        final name = _pcan.getChannelName(i);
        if (name != null) list.add(name);  // 如 'PCAN-USB1'
      }
    } catch (_) {}
    return list;
  }

  @override
  Future<void> open({
    required CanTransportConfig config,
    required void Function(CanFrame frame) onFrame,
    required void Function(Object error) onError,
  }) async {
    // 1. 初始化 DLL（首次调用时 LoadLibrary）
    if (!_pcan.isLoaded) {
      _pcan.loadDll();
    }

    // 2. 打开指定通道
    final channelIndex = _pcan.channelNameToIndex(config.portName);
    final handle = _pcan.initialize(channelIndex, config.canBitrate.pcanCode);
    if (handle == null) {
      throw StateError('打开 PCAN 通道 ${config.portName} 失败：'
          '${_pcan.getLastError()}');
    }
    _channelHandle = handle;

    // 3. 启动轮询接收
    _dead = false;
    _initialized = true;
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => _pollOnce(onFrame, onError),
    );
  }

  void _pollOnce(
    void Function(CanFrame) onFrame,
    void Function(Object) onError,
  ) {
    if (_dead) return;
    final handle = _channelHandle;
    if (handle == null) return;

    try {
      final rawFrames = _pcan.readAll(handle);
      for (final raw in rawFrames) {
        final frame = CanFrame(
          id: raw.id,
          extended: raw.isExtended,
          remote: raw.isRemote,
          data: Uint8List.fromList(raw.data),
        );
        onFrame(frame);
      }
    } catch (e) {
      _handleFatal(e, onError);
    }
  }

  @override
  Future<int> sendFrame(CanFrame frame) async {
    final handle = _channelHandle;
    if (handle == null || _dead) {
      throw StateError('PCAN 通道未打开');
    }
    _pcan.write(handle, frame.id, frame.extended, frame.remote, frame.data);
    return 1;
  }

  void _handleFatal(Object error, void Function(Object) onError) {
    if (_dead) return;
    _dead = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _releaseChannel();
    onError(StateError('PCAN 连接异常：$error'));
  }

  void _releaseChannel() {
    final handle = _channelHandle;
    if (handle != null) {
      try { _pcan.uninitialize(handle); } catch (_) {}
    }
    _channelHandle = null;
    _initialized = false;
  }

  @override Future<void> close() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _dead = true;
    _releaseChannel();
  }

  @override Future<void> dispose() async {
    await close();
    // FFI DLL 常驻，不主动 FreeLibrary
  }
}

/// PCANBasic.dll 的 FFI 绑定（简化示意，实际用 ffi 2.x 编写）
class _PcanBindings {
  bool get isLoaded => _isLoaded;
  bool _isLoaded = false;
  void loadDll() { /* LoadLibrary('PCANBasic.dll') */ _isLoaded = true; }
  int? initialize(int channelIndex, int baudrateCode) => null;
  void uninitialize(int handle) {}
  List<_RawPcanFrame> readAll(int handle) => const [];
  void write(int handle, int id, bool extended, bool remote, Uint8List data) {}
  String? getLastError() => null;
  String? getChannelName(int index) => null;
  int channelNameToIndex(String name) => 0;
}

class _RawPcanFrame {
  _RawPcanFrame({
    required this.id,
    required this.isExtended,
    required this.isRemote,
    required this.data,
  });
  final int id;
  final bool isExtended;
  final bool isRemote;
  final Uint8List data;
}
```

**2. 注册到注册表**

```dart
// lib/features/can/data/can_transport_registry.dart
void registerCanTransports() {
  CanTransportRegistry.register(
    'slcan', () => SlcanTransport(),
    label: 'SLCAN 串口（Lawicel 协议）',
    availableAdapters: () => SlcanTransport.availableAdapters,
  );

  // ↓ 新增这一行
  CanTransportRegistry.register(
    'pcan', () => PcanTransport(),
    label: 'PCAN-USB（PEAK 系统）',
    availableAdapters: () => PcanTransport.availableAdapters,
  );
}
```

**3. 在 pubspec.yaml 加依赖**（如 `ffi` / `win32`）+ CMakeLists 拷贝原生 DLL 到输出目录

完成！CAN / CANopen 连接对话框自动出现"传输层"下拉框，选 PCAN-USB → 显示 PCAN 通道列表 → 连接。会话代码零改动。

##### 波特率映射

不同传输层的波特率编码可能不同：

- **SLCAN**：`CanBitrate.speed500K.slcanCode` → `'6'`（传给 `S6\r`）
- **PCAN**：`CanBitrate.speed500K.pcanCode` → `0x00140014`（传给 `CAN_Initialize`）

两种处理方式：

1. **在 `CanBitrate` 枚举加字段**（简单场景）：
```dart
enum CanBitrate {
  speed500K('500 kbps', '6', 0x00140014);

  const CanBitrate(this.label, this.slcanCode, this.pcanCode);
  final String label;
  final String slcanCode;
  final int pcanCode;
}
```

2. **放入 `CanTransportConfig.rawConfig`**（灵活场景，传输层自己处理）：
```dart
CanTransportConfig(
  transportType: 'pcan',
  portName: 'PCAN-USB1',
  canBitrate: CanBitrate.speed500K,          // 通用字段
  rawConfig: {'pcanBaudrate': 0x00140014},  // PCAN 特有
)
```

推荐方式 1——当波特率是通用概念时；如果传输层有特殊波特率（如非标准值、DLC 补偿），用方式 2。

## 依赖

| 包 | 用途 |
|----|------|
| `flutter_libserialport` | 串口通信（串口 / CAN 模块共用） |
| `libserialport` | 串口参数常量（校验 / 停止位 / 流控） |
| `universal_ble` | BLE 蓝牙扫描 / 连接 / GATT 读写 / Notify |
| `hid_tool` | HID 设备通信（USB HID 通道） |
| `ffi` | libusb FFI 绑定（通用 USB 通道，ffi 2.x） |
| `mqtt_client` | MQTT 客户端（MQTT 模块，纯 Dart） |
| `file_selector` | 日志文件导出 |
| `shared_preferences` | 配置与数据持久化 |

## 硬件推荐

| 调试需求 | 推荐硬件 | 备注 |
|----------|----------|------|
| 串口 | CH340 / CP2102 / FT232 模块 | 最常见的 USB 转串口方案，驱动免安装 |
| CAN | CANable Pro（USB-CAN，SLCAN 固件） / PCAN-USB / Kvaser Leaf | 传输层插件化，SLCAN / PCAN / Kvaser 任选其一 |
| CANopen | CAN 适配器 + 目标 CANopen 设备 | 如倍福 PLC、施耐德驱动器、带 CANopen 的传感器 |
| 蓝牙 | 内置蓝牙或 USB BLE 5.0 适配器 | Windows 10/11 自带蓝牙栈即可 |
| USB 通用 | CH341 + libusb 驱动 | WinUSB 设备可用 Zadig 切换驱动 |
| Modbus RTU | 485 转串口转换器 + 从机设备 | |
| Modbus TCP / MQTT | 局域网 + 对应 Broker / 从机 | |

## 开发

```bash
# 静态分析
flutter analyze

# 运行测试
flutter test

# 构建 Windows Debug 版本
flutter build windows --debug

# 构建 Windows Release 版本
flutter build windows --release
```

产物路径：`build/windows/x64/runner/Debug/debug_assistant.exe`（Debug）或 `build/windows/x64/runner/Release/debug_assistant.exe`（Release）
