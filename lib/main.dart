import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/memory/memory_guard.dart';

void main() {
  // Required so [installMemoryGuard] can register a
  // [WidgetsBindingObserver] before runApp pumps the first frame.
  WidgetsFlutterBinding.ensureInitialized();
  installMemoryGuard();
  runApp(const ProviderScope(child: CanvasEngineApp()));
}
