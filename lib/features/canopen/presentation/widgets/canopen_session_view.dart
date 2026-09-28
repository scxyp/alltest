import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/receive_panel.dart';
import '../../../../core/ui/send_panel.dart';
import '../../../../core/util/data_format.dart';
import '../../domain/canopen_nmt.dart';
import '../../domain/canopen_sdo.dart';
import '../../domain/canopen_session.dart';
import '../../domain/canopen_session_manager.dart';
import 'canopen_connection_dialog.dart';

/// 单个 CANopen 会话的完整视图：状态栏 + NMT 控制 + SDO 区域 + 接收区 + 发送区。
class CanOpenSessionView extends StatefulWidget {
  const CanOpenSessionView({
    super.key,
    required this.session,
    required this.manager,
    required this.onCloseSession,
  });

  final CanOpenSession session;
  final CanOpenSessionManager manager;
  final Future<void> Function() onCloseSession;

  @override
  State<CanOpenSessionView> createState() => _CanOpenSessionViewState();
}

class _CanOpenSessionViewState extends State<CanOpenSessionView> {
  late final TextEditingController _indexController;
  late final TextEditingController _subindexController;
  late final TextEditingController _sdoDataController;
  late final TextEditingController _frameIdController;

  @override
  void initState() {
    super.initState();
    _indexController = TextEditingController(text: '1000');
    _subindexController = TextEditingController(text: '00');
    _sdoDataController = TextEditingController();
    final sid = widget.session.frameId
        .toRadixString(16)
        .toUpperCase()
        .padLeft(3, '0');
    _frameIdController = TextEditingController(text: sid);
  }

  @override
  void dispose() {
    _indexController.dispose();
    _subindexController.dispose();
    _sdoDataController.dispose();
    _frameIdController.dispose();
    super.dispose();
  }

  Future<void> _toggleConnection() async {
    final session = widget.session;
    if (session.isConnected) {
      await session.disconnect();
      return;
    }
    try {
      await session.connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _editConfig() async {
    final config = await CanOpenConnectionDialog.show(
      context,
      ports: widget.manager.availablePorts,
      busyPorts: widget.manager.busyPorts,
      initial: widget.session.config,
      actionText: '保存',
    );
    if (config != null) {
      widget.session.updateConfig(config);
      _frameIdController.text = (SdoCodec.requestCobIdBase + config.nodeId)
          .toRadixString(16)
          .toUpperCase()
          .padLeft(3, '0');
    }
  }

  void _onFrameIdChanged(String value) {
    final hex = value.trim().replaceAll(RegExp(r'^0[xX]'), '');
    final id = int.tryParse(hex, radix: 16);
    if (id != null) widget.session.frameId = id;
  }

  // --- NMT 控制 ---

  void _sendNmt(NmtCommand cmd) {
    final session = widget.session;
    try {
      session.sendNmt(cmd, targetNodeId: session.config.nodeId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  // --- SDO 操作 ---

  Future<void> _sdoRead() async {
    final session = widget.session;
    final index = _parseHex(_indexController.text, name: 'Index');
    final subindex = _parseHex(_subindexController.text, name: 'Subindex');
    if (index == null || subindex == null) return;

    try {
      final result = await session.sdoRead(index, subindex).timeout(
        const Duration(milliseconds: CanOpenSession.sdoTimeoutMs),
      );
      // 将读到的数据填入 SDO 数据字段
      _sdoDataController.text = DataFormat.bytesToHex(result.data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SDO 读取成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _sdoWrite() async {
    final session = widget.session;
    final index = _parseHex(_indexController.text, name: 'Index');
    final subindex = _parseHex(_subindexController.text, name: 'Subindex');
    if (index == null || subindex == null) return;

    Uint8List value;
    try {
      value = DataFormat.hexToBytes(_sdoDataController.text);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
      return;
    }
    if (value.length > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expedited SDO 仅支持 ≤4 字节数据')),
      );
      return;
    }
    try {
      session.sdoWrite(index, subindex, value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SDO 写入已发送')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  int? _parseHex(String text, {required String name}) {
    final hex = text.trim().replaceAll(RegExp(r'^0[xX]'), '');
    if (hex.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请填写 $name')),
      );
      return null;
    }
    final value = int.tryParse(hex, radix: 16);
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name 必须是十六进制数')),
      );
      return null;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Column(
      children: [
        // --- 状态栏 ---
        ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final connected = session.isConnected;
            final scheme = Theme.of(context).colorScheme;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: scheme.surfaceContainerLowest,
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: connected
                          ? Colors.green
                          : (session.lastError != null
                              ? Colors.red
                              : Colors.grey),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    session.config.portName,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Node ${session.config.nodeId}',
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'Consolas'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    connected ? '已连接' : '未连接',
                    style: TextStyle(
                      fontSize: 12,
                      color: connected ? Colors.green : scheme.outline,
                    ),
                  ),
                  if (session.loopSending) ...[
                    const SizedBox(width: 10),
                    _LoopBadge(),
                  ],
                  const Spacer(),
                  if (!connected)
                    TextButton.icon(
                      onPressed: _editConfig,
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('参数'),
                    ),
                  const SizedBox(width: 4),
                  connected
                      ? OutlinedButton.icon(
                          onPressed: _toggleConnection,
                          icon: const Icon(Icons.link_off, size: 18),
                          label: const Text('断开'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: _toggleConnection,
                          icon: const Icon(Icons.power, size: 18),
                          label: const Text('连接'),
                        ),
                  IconButton(
                    tooltip: '关闭会话',
                    onPressed: widget.onCloseSession,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
        // --- NMT 控制行 ---
        ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final connected = session.isConnected;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Text('NMT',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(width: 8),
                  _NmtBtn(
                    label: 'Start',
                    color: Colors.green.shade700,
                    enabled: connected,
                    onPressed: () => _sendNmt(NmtCommand.start),
                  ),
                  _NmtBtn(
                    label: 'Stop',
                    color: Colors.red.shade700,
                    enabled: connected,
                    onPressed: () => _sendNmt(NmtCommand.stop),
                  ),
                  _NmtBtn(
                    label: 'Pre-Op',
                    color: Colors.orange.shade700,
                    enabled: connected,
                    onPressed: () => _sendNmt(NmtCommand.preOperational),
                  ),
                  _NmtBtn(
                    label: 'Reset',
                    color: Colors.deepOrange.shade800,
                    enabled: connected,
                    onPressed: () => _sendNmt(NmtCommand.reset),
                  ),
                  _NmtBtn(
                    label: 'Reset Comm',
                    color: Colors.purple.shade700,
                    enabled: connected,
                    onPressed: () => _sendNmt(NmtCommand.resetCommunication),
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
        // --- SDO 区域 ---
        ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final connected = session.isConnected;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Text('SDO',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(width: 8),
                  // Index
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _indexController,
                      enabled: connected,
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 13),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-FxX]')),
                      ],
                      decoration: const InputDecoration(
                        prefixText: '0x',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        labelText: 'Index',
                        labelStyle: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Subindex
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _subindexController,
                      enabled: connected,
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 13),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-FxX]')),
                      ],
                      decoration: const InputDecoration(
                        prefixText: '0x',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        labelText: 'Sub',
                        labelStyle: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Data
                  Expanded(
                    child: TextField(
                      controller: _sdoDataController,
                      enabled: connected,
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 13),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-F\s]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'HEX 数据（≤4 字节 Expedited）',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    onPressed: connected ? _sdoRead : null,
                    child: const Text('读取'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonal(
                    onPressed: connected ? _sdoWrite : null,
                    child: const Text('写入'),
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
        // --- 帧属性行 ---
        ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Text('帧 ID',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _frameIdController,
                      enabled: session.isConnected,
                      style: const TextStyle(
                          fontFamily: 'Consolas', fontSize: 13),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-FxX]')),
                      ],
                      decoration: const InputDecoration(
                        prefixText: '0x',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                      ),
                      onChanged: _onFrameIdChanged,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
        // --- 接收区 + 发送区 ---
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  Expanded(
                    child: ListenableBuilder(
                      listenable: session,
                      builder: (context, _) => ReceivePanel(
                        entries: session.logs,
                        rxBytes: session.rxBytes,
                        txBytes: session.txBytes,
                        onClear: session.clearLogs,
                        exportNamePrefix:
                            'canopen_${session.config.portName}',
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.55,
                    ),
                    child: SendPanel(
                      controller: session,
                      store: widget.manager,
                      disconnectedHint: '请先连接 CANopen 适配器',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NmtBtn extends StatelessWidget {
  const _NmtBtn({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          foregroundColor: enabled ? color : null,
          visualDensity: VisualDensity.compact,
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          minimumSize: const Size(0, 28),
        ),
        onPressed: enabled ? onPressed : null,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _LoopBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.repeat, size: 13, color: Colors.orange.shade800),
          const SizedBox(width: 4),
          Text(
            '循环发送中',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
          ),
        ],
      ),
    );
  }
}
