import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debug_log_entry.dart';
import 'line_ending.dart';
import 'quick_command.dart';
import 'quick_command_dialog.dart';
import 'quick_command_strip.dart';
import 'send_contracts.dart';

export 'line_ending.dart';
export 'send_contracts.dart';

class SendTextIntent extends Intent {
  const SendTextIntent();
}

/// 数据发送面板：输入、编码选项、循环发送、快捷指令与发送历史。
class SendPanel extends StatefulWidget {
  const SendPanel({
    super.key,
    required this.controller,
    required this.store,
    this.disconnectedHint = '请先建立连接',
  });

  final SendPanelController controller;
  final QuickCommandStore store;

  /// 未连接时输入框中的提示语（如串口模块传"请先打开串口"）。
  final String disconnectedHint;

  @override
  State<SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends State<SendPanel> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _interval = TextEditingController(text: '1000');

  @override
  void dispose() {
    _input.dispose();
    _interval.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _doSend() {
    try {
      widget.controller.sendContent(
        _input.text,
        asHex: widget.controller.sendAsHex,
      );
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  void _toggleLoop(bool on) {
    final controller = widget.controller;
    if (on) {
      try {
        controller.startLoopSend(_input.text);
      } on FormatException catch (e) {
        _snack(e.message);
      } catch (e) {
        _snack(friendlyError(e));
      }
    } else {
      controller.stopLoopSend();
    }
  }

  void _loadToInput(String content, bool asHex) {
    _input.text = content;
    setState(() {
      widget.controller.sendAsHex = asHex;
    });
  }

  Future<void> _addQuickCommand() async {
    final result = await QuickCommandDialog.show(
      context,
      newId: widget.store.newCommandId(),
    );
    if (result != null) await widget.store.addQuickCommand(result);
  }

  Future<void> _editQuickCommand(QuickCommand command) async {
    final result = await QuickCommandDialog.show(
      context,
      existing: command,
      newId: widget.store.newCommandId(),
    );
    if (result != null) await widget.store.updateQuickCommand(result);
  }

  void _sendQuickCommand(QuickCommand command) {
    try {
      widget.controller.sendContent(command.content, asHex: command.asHex);
    } on FormatException catch (e) {
      _snack('“${command.name}”内容不合法：${e.message}');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([controller, store]),
      builder: (context, _) {
        final connected = controller.isConnected;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          color: scheme.surfaceContainerLow,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- 选项行 ---
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('HEX 发送'),
                      selected: controller.sendAsHex,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) {
                        setState(() {
                          controller.sendAsHex = v;
                        });
                      },
                    ),
                    if (!controller.sendAsHex)
                      _wrapLabel(
                        '行结束符',
                        SegmentedButton<LineEnding>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                                value: LineEnding.none, label: Text('无')),
                            ButtonSegment(
                                value: LineEnding.crLf, label: Text('CRLF')),
                            ButtonSegment(
                                value: LineEnding.cr, label: Text('CR')),
                            ButtonSegment(
                                value: LineEnding.lf, label: Text('LF')),
                          ],
                          selected: {controller.lineEnding},
                          onSelectionChanged: (v) {
                            setState(() {
                              controller.lineEnding = v.first;
                            });
                          },
                        ),
                      ),
                    _wrapLabel(
                      '定时发送',
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: controller.loopSending,
                            onChanged: connected ? _toggleLoop : null,
                          ),
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              controller: _interval,
                              enabled: !controller.loopSending,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                suffixText: 'ms',
                              ),
                              onChanged: (v) =>
                                  controller.loopIntervalMs = int.tryParse(v) ?? 1000,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // --- 输入框 + 发送按钮 ---
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Actions(
                          actions: {
                            SendTextIntent:
                                CallbackAction<SendTextIntent>(
                              onInvoke: (_) {
                                _doSend();
                                return null;
                              },
                            ),
                          },
                          child: Shortcuts(
                            shortcuts: const {
                              SingleActivator(LogicalKeyboardKey.enter,
                                  control: true): SendTextIntent(),
                            },
                            child: TextField(
                              controller: _input,
                              maxLines: 3,
                              minLines: 3,
                              enabled: connected,
                              style: const TextStyle(
                                  fontFamily: 'Consolas', fontSize: 13.5),
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                hintText: connected
                                    ? (controller.sendAsHex
                                        ? '输入 HEX，如：AA 01 0F（Ctrl+Enter 发送）'
                                        : '输入发送内容（Ctrl+Enter 发送）')
                                    : widget.disconnectedHint,
                                hintStyle: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 104,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: controller.loopSending
                                  ? FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red.shade700,
                                      ),
                                      onPressed: () => _toggleLoop(false),
                                      child: const Text('停止'),
                                    )
                                  : FilledButton.icon(
                                      onPressed: connected ? _doSend : null,
                                      icon: const Icon(Icons.send, size: 18),
                                      label: const Text('发送'),
                                    ),
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: () => _input.clear(),
                              icon: const Icon(Icons.clear_all, size: 16),
                              label: const Text('清空'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // --- 快捷指令 + 历史 ---
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('快捷指令',
                        style: TextStyle(
                            fontSize: 12, color: scheme.outline)),
                    for (final command in store.quickCommands)
                      QuickChip(
                        command: command,
                        enabled: connected,
                        onSend: () => _sendQuickCommand(command),
                        onLoad: () =>
                            _loadToInput(command.content, command.asHex),
                        onEdit: () => _editQuickCommand(command),
                        onDelete: () =>
                            store.removeQuickCommand(command.id),
                      ),
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('新增'),
                      onPressed: _addQuickCommand,
                    ),
                    Container(
                      width: 1,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: scheme.outlineVariant,
                    ),
                    HistoryMenu(
                      store: store,
                      onPick: (item) =>
                          _loadToInput(item.content, item.asHex),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _wrapLabel(String label, Widget child) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline)),
        child,
      ],
    );
  }
}
