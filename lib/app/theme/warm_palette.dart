import 'package:flutter/material.dart';

/// Shared warm-editorial palette for Home, Onboarding, and Templates
/// Browse — surfaces that intentionally lean on a bespoke warm-paper
/// look distinct from the app-wide Material theme (see [AppTheme]).
///
/// Unifies the former byte-identical `HomePalette`/`OnboardingPalette`
/// duplicates (Phase 4 plan §4.3). [of] resolves against the ambient
/// [Brightness] so these three surfaces get real dark-mode support —
/// today they hardcode the light values and render light-on-light
/// under the app's `ThemeMode.system` dark theme.
///
/// Migration is two steps (kept as separate commits) so the risk is
/// separable:
///   1. Mechanical — introduce this class and re-point every
///      consumer, but [of] always returns [_light] regardless of
///      brightness. Zero visual change, including preserving the
///      existing light-in-dark-mode bug for now.
///   2. Behavioural — [of] branches on brightness and returns a
///      designed [_dark] variant, gated on before/after simulator
///      screenshots (Phase 4 plan D5).
class WarmPalette {
  const WarmPalette._({
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.surface,
    required this.surfaceMuted,
    required this.canvasPaper,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.accent,
    required this.accentPressed,
    required this.accentSoft,
    required this.rose,
    required this.saffron,
    required this.shadow,
  });

  final Color backgroundTop;
  final Color backgroundBottom;
  final Color surface;
  final Color surfaceMuted;
  final Color canvasPaper;
  final Color ink;
  final Color muted;
  final Color hairline;
  final Color accent;
  final Color accentPressed;
  final Color accentSoft;
  final Color rose;
  final Color saffron;
  final Color shadow;

  /// Byte-identical to the former `HomePalette`/`OnboardingPalette`
  /// static constants.
  static const WarmPalette _light = WarmPalette._(
    backgroundTop: Color(0xFFFFFBF6),
    backgroundBottom: Color(0xFFF3F0FF),
    surface: Color(0xFFFFFEFC),
    surfaceMuted: Color(0xFFFAF7F2),
    canvasPaper: Color(0xFFFFFCF7),
    ink: Color(0xFF17151F),
    muted: Color(0xFF746C7E),
    hairline: Color(0xFFE9DFD7),
    accent: Color(0xFF7C5CFF),
    accentPressed: Color(0xFF6747F2),
    accentSoft: Color(0xFFF1ECFF),
    rose: Color(0xFFD87995),
    saffron: Color(0xFFE5A044),
    shadow: Color(0xFF3A2E46),
  );

  /// Step 1 (mechanical): always the light palette, regardless of
  /// [context]'s brightness. Step 2 will switch this on brightness.
  static WarmPalette of(BuildContext context) => _light;
}
