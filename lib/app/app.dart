import 'package:flutter/material.dart';

import '../features/shell/presentation/root_shell.dart';
import 'theme/app_theme.dart';

/// Root MaterialApp. Owns the light/dark theme pair and hosts the
/// app shell (bottom navigation + tabs). Locale is intentionally
/// not set yet — adding `flutter_localizations` + a `locale: fa`
/// override is the future RTL/Persian milestone, and the entire
/// widget tree is already written with directional primitives so
/// that switch will be a single line here.
class CanvasEngineApp extends StatelessWidget {
  const CanvasEngineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Canvas',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const RootShell(),
    );
  }
}
