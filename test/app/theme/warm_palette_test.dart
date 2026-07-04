import 'package:canvas_engine/app/theme/warm_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks in the Phase 4 §4.3 WarmPalette contract: light values stay
/// byte-identical to the former HomePalette/OnboardingPalette
/// duplicates, and `of(context)` now resolves a real dark variant
/// (step 2 — the behavioural switch, gated on before/after simulator
/// screenshots) that flips ink/paper while keeping the three brand
/// accents (accent, rose, saffron) unchanged.
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

  testWidgets('light values match the former HomePalette/'
      'OnboardingPalette byte-identical constants', (tester) async {
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

    expect(palette.backgroundTop, const Color(0xFFFFFBF6));
    expect(palette.backgroundBottom, const Color(0xFFF3F0FF));
    expect(palette.surface, const Color(0xFFFFFEFC));
    expect(palette.surfaceMuted, const Color(0xFFFAF7F2));
    expect(palette.canvasPaper, const Color(0xFFFFFCF7));
    expect(palette.ink, const Color(0xFF17151F));
    expect(palette.muted, const Color(0xFF746C7E));
    expect(palette.hairline, const Color(0xFFE9DFD7));
    expect(palette.accent, const Color(0xFF7C5CFF));
    expect(palette.accentPressed, const Color(0xFF6747F2));
    expect(palette.accentSoft, const Color(0xFFF1ECFF));
    expect(palette.rose, const Color(0xFFD87995));
    expect(palette.saffron, const Color(0xFFE5A044));
    expect(palette.shadow, const Color(0xFF3A2E46));
  });

  testWidgets('dark values match the designed dark variant', (tester) async {
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

    expect(palette.backgroundTop, const Color(0xFF1C1A22));
    expect(palette.backgroundBottom, const Color(0xFF15131B));
    expect(palette.surface, const Color(0xFF221F29));
    expect(palette.surfaceMuted, const Color(0xFF2A2733));
    expect(palette.canvasPaper, const Color(0xFF262330));
    expect(palette.ink, const Color(0xFFF2EFF7));
    expect(palette.muted, const Color(0xFFACA3B9));
    expect(palette.hairline, const Color(0xFF3B3745));
    expect(palette.accent, const Color(0xFF7C5CFF));
    expect(palette.accentPressed, const Color(0xFF6747F2));
    expect(palette.accentSoft, const Color(0xFF362C55));
    expect(palette.rose, const Color(0xFFD87995));
    expect(palette.saffron, const Color(0xFFE5A044));
    expect(palette.shadow, const Color(0xFF000000));

    // Ink/paper flip vs. the light values (asserted above in the
    // previous test) and the three brand accents stay fixed.
    expect(palette.ink, isNot(const Color(0xFF17151F)));
    expect(palette.surface, isNot(const Color(0xFFFFFEFC)));
    expect(palette.backgroundTop, isNot(const Color(0xFFFFFBF6)));
    expect(palette.accent, const Color(0xFF7C5CFF));
    expect(palette.accentPressed, const Color(0xFF6747F2));
    expect(palette.rose, const Color(0xFFD87995));
    expect(palette.saffron, const Color(0xFFE5A044));
  });
}
