import 'dart:async';
import 'dart:typed_data';

import 'package:libserialport/libserialport.dart';

import '../domain/serial_config.dart';

/// 对 libserialport 的薄封装，负责一个串口的打开 / 读写 / 关闭生命周期。
///
/// 不使用库自带的 [SerialPortReader]：它会启动一个持有端口原始指针的
/// isolate，关闭 / 拔线时若 isolate 仍阻塞在原生调用中而我们释放了端口，
/// 会造成原生层 use-after-free 崩溃。这里改为在主 isolate 内以定时器做
/// 非阻塞轮询（`bytesAvailable` + `read(timeout: 0)` 均不会阻塞），
/// 所有端口访问单线程且严格按序：停轮询 → 关端口 → 释放内存。
///
/// 资源释放规则（重要）：
/// `SerialPort.dispose()` 内部会先释放它持有的 [SerialPortConfig] 再释放
/// 端口结构，而 `SerialPortConfig.dispose()` 没有二次释放防护。因此配置
/// 对象一旦通过 `port.config = ...` 交给端口，就绝不能再单独调用其
/// `dispose()`，否则同一块原生内存被 free 两次，在 Debug CRT 下触发
/// `_CrtIsValidHeapPointer` 断言崩溃。
class SerialPortService {
  SerialPort? _port;
  Timer? _pollTimer;
  bool _dead = false;

  /// 轮询周期。15ms 在 115200 波特率下单次最多约 1.7KB，足够低延迟。
  static const Duration _pollInterval = Duration(milliseconds: 15);

  bool get isOpen => _port?.isOpen ?? false;

  /// 按 [config] 打开串口并开始轮询接收。
  void open(
    SerialConfig config, {
    required void Function(Uint8List data) onData,
    required void Function(Object error) onError,
  }) {
    final port = SerialPort(config.portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw StateError(
        '打开 ${config.portName} 失败：${error?.toString() ?? '未知错误'}',
      );
    }

    final cfg = SerialPortConfig()
      ..baudRate = config.baudRate
      ..bits = config.dataBits
      ..parity = config.parity.nativeValue
      ..stopBits = config.stopBits.nativeValue
      ..setFlowControl(config.flowControl.nativeValue);

    try {
      port.config = cfg;
    } catch (e) {
      // config setter 即使在 sp_set_config 失败时也已把 cfg 存入 port，
      // 统一交给 port.dispose() 释放，避免双重 free。
      try {
        port.close();
      } catch (_) {}
      port.dispose();
      throw StateError('应用串口参数失败：$e');
    }

    _port = port;
    _dead = false;
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => _pollOnce(onData, onError),
    );
  }

  /// 生成适合展示的错误描述。Windows 的错误消息是本地 ANSI（GBK）编码，
  /// 直接展示会乱码，串口错误只保留错误码。
  String _describeError(Object e) {
    if (e is SerialPortError) {
      return '串口错误（errno=${e.errorCode}）';
    }
    return '$e';
  }

  void _pollOnce(
    void Function(Uint8List) onData,
    void Function(Object) onError,
  ) {
    if (_dead) return;
    final port = _port;
    if (port == null || !port.isOpen) return;

    // 拔线探针：读取调制解调器状态线（内部为 GetCommModemStatus）。
    // 设备被拔出后句柄失效，该调用会立刻报错；而 bytesAvailable 依赖的
    // ClearCommError 在拔线后往往仍"成功"返回 0 字节，探不出任何异常。
    try {
      port.signals;
    } catch (e) {
      _handleFatal(e, onError);
      return;
    }

    final int available;
    try {
      available = port.bytesAvailable;
    } catch (e) {
      _handleFatal(e, onError);
      return;
    }
    if (available <= 0) return;

    final Uint8List data;
    try {
      // timeout: 0 → 非阻塞，立即返回当前可读的字节。
      data = port.read(available, timeout: 0);
    } catch (e) {
      _handleFatal(e, onError);
      return;
    }
    if (data.isNotEmpty) onData(data);
  }

  /// 轮询中发生致命错误（通常是设备被拔出）：先清理端口再上报，
  /// 并保证 onError 只触发一次。
  void _handleFatal(Object error, void Function(Object) onError) {
    if (_dead) return;
    _dead = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _releasePort();
    onError(StateError(_describeError(error)));
  }

  /// 同步写出数据，返回实际写入字节数。
  int write(Uint8List bytes) {
    final port = _port;
    if (port == null || !port.isOpen) {
      throw StateError('串口未打开');
    }
    try {
      return port.write(bytes);
    } catch (e) {
      throw StateError('写入失败（${_describeError(e)}）');
    }
  }

  /// 停止轮询并释放全部原生资源。可重复调用。
  ///
  /// 由于收发全部在主 isolate 内完成，这里不存在与后台读取的竞态。
  Future<void> close() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _dead = true;
    _releasePort();
  }

  void _releasePort() {
    try {
      if (_port?.isOpen ?? false) _port?.close();
    } catch (_) {
      // 设备已被拔出等场景下关闭可能失败，忽略。
    }
    // 只调用 SerialPort.dispose()：它会先释放内部持有的
    // SerialPortConfig 再释放端口，保证每块原生内存只被释放一次。
    try {
      _port?.dispose();
    } catch (_) {}
    _port = null;
  }

  /// 系统当前可用的串口名列表。
  static List<String> get availablePorts => SerialPort.availablePorts;

  /// 获取串口的用户可读描述（驱动名），失败返回 null。
  static String? describe(String portName) {
    try {
      final port = SerialPort(portName);
      final description = port.description;
      port.dispose();
      return description;
    } catch (_) {
      return null;
    }
  }
}
