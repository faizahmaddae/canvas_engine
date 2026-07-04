import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/section_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders the text in textMuted', (tester) async {
    await tester.pumpWidget(host(const SectionLabel('Eyebrow')));
    final text = tester.widget<Text>(find.text('Eyebrow'));
    expect(text.style?.color, AppTokens.light.textMuted);
  });

  testWidgets('renders without throwing and flips textMuted in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const SectionLabel('Eyebrow'), brightness: Brightness.dark),
    );
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text('Eyebrow'));
    expect(text.style?.color, AppTokens.dark.textMuted);
  });
}
