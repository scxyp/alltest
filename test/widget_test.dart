import 'package:flutter_test/flutter_test.dart';

import 'package:debug_assistant/app/debug_assistant_app.dart';
import 'package:debug_assistant/core/bootstrap.dart';

void main() {
  testWidgets('应用启动后展示已注册的调试功能', (tester) async {
    await tester.pumpWidget(
      DebugAssistantApp(registry: buildFeatureRegistry()),
    );
    await tester.pump();

    expect(find.text('多功能调试助手'), findsOneWidget);
    expect(find.text('串口调试'), findsOneWidget);
    expect(find.text('网络调试'), findsOneWidget);
    expect(find.text('Modbus 模拟器'), findsOneWidget);
    expect(find.text('蓝牙调试'), findsOneWidget);
    expect(find.text('USB 调试'), findsOneWidget);
    expect(find.text('MQTT 调试'), findsOneWidget);
    expect(find.text('CAN 调试'), findsOneWidget);
    expect(find.text('CANopen 调试'), findsOneWidget);
  });
}

