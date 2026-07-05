import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks in the AppTokens v2 contract (docs/design-direction-v2-
/// calligraphy-2026-07.md): warm paper/ink neutrals, ink/cream
/// primary that SWAPS across brightness, per-mode saffron accent,
/// and fixed category accents. `AppTokens.of(context)` picks the
/// instance matching the ambient theme.
void main() {
  Widget host(Widget child, {required Brightness brightness}) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Scaffold(body: child),
    );
  }

  test('light instance matches the documented v2 hex values', () {
    const t = AppTokens.light;
    expect(t.brand, const Color(0xFF1F1B16)); // primary/CTA = ink
    expect(t.onBrand, const Color(0xFFF4EEE1));
    expect(t.brandStrong, t.brand, reason: 'v2 has no separate hero fill');
    expect(t.accent, const Color(0xFFC0872A)); // saffron
    expect(t.accentDeep, const Color(0xFFA5731E));
    expect(t.rose, const Color(0xFFD87995));
    expect(t.saffron, const Color(0xFFE5A044));
    expect(t.teal, const Color(0xFF22B8A0));
    expect(t.pageBg, const Color(0xFFF4EEE1)); // warm paper
    expect(t.surface, const Color(0xFFFBF7EF));
    expect(t.surfaceMuted, const Color(0xFFEDE5D4));
    expect(t.textPrimary, const Color(0xFF1F1B16));
    expect(t.textSecondary, const Color(0xFF6B6155));
    expect(t.textMuted, const Color(0xFF9C8F7C));
    expect(t.border, const Color(0xFFE3D9C6));
  });

  test('dark instance matches the documented v2 hex values', () {
    const t = AppTokens.dark;
    expect(t.brand, const Color(0xFFF2EADB)); // primary/CTA = cream
    expect(t.onBrand, const Color(0xFF1F1B16));
    expect(t.brandStrong, t.brand, reason: 'v2 has no separate hero fill');
    expect(t.accent, const Color(0xFFD4A24A)); // brighter saffron on ink
    expect(t.accentDeep, const Color(0xFFC0872A));
    expect(t.pageBg, const Color(0xFF14110D)); // deep ink
    expect(t.surface, const Color(0xFF1E1A14));
    expect(t.surfaceMuted, const Color(0xFF26211A));
    expect(t.textPrimary, const Color(0xFFF2EADB));
    expect(t.textSecondary, const Color(0xFFA9A090));
    expect(t.textMuted, const Color(0xFF7C7264));
    expect(t.border, const Color(0xFF2E2820));
  });

  test('primary swaps ink/cream across modes; category accents stay '
      'fixed', () {
    const l = AppTokens.light;
    const d = AppTokens.dark;

    // The v2 signature: brand/onBrand mirror each other across modes.
    expect(l.brand, isNot(d.brand));
    expect(l.brand, d.onBrand); // ink
    expect(l.onBrand, isNot(d.onBrand));

    // Saffron accent is per-mode tuned, deeper stop shifts with it.
    expect(l.accent, isNot(d.accent));
    expect(d.accentDeep, l.accent);

    // Category accents fixed — they harmonise with the warm system.
    expect(d.rose, l.rose);
    expect(d.saffron, l.saffron);
    expect(d.teal, l.teal);

    // Neutrals flip paper <-> ink.
    expect(d.pageBg, isNot(l.pageBg));
    expect(d.textPrimary, isNot(l.textPrimary));
  });

  testWidgets('AppTokens.of resolves light in a light theme', (tester) async {
    late AppTokens tokens;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            tokens = AppTokens.of(context);
            return const SizedBox.shrink();
          },
        ),
        brightness: Brightness.light,
      ),
    );
    expect(tokens.surface, AppTokens.light.surface);
  });

  testWidgets('AppTokens.of resolves dark in a dark theme', (tester) async {
    late AppTokens tokens;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            tokens = AppTokens.of(context);
            return const SizedBox.shrink();
          },
        ),
        brightness: Brightness.dark,
      ),
    );
    expect(tokens.surface, AppTokens.dark.surface);
  });

  testWidgets('AppTheme.light/.dark build without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
