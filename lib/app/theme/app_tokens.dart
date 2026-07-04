import 'package:flutter/material.dart';

/// Design-system colour tokens (Workstream B, design doc §1) — the
/// seed every new screen builds on instead of hardcoding colours or
/// reaching for a per-screen palette. Wired into [ThemeData] as a
/// [ThemeExtension] so `AppTokens.of(context)` always resolves the
/// instance matching the ambient [Brightness].
///
/// Unlike [WarmPalette] (kept for Home/Onboarding's warm-editorial
/// surfaces until they migrate), most values here stay fixed across
/// brightness by design: `brand`/`brandStrong`/`brandPressed` and the
/// three category accents are already mid-to-high saturation and read
/// on both a near-white and a near-black background. Only the tint
/// (`brandSoft`) and the neutral surface/text/border ramps flip.
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brand,
    required this.brandStrong,
    required this.brandPressed,
    required this.brandSoft,
    required this.onBrand,
    required this.rose,
    required this.saffron,
    required this.teal,
    required this.roseOnText,
    required this.saffronOnText,
    required this.tealOnText,
    required this.pageBg,
    required this.surface,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
  });

  // ─── brand ─────────────────────────────────────────────────────
  final Color brand;
  final Color brandStrong;
  final Color brandPressed;
  final Color brandSoft;
  final Color onBrand;

  // ─── category accents (template thumbs; reused app-wide) ──────
  final Color rose;
  final Color saffron;
  final Color teal;

  /// Dark on-text stop for a label sitting on the matching accent's
  /// *soft/tinted* background (not the vivid fill itself, which
  /// pairs with [onBrand]-style light text instead).
  final Color roseOnText;
  final Color saffronOnText;
  final Color tealOnText;

  // ─── neutrals / surfaces ────────────────────────────────────────
  final Color pageBg;
  final Color surface;
  final Color surfaceMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;

  static const AppTokens light = AppTokens(
    brand: Color(0xFF7C5CFF),
    brandStrong: Color(0xFF6A4BF0),
    brandPressed: Color(0xFF5A3BD6),
    brandSoft: Color(0xFFF1ECFF),
    onBrand: Color(0xFFFFFFFF),
    rose: Color(0xFFD87995),
    saffron: Color(0xFFE5A044),
    teal: Color(0xFF22B8A0),
    roseOnText: Color(0xFF5A1E2E),
    saffronOnText: Color(0xFF5A3B10),
    tealOnText: Color(0xFF0C3D34),
    pageBg: Color(0xFFFBFAF7),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF4F1EC),
    textPrimary: Color(0xFF17151F),
    textSecondary: Color(0xFF6A6472),
    textMuted: Color(0xFF9A93A2),
    border: Color(0xFFEAE5DF),
  );

  static const AppTokens dark = AppTokens(
    brand: Color(0xFF7C5CFF),
    brandStrong: Color(0xFF6A4BF0),
    brandPressed: Color(0xFF5A3BD6),
    brandSoft: Color(0xFF241E3A),
    onBrand: Color(0xFFFFFFFF),
    rose: Color(0xFFD87995),
    saffron: Color(0xFFE5A044),
    teal: Color(0xFF22B8A0),
    roseOnText: Color(0xFF5A1E2E),
    saffronOnText: Color(0xFF5A3B10),
    tealOnText: Color(0xFF0C3D34),
    pageBg: Color(0xFF0E0E13),
    surface: Color(0xFF17161D),
    surfaceMuted: Color(0xFF1F1E27),
    textPrimary: Color(0xFFF5F3F8),
    textSecondary: Color(0xFFB4AEC0),
    textMuted: Color(0xFF7C7688),
    border: Color(0xFF2A2833),
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
    Color? rose,
    Color? saffron,
    Color? teal,
    Color? roseOnText,
    Color? saffronOnText,
    Color? tealOnText,
    Color? pageBg,
    Color? surface,
    Color? surfaceMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
  }) {
    return AppTokens(
      brand: brand ?? this.brand,
      brandStrong: brandStrong ?? this.brandStrong,
      brandPressed: brandPressed ?? this.brandPressed,
      brandSoft: brandSoft ?? this.brandSoft,
      onBrand: onBrand ?? this.onBrand,
      rose: rose ?? this.rose,
      saffron: saffron ?? this.saffron,
      teal: teal ?? this.teal,
      roseOnText: roseOnText ?? this.roseOnText,
      saffronOnText: saffronOnText ?? this.saffronOnText,
      tealOnText: tealOnText ?? this.tealOnText,
      pageBg: pageBg ?? this.pageBg,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
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
      rose: c(rose, other.rose),
      saffron: c(saffron, other.saffron),
      teal: c(teal, other.teal),
      roseOnText: c(roseOnText, other.roseOnText),
      saffronOnText: c(saffronOnText, other.saffronOnText),
      tealOnText: c(tealOnText, other.tealOnText),
      pageBg: c(pageBg, other.pageBg),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      border: c(border, other.border),
    );
  }
}
