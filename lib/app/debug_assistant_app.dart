import 'package:flutter/material.dart';

import '../core/feature/feature_registry.dart';
import 'home_page.dart';

class DebugAssistantApp extends StatelessWidget {
  const DebugAssistantApp({super.key, required this.registry});

  final FeatureRegistry registry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '多功能调试助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3468F6),
        brightness: Brightness.light,
        visualDensity: VisualDensity.standard,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3468F6),
        brightness: Brightness.dark,
      ),
      home: HomePage(registry: registry),
    );
  }
}
