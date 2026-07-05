import 'package:canvas_engine/app/theme/warm_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks in the v2 WarmPalette contract: both variants live in the
/// calligraphy-forward paper/ink family (values match `AppTokens`),
/// the accent is saffron (per-mode tuned like `AppTokens.accent`),
/// and no slot in either mode is violet/plum any more.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Scaffold(body: child),
    );
  }

  testWidgets('light values sit in the v2 paper/ink family', (tester) async {
    late WarmPalette palette;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            palette = WarmPalette.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(palette.backgroundTop, const Color(0xFFFBF7EF));
    expect(palette.backgroundBottom, const Color(0xFFF4EEE1));
    expect(palette.surface, const Color(0xFFFBF7EF));
    expect(palette.surfaceMuted, const Color(0xFFEDE5D4));
    expect(palette.canvasPaper, const Color(0xFFFBF7EF));
    expect(palette.ink, const Color(0xFF1F1B16));
    expect(palette.muted, const Color(0xFF6B6155));
    expect(palette.hairline, const Color(0xFFE3D9C6));
    expect(palette.accent, const Color(0xFFC0872A));
    expect(palette.accentPressed, const Color(0xFFA5731E));
    expect(palette.accentSoft, const Color(0xFFF0E4CC));
    expect(palette.rose, const Color(0xFFD87995));
    expect(palette.saffron, const Color(0xFFE5A044));
    expect(palette.shadow, const Color(0xFF1F1B16));
  });

  testWidgets('dark values are deep warm ink (no slate-plum)', (tester) async {
    late WarmPalette palette;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            palette = WarmPalette.of(context);
            return const SizedBox.shrink();
          },
        ),
        brightness: Brightness.dark,
      ),
    );

    expect(palette.backgroundTop, const Color(0xFF1E1A14));
    expect(palette.backgroundBottom, const Color(0xFF14110D));
    expect(palette.surface, const Color(0xFF1E1A14));
    expect(palette.surfaceMuted, const Color(0xFF26211A));
    expect(palette.canvasPaper, const Color(0xFF221D16));
    expect(palette.ink, const Color(0xFFF2EADB));
    expect(palette.muted, const Color(0xFFA9A090));
    expect(palette.hairline, const Color(0xFF2E2820));
    expect(palette.accent, const Color(0xFFD4A24A));
    expect(palette.accentPressed, const Color(0xFFC0872A));
    expect(palette.accentSoft, const Color(0xFF3A301C));
    expect(palette.rose, const Color(0xFFD87995));
    expect(palette.saffron, const Color(0xFFE5A044));
    expect(palette.shadow, const Color(0xFF000000));

    // Ink/paper flip vs. the light values, decorative accents fixed,
    // and the retired violet is gone from every slot.
    expect(palette.ink, isNot(const Color(0xFF1F1B16)));
    expect(palette.surface, isNot(const Color(0xFFFBF7EF)));
    expect(palette.accent, isNot(const Color(0xFF7C5CFF)));
    expect(palette.rose, const Color(0xFFD87995));
    expect(palette.saffron, const Color(0xFFE5A044));
  });
}
