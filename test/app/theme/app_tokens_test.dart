import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Workstream B, Commit 1: locks in the AppTokens contract (design
/// doc §1) -- both instances resolve their documented values, and
/// `AppTokens.of(context)` picks the one matching the ambient theme
/// so widgets never need to branch on Brightness themselves.
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

  test('light instance matches the documented hex values', () {
    const t = AppTokens.light;
    expect(t.brand, const Color(0xFF7C5CFF));
    expect(t.brandStrong, const Color(0xFF6A4BF0));
    expect(t.brandPressed, const Color(0xFF5A3BD6));
    expect(t.brandSoft, const Color(0xFFF1ECFF));
    expect(t.onBrand, const Color(0xFFFFFFFF));
    expect(t.rose, const Color(0xFFD87995));
    expect(t.saffron, const Color(0xFFE5A044));
    expect(t.teal, const Color(0xFF22B8A0));
    expect(t.pageBg, const Color(0xFFFBFAF7));
    expect(t.surface, const Color(0xFFFFFFFF));
    expect(t.surfaceMuted, const Color(0xFFF4F1EC));
    expect(t.textPrimary, const Color(0xFF17151F));
    expect(t.textSecondary, const Color(0xFF6A6472));
    expect(t.textMuted, const Color(0xFF9A93A2));
    expect(t.border, const Color(0xFFEAE5DF));
  });

  test('dark instance flips surfaces/text but keeps brand + accents fixed', () {
    const l = AppTokens.light;
    const d = AppTokens.dark;

    expect(d.pageBg, const Color(0xFF0E0E13));
    expect(d.surface, const Color(0xFF17161D));
    expect(d.surfaceMuted, const Color(0xFF1F1E27));
    expect(d.textPrimary, const Color(0xFFF5F3F8));
    expect(d.textSecondary, const Color(0xFFB4AEC0));
    expect(d.textMuted, const Color(0xFF7C7688));
    expect(d.border, const Color(0xFF2A2833));
    expect(d.brandSoft, const Color(0xFF241E3A));

    // Fixed across brightness -- already mid/high saturation, reads
    // on both a near-white and a near-black background.
    expect(d.brand, l.brand);
    expect(d.brandStrong, l.brandStrong);
    expect(d.brandPressed, l.brandPressed);
    expect(d.onBrand, l.onBrand);
    expect(d.rose, l.rose);
    expect(d.saffron, l.saffron);
    expect(d.teal, l.teal);

    expect(d.surface, isNot(l.surface));
    expect(d.textPrimary, isNot(l.textPrimary));
    expect(d.pageBg, isNot(l.pageBg));
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
