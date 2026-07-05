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
///   2. Behavioural (this step) — [of] branches on brightness and
///      returns a designed [_dark] variant, gated on before/after
///      simulator screenshots (Phase 4 plan D5).
///
/// Dark variant design rule: ink↔paper flips (near-black text becomes
/// warm cream, warm paper becomes deep ink), the saffron accent is
/// tuned brighter per mode (like `AppTokens.accent`), the two
/// decorative accents (rose, saffron) stay fixed since they're
/// mid-brightness and read fine on both backgrounds, and `shadow`
/// drops to a near-black so elevation still reads against a dark
/// surface (a colour-tinted shadow disappears at low lightness).
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

  /// v2 recolour: the legacy violet accent and plum-tinted neutrals
  /// converged on the calligraphy-forward paper/ink/saffron family
  /// (values from `AppTokens.light`) so no surface outside the
  /// document canvas can render violet.
  static const WarmPalette _light = WarmPalette._(
    backgroundTop: Color(0xFFFBF7EF),
    backgroundBottom: Color(0xFFF4EEE1),
    surface: Color(0xFFFBF7EF),
    surfaceMuted: Color(0xFFEDE5D4),
    canvasPaper: Color(0xFFFBF7EF),
    ink: Color(0xFF1F1B16),
    muted: Color(0xFF6B6155),
    hairline: Color(0xFFE3D9C6),
    accent: Color(0xFFC0872A),
    accentPressed: Color(0xFFA5731E),
    accentSoft: Color(0xFFF0E4CC),
    rose: Color(0xFFD87995),
    saffron: Color(0xFFE5A044),
    shadow: Color(0xFF1F1B16),
  );

  /// Dark counterpart of [_light] — deep warm ink (values from
  /// `AppTokens.dark`), not the old slate-plum, so dark mode reads
  /// as the same paper/ink family as the rest of v2.
  static const WarmPalette _dark = WarmPalette._(
    backgroundTop: Color(0xFF1E1A14),
    backgroundBottom: Color(0xFF14110D),
    surface: Color(0xFF1E1A14),
    surfaceMuted: Color(0xFF26211A),
    canvasPaper: Color(0xFF221D16),
    ink: Color(0xFFF2EADB),
    muted: Color(0xFFA9A090),
    hairline: Color(0xFF2E2820),
    accent: Color(0xFFD4A24A),
    accentPressed: Color(0xFFC0872A),
    accentSoft: Color(0xFF3A301C),
    rose: Color(0xFFD87995),
    saffron: Color(0xFFE5A044),
    shadow: Color(0xFF000000),
  );

  /// Resolves against the ambient [Brightness] — see the class doc
  /// for the two-step migration this landed in.
  static WarmPalette of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? _dark : _light;
  }
}
