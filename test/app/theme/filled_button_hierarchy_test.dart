import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// v2 button emphasis contract: FilledButton is the ink/cream primary
/// CTA (scheme.primary = tokens.brand) while FilledButton.tonal is a
/// clearly lower-emphasis muted fill (scheme.secondaryContainer =
/// tokens.surfaceMuted) — the two must never render identically.
void main() {
  Future<({Color filled, Color tonal, Color tonalFg})> resolve(
    WidgetTester tester,
    Brightness brightness,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('primary')),
              FilledButton.tonal(onPressed: () {}, child: const Text('tonal')),
            ],
          ),
        ),
      ),
    );

    Color bg(String label) {
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(FilledButton),
        ),
      );
      final ctx = tester.element(find.text(label));
      // Same precedence the widget applies: themed style first,
      // per-variant defaults fill the gaps.
      final style = (FilledButtonTheme.of(ctx).style ?? const ButtonStyle())
          .merge(button.defaultStyleOf(ctx));
      return style.backgroundColor!.resolve(const {})!;
    }

    Color fg(String label) {
      final ctx = tester.element(find.text(label));
      return DefaultTextStyle.of(ctx).style.color!;
    }

    return (filled: bg('primary'), tonal: bg('tonal'), tonalFg: fg('tonal'));
  }

  testWidgets('light: primary=brand ink, tonal=surfaceMuted + ink text', (
    tester,
  ) async {
    final c = await resolve(tester, Brightness.light);
    expect(c.filled, AppTokens.light.brand);
    expect(c.tonal, AppTokens.light.surfaceMuted);
    expect(c.tonalFg, AppTokens.light.textPrimary);
    expect(c.filled, isNot(c.tonal));
  });

  testWidgets('dark: primary=brand cream, tonal=surfaceMuted + cream text', (
    tester,
  ) async {
    final c = await resolve(tester, Brightness.dark);
    expect(c.filled, AppTokens.dark.brand);
    expect(c.tonal, AppTokens.dark.surfaceMuted);
    expect(c.tonalFg, AppTokens.dark.textPrimary);
    expect(c.filled, isNot(c.tonal));
  });
}
