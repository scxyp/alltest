import 'package:flutter/material.dart';

import 'app/debug_assistant_app.dart';
import 'core/bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DebugAssistantApp(registry: buildFeatureRegistry()));
}
