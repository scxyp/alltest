import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../domain/ble_session.dart';

/// GATT 服务 / 特征树：可折叠展开，标注权限，支持读 / 写 / Notify 操作。
class ServiceCharacteristicTree extends StatelessWidget {
  const ServiceCharacteristicTree({
    super.key,
    required this.session,
  });

  final BleSession session;

  @override
  Widget build(BuildContext context) {
    final services = session.services;
    if (services.isEmpty) {
      return Center(
        child: Text(
          '未发现 GATT 服务',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return _ServiceTile(service: service, session: session);
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.session});

  final BleService service;
  final BleSession session;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: false,
      dense: true,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        service.uuid,
        style: const TextStyle(fontSize: 13, fontFamily: 'Consolas'),
      ),
      subtitle: Text(
        '${service.characteristics.length} 个特征',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      children: [
        for (final ch in service.characteristics)
          _CharacteristicTile(
            characteristic: ch,
            serviceId: service.uuid,
            session: session,
          ),
      ],
    );
  }
}

class _CharacteristicTile extends StatefulWidget {
  const _CharacteristicTile({
    required this.characteristic,
    required this.serviceId,
    required this.session,
  });

  final BleCharacteristic characteristic;
  final String serviceId;
  final BleSession session;

  @override
  State<_CharacteristicTile> createState() => _CharacteristicTileState();
}

class _CharacteristicTileState extends State<_CharacteristicTile> {
  bool _subscribed = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.characteristic;
    final props = ch.properties;
    final isWritable = props.contains(CharacteristicProperty.write) ||
        props.contains(CharacteristicProperty.writeWithoutResponse);
    final isReadable = props.contains(CharacteristicProperty.read);
    final isNotifiable = props.contains(CharacteristicProperty.notify) ||
        props.contains(CharacteristicProperty.indicate);
    final isIndicate = props.contains(CharacteristicProperty.indicate);

    final isSelected = widget.session.selectedServiceId == widget.serviceId &&
        widget.session.selectedCharacteristicId == ch.uuid;

    return Container(
      margin: const EdgeInsets.only(left: 16, bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isSelected ? const Color(0xFF4A90D9) : Colors.grey.shade300,
            width: isSelected ? 3 : 1,
          ),
        ),
      ),
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                ch.uuid,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
            // 权限图标
            if (isReadable)
              const Tooltip(
                message: '可读',
                child: Icon(Icons.menu_book, size: 15, color: Colors.blue),
              ),
            if (isWritable) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: props.contains(CharacteristicProperty.write)
                    ? '可写（有响应）'
                    : '可写（无响应）',
                child: const Icon(Icons.edit, size: 15, color: Colors.green),
              ),
            ],
            if (isNotifiable) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: isIndicate ? '可 Indicate' : '可 Notify',
                child: Icon(Icons.notifications,
                    size: 15, color: Colors.orange.shade700),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 读取按钮
            if (isReadable)
              IconButton(
                tooltip: '读取一次',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => _readCharacteristic(),
                icon: const Icon(Icons.download, size: 18),
              ),
            // Notify 订阅切换
            if (isNotifiable)
              IconButton(
                tooltip: _subscribed ? '取消订阅' : '订阅 Notify',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => _toggleSubscribe(isIndicate),
                icon: Icon(
                  _subscribed
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  size: 18,
                  color: _subscribed ? Colors.orange.shade700 : null,
                ),
              ),
            // 设为发送目标
            if (isWritable)
              IconButton(
                tooltip: '设为发送目标',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  widget.session
                      .selectCharacteristic(widget.serviceId, ch.uuid);
                },
                icon: Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_off,
                  size: 18,
                  color: isSelected ? const Color(0xFF4A90D9) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _readCharacteristic() async {
    try {
      final data = await UniversalBle.read(
        widget.session.deviceId,
        widget.serviceId,
        widget.characteristic.uuid,
      );
      // 读到的数据直接加入日志（单次读是一次性结果，不经过静默判帧）
      widget.session.appendReceiveLog(data,
          source: 'READ ${widget.characteristic.uuid}');
    } catch (e) {
      widget.session
          .appendSystemLog('读取 ${widget.characteristic.uuid} 失败：$e');
    }
  }

  Future<void> _toggleSubscribe(bool indication) async {
    if (_subscribed) {
      await widget.session.unsubscribeNotify(
        widget.serviceId,
        widget.characteristic.uuid,
      );
      setState(() => _subscribed = false);
    } else {
      await widget.session.subscribeNotify(
        widget.serviceId,
        widget.characteristic.uuid,
        indication: indication,
      );
      setState(() => _subscribed = true);
    }
  }
}
