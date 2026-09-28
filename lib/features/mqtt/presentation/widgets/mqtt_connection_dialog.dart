import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/mqtt_config.dart';

/// 新建 / 编辑 MQTT 会话的配置对话框。
class MqttConnectionDialog extends StatefulWidget {
  const MqttConnectionDialog({super.key, this.initial});

  final MqttConfig? initial;

  static Future<MqttConfig?> show(
    BuildContext context, {
    MqttConfig? initial,
  }) {
    return showDialog<MqttConfig>(
      context: context,
      builder: (_) => MqttConnectionDialog(initial: initial),
    );
  }

  @override
  State<MqttConnectionDialog> createState() => _MqttConnectionDialogState();
}

class _MqttConnectionDialogState extends State<MqttConnectionDialog> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _clientId;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _keepAlive;
  late bool _tls;

  // 遗嘱
  late bool _willEnabled;
  late final TextEditingController _willTopic;
  late final TextEditingController _willPayload;
  late MqttQosLevel _willQos;
  late bool _willRetain;

  @override
  void initState() {
    super.initState();
    final cfg = widget.initial;
    _host = TextEditingController(text: cfg?.host ?? '');
    _port = TextEditingController(
      text: cfg?.port == null || cfg?.port == 0 ? '' : '${cfg?.port}',
    );
    _clientId = TextEditingController(text: cfg?.clientId ?? '');
    _username = TextEditingController(text: cfg?.username ?? '');
    _password = TextEditingController(text: cfg?.password ?? '');
    _keepAlive = TextEditingController(
      text: '${cfg?.keepAlive ?? 60}',
    );
    _tls = cfg?.tls ?? false;

    _willEnabled = cfg?.will != null;
    _willTopic = TextEditingController(text: cfg?.will?.topic ?? '');
    _willPayload = TextEditingController(text: cfg?.will?.payload ?? '');
    _willQos = cfg?.will?.qos ?? MqttQosLevel.atMostOnce;
    _willRetain = cfg?.will?.retain ?? false;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _clientId.dispose();
    _username.dispose();
    _password.dispose();
    _keepAlive.dispose();
    _willTopic.dispose();
    _willPayload.dispose();
    super.dispose();
  }

  /// TLS 开关变化时自动调整端口默认值。
  void _onTlsChanged(bool value) {
    setState(() {
      _tls = value;
      final currentPort = int.tryParse(_port.text.trim()) ?? 0;
      if (value && currentPort == 1883) {
        _port.text = '8883';
      } else if (!value && currentPort == 8883) {
        _port.text = '1883';
      }
    });
  }

  void _submit() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 0;
    final clientId = _clientId.text.trim();
    final username = _username.text.trim();
    final password = _password.text.trim();
    final keepAlive = int.tryParse(_keepAlive.text.trim()) ?? 60;

    if (host.isEmpty) {
      _snack('请填写 Broker 地址');
      return;
    }
    if (port <= 0 || port > 65535) {
      _snack('请填写有效的端口（1-65535）');
      return;
    }

    MqttLastWill? will;
    if (_willEnabled) {
      final willTopic = _willTopic.text.trim();
      if (willTopic.isEmpty) {
        _snack('遗嘱主题不能为空');
        return;
      }
      will = MqttLastWill(
        topic: willTopic,
        payload: _willPayload.text,
        qos: _willQos,
        retain: _willRetain,
      );
    }

    Navigator.of(context).pop(MqttConfig(
      host: host,
      port: port,
      clientId: clientId,
      username: username,
      password: password,
      tls: _tls,
      keepAlive: keepAlive,
      will: will,
    ));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建 MQTT 连接'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _FieldLabel('Broker 地址'),
              TextFormField(
                controller: _host,
                decoration: const InputDecoration(
                  hintText: '如 broker.hivemq.com 或 192.168.1.10',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('端口'),
                        TextFormField(
                          controller: _port,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            hintText: '1883 / 8883',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('TLS'),
                        Switch(
                          value: _tls,
                          onChanged: _onTlsChanged,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('ClientId（可空，自动生成）'),
                        TextFormField(
                          controller: _clientId,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('KeepAlive'),
                        TextFormField(
                          controller: _keepAlive,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            suffixText: 's',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _FieldLabel('用户名 / 密码（可空，匿名连接）'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                        hintText: '用户名',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        hintText: '密码',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // --- 遗嘱（Last Will）---
              InkWell(
                onTap: () =>
                    setState(() => _willEnabled = !_willEnabled),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _willEnabled
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Checkbox(
                        value: _willEnabled,
                        onChanged: (v) =>
                            setState(() => _willEnabled = v ?? false),
                      ),
                      const Text('遗嘱消息（Last Will）'),
                    ],
                  ),
                ),
              ),
              if (_willEnabled) ...[
                TextFormField(
                  controller: _willTopic,
                  decoration: const InputDecoration(
                    labelText: '遗嘱主题',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _willPayload,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '遗嘱负载',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('QoS'),
                    const SizedBox(width: 8),
                    DropdownButton<MqttQosLevel>(
                      value: _willQos,
                      items: [
                        for (final q in MqttQosLevel.values)
                          DropdownMenuItem(value: q, child: Text(q.label)),
                      ],
                      onChanged: (v) =>
                          setState(() => _willQos = v ?? MqttQosLevel.atMostOnce),
                    ),
                    const SizedBox(width: 16),
                    const Text('Retain'),
                    Checkbox(
                      value: _willRetain,
                      onChanged: (v) =>
                          setState(() => _willRetain = v ?? false),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('连接')),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
