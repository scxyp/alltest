import 'dart:typed_data';

/// CANopen NMT 命令类型（发送到 COB-ID 0x000）。
enum NmtCommand {
  start(0x01),
  stop(0x02),
  preOperational(0x80),
  reset(0x81),
  resetCommunication(0x82);

  const NmtCommand(this.code);
  final int code;
}

/// CANopen 节点状态（由 Heartbeat 上报）。
enum NmtState {
  bootUp(0x00, 'Boot-up'),
  stopped(0x04, 'Stopped'),
  operational(0x05, 'Operational'),
  preOperational(0x7F, 'Pre-Operational');

  const NmtState(this.code, this.label);
  final int code;
  final String label;

  static NmtState? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// CANopen NMT / Heartbeat 协议编解码。
class NmtCodec {
  NmtCodec._();

  /// NMT 控制 COB-ID（广播所有节点）。
  static const int controlCobId = 0x000;

  /// Heartbeat COB-ID 基址（0x700 + Node ID）。
  static const int heartbeatCobIdBase = 0x700;

  /// 构造 NMT 命令数据帧（3 字节，附加在 COB-ID 0x000 上发送）。
  ///
  /// [targetNodeId] 目标节点 ID（0 = 广播所有节点）。
  static Uint8List buildNmtCommand(NmtCommand cmd, int targetNodeId) {
    final data = Uint8List(3);
    data[0] = cmd.code;
    data[1] = targetNodeId & 0x7F;
    data[2] = 0; // 保留
    return data;
  }

  /// 解析 Heartbeat 帧数据（1 字节，来自 COB-ID 0x700+NID）。
  static NmtState? parseHeartbeat(Uint8List data) {
    if (data.isEmpty) return null;
    return NmtState.fromCode(data[0]);
  }
}
