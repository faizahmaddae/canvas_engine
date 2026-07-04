import 'package:canvas_engine/app/theme/warm_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks in the Phase 4 §4.3 step-1 constraints: WarmPalette's light
/// values must stay byte-identical to the former HomePalette/
/// OnboardingPalette duplicates, and `of(context)` must not yet vary
/// with brightness (that's step 2, gated on screenshots).
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MediaQuery(
      data: MediaQueryData(platformBrightness: brightness),
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: ThemeMode.system,
        home: Scaffold(body: child),
      ),
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

  testWidgets('step 1: of(context) returns the same values under a '
      'dark platform brightness (deliberate — behavioural switch is '
      'step 2, gated on screenshots)', (tester) async {
    late WarmPalette light;
    late WarmPalette dark;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            light = WarmPalette.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            dark = WarmPalette.of(context);
            return const SizedBox.shrink();
          },
        ),
        brightness: Brightness.dark,
      ),
    );

    expect(dark.ink, light.ink);
    expect(dark.surface, light.surface);
    expect(dark.backgroundTop, light.backgroundTop);
  });
}
