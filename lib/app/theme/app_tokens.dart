import 'package:flutter/material.dart';

/// Design-system colour tokens — v2 "Persian calligraphy-forward"
/// palette (docs/design-direction-v2-calligraphy-2026-07.md). The
/// token *system* is unchanged from the original design doc; only
/// the *values* pivoted: warm paper/ink neutrals with a single
/// saffron accent, replacing the generic violet. Wired into
/// [ThemeData] as a [ThemeExtension] so `AppTokens.of(context)`
/// always resolves the instance matching the ambient [Brightness].
///
/// v2 design rule: the primary/CTA fill is **ink on light, cream on
/// dark** ([brand]/[onBrand] swap roles across modes — they are NOT
/// fixed across brightness anymore). The three category accents
/// (rose/saffron/teal) stay fixed; they harmonise with the warm
/// system. [accent] is the saffron flourish colour and is tuned per
/// mode for contrast against paper vs. ink.
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brand,
    required this.brandStrong,
    required this.brandPressed,
    required this.brandSoft,
    required this.onBrand,
    required this.accent,
    required this.accentDeep,
    required this.accentText,
    required this.rose,
    required this.saffron,
    required this.teal,
    required this.roseOnText,
    required this.saffronOnText,
    required this.tealOnText,
    required this.pageBg,
    required this.surface,
    required this.surfaceMuted,
    required this.workspace,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderStrong,
  });

  // ─── primary (ink / cream) ─────────────────────────────────────
  /// Primary/CTA fill — ink in light mode, cream in dark.
  final Color brand;

  /// v2 has no separate "hero fill" concept (the old violet hero is
  /// gone); kept equal to [brand] for API stability.
  final Color brandStrong;

  /// Pressed variant of [brand]. Not in the v2 doc table — derived
  /// (ink lifted ~10% in light, cream dimmed ~10% in dark).
  final Color brandPressed;

  /// Soft ink-tint background. Not in the v2 doc table — derived
  /// from the paper/ink ramp for chip/tint use.
  final Color brandSoft;

  /// Text/icon on [brand] — paper on ink (light), ink on cream
  /// (dark). Mirrors [brand]'s cross-mode swap.
  final Color onBrand;

  // ─── saffron accent ────────────────────────────────────────────
  /// The single saffron accent (flourishes, marks). Per-mode tuned:
  /// deeper on paper, brighter on ink.
  final Color accent;

  /// Deeper saffron stop for pressed/emphasis pairings with
  /// [accent].
  final Color accentDeep;

  /// The saffron stop for **glyphs** — labels, links, section
  /// headers, active tile text, chevrons.
  ///
  /// [accent] is tuned as a FILL (diamonds, slider tracks, tints,
  /// borders) and at `#C0872A` it measures 2.92:1 on `surface`,
  /// 2.69:1 on `pageBg` and 2.29:1 on the crop bar — every light-mode
  /// text use of it failed WCAG AA, including the crop session's only
  /// Cancel and the sole cue for which tool is open. This keeps the
  /// same saffron hue and saturation, drops the value, and clears
  /// 4.5:1 on all five light backgrounds the accent lands on
  /// (surface 6.72, pageBg 6.21, active tile 6.02, selected option
  /// tile 4.57, crop bar 5.28). Dark mode already passed at 7.47:1,
  /// so there it stays equal to [accent].
  ///
  /// Rule: paint glyphs with this, everything else with [accent].
  final Color accentText;

  // ─── category accents (template thumbs; fixed across modes) ───
  final Color rose;
  final Color saffron;
  final Color teal;

  /// Dark on-text stop for a label sitting on the matching accent's
  /// *soft/tinted* background (not the vivid fill itself).
  final Color roseOnText;
  final Color saffronOnText;
  final Color tealOnText;

  // ─── neutrals / surfaces (warm paper ↔ deep ink) ───────────────
  final Color pageBg;
  final Color surface;
  final Color surfaceMuted;

  /// Editor canvas workspace — one step deeper than [surfaceMuted]
  /// so the editor's chrome (bars/panels on [surface]) visibly
  /// floats above it. Editor-scoped by convention: ordinary screens
  /// keep using [pageBg]/[surfaceMuted].
  final Color workspace;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;

  /// Boundary stop for components whose EDGE is load-bearing — the
  /// only thing separating an option tile from the panel behind it.
  ///
  /// [border] is a decorative hairline: it measures 1.31:1 on light
  /// `surface` and 1.19:1 on dark, which is fine for a divider between
  /// two labelled rows and useless as the sole outline of a control.
  /// Option tiles drawn with only a `surfaceMuted @35%` fill and a
  /// `border` hairline were invisible rectangles — a row of options
  /// read as floating glyphs with one highlighted box among them.
  /// This clears WCAG 1.4.11's 3:1 against every surface a bounded
  /// component sits on — `surface`, `pageBg`, `workspace` and the
  /// unselected tile fill — in BOTH modes. `token_contrast_test.dart`
  /// pins that; the first value chosen here cleared surface and fill
  /// and missed `pageBg` at 2.94:1, which is exactly the kind of
  /// near-miss the test exists to stop.
  final Color borderStrong;

  static const AppTokens light = AppTokens(
    brand: Color(0xFF1F1B16),
    brandStrong: Color(0xFF1F1B16),
    brandPressed: Color(0xFF3A342B),
    brandSoft: Color(0xFFE7E0D2),
    onBrand: Color(0xFFF4EEE1),
    accent: Color(0xFFC0872A),
    accentDeep: Color(0xFFA5731E),
    accentText: Color(0xFF735119),
    rose: Color(0xFFD87995),
    saffron: Color(0xFFE5A044),
    teal: Color(0xFF22B8A0),
    roseOnText: Color(0xFF5A1E2E),
    saffronOnText: Color(0xFF5A3B10),
    tealOnText: Color(0xFF0C3D34),
    pageBg: Color(0xFFF4EEE1),
    surface: Color(0xFFFBF7EF),
    surfaceMuted: Color(0xFFEDE5D4),
    workspace: Color(0xFFE7DCC4),
    textPrimary: Color(0xFF1F1B16),
    textSecondary: Color(0xFF6B6155),
    textMuted: Color(0xFF9C8F7C),
    border: Color(0xFFE3D9C6),
    borderStrong: Color(0xFF85785C),
  );

  static const AppTokens dark = AppTokens(
    brand: Color(0xFFF2EADB),
    brandStrong: Color(0xFFF2EADB),
    brandPressed: Color(0xFFDCD3C0),
    brandSoft: Color(0xFF2A251E),
    onBrand: Color(0xFF1F1B16),
    accent: Color(0xFFD4A24A),
    accentDeep: Color(0xFFC0872A),
    accentText: Color(0xFFD4A24A),
    rose: Color(0xFFD87995),
    saffron: Color(0xFFE5A044),
    teal: Color(0xFF22B8A0),
    roseOnText: Color(0xFF5A1E2E),
    saffronOnText: Color(0xFF5A3B10),
    tealOnText: Color(0xFF0C3D34),
    pageBg: Color(0xFF14110D),
    surface: Color(0xFF1E1A14),
    surfaceMuted: Color(0xFF26211A),
    workspace: Color(0xFF191510),
    textPrimary: Color(0xFFF2EADB),
    textSecondary: Color(0xFFA9A090),
    textMuted: Color(0xFF7C7264),
    border: Color(0xFF2E2820),
    borderStrong: Color(0xFF7B7060),
  );

  /// Resolves the instance matching the ambient theme's brightness.
  /// Falls back to [light] if the extension somehow isn't registered
  /// (defensive only — [AppTheme] always wires both).
  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ?? light;

  @override
  AppTokens copyWith({
    Color? brand,
    Color? brandStrong,
    Color? brandPressed,
    Color? brandSoft,
    Color? onBrand,
    Color? accent,
    Color? accentDeep,
    Color? accentText,
    Color? rose,
    Color? saffron,
    Color? teal,
    Color? roseOnText,
    Color? saffronOnText,
    Color? tealOnText,
    Color? pageBg,
    Color? surface,
    Color? surfaceMuted,
    Color? workspace,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? borderStrong,
  }) {
    return AppTokens(
      brand: brand ?? this.brand,
      brandStrong: brandStrong ?? this.brandStrong,
      brandPressed: brandPressed ?? this.brandPressed,
      brandSoft: brandSoft ?? this.brandSoft,
      onBrand: onBrand ?? this.onBrand,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      accentText: accentText ?? this.accentText,
      rose: rose ?? this.rose,
      saffron: saffron ?? this.saffron,
      teal: teal ?? this.teal,
      roseOnText: roseOnText ?? this.roseOnText,
      saffronOnText: saffronOnText ?? this.saffronOnText,
      tealOnText: tealOnText ?? this.tealOnText,
      pageBg: pageBg ?? this.pageBg,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      workspace: workspace ?? this.workspace,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      brand: c(brand, other.brand),
      brandStrong: c(brandStrong, other.brandStrong),
      brandPressed: c(brandPressed, other.brandPressed),
      brandSoft: c(brandSoft, other.brandSoft),
      onBrand: c(onBrand, other.onBrand),
      accent: c(accent, other.accent),
      accentDeep: c(accentDeep, other.accentDeep),
      accentText: c(accentText, other.accentText),
      rose: c(rose, other.rose),
      saffron: c(saffron, other.saffron),
      teal: c(teal, other.teal),
      roseOnText: c(roseOnText, other.roseOnText),
      saffronOnText: c(saffronOnText, other.saffronOnText),
      tealOnText: c(tealOnText, other.tealOnText),
      pageBg: c(pageBg, other.pageBg),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      workspace: c(workspace, other.workspace),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
    );
  }
}
