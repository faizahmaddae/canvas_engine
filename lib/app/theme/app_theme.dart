import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// App-wide design system: Material 3 colour schemes derived from a
/// single seed, plus a UI type scale and shared component shapes.
///
/// Both [light] and [dark] are produced from the same seed so the
/// brand identity (violet) carries through; M3 derives the rest.
abstract final class AppTheme {
  /// Brand seed — a refined violet that reads premium in dark mode
  /// and stays accessible in light mode after M3's tonal mapping.
  static const Color seed = Color(0xFF7C5CFF);

  /// Primary UI font for Latin scripts. Bundled in `pubspec.yaml`
  /// already (no `google_fonts` dependency needed). Hanken Grotesk
  /// is geometrically close to Inter and ships a real Bold weight.
  static const String _latinUiFamily = 'Hanken_Grotesk';
  static const String _persianUiFamily = 'Vazir_Regular';

  /// Persian fallback chain for later localization. Listed via
  /// `fontFamilyFallback` so Latin glyphs come from Hanken Grotesk
  /// and any unsupported codepoints fall through to a Persian
  /// family that's already in `pubspec.yaml`.
  static const List<String> _latinUiFallback = <String>[
    'IranianSans',
    'B_Yekan',
    'Gandom',
  ];

  static const List<String> _persianUiFallback = <String>[
    _latinUiFamily,
    'IranianSans',
    'B_Yekan',
    'Gandom',
  ];

  static ThemeData light({Locale? locale}) =>
      _build(Brightness.light, locale: locale);
  static ThemeData dark({Locale? locale}) =>
      _build(Brightness.dark, locale: locale);

  static ThemeData _build(Brightness brightness, {Locale? locale}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final uiFamily = _uiFamilyFor(locale);
    final uiFallback = _uiFallbackFor(locale);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: uiFamily,
      fontFamilyFallback: uiFallback,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, scheme, uiFamily, uiFallback),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ).copyWith(fontFamily: uiFamily, fontFamilyFallback: uiFallback),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: uiFamily,
            fontFamilyFallback: uiFallback,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 11,
            letterSpacing: 0,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: uiFamily,
          fontFamilyFallback: uiFallback,
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: scheme.onSurface,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  static String _uiFamilyFor(Locale? locale) =>
      locale?.languageCode == 'fa' ? _persianUiFamily : _latinUiFamily;

  static List<String> _uiFallbackFor(Locale? locale) =>
      locale?.languageCode == 'fa' ? _persianUiFallback : _latinUiFallback;

  static TextTheme _textTheme(
    TextTheme base,
    ColorScheme scheme,
    String uiFamily,
    List<String> uiFallback,
  ) {
    TextStyle s(double size, FontWeight w, {double letter = 0, double? h}) =>
        TextStyle(
          fontFamily: uiFamily,
          fontFamilyFallback: uiFallback,
          fontSize: size,
          fontWeight: w,
          letterSpacing: letter,
          height: h,
          color: scheme.onSurface,
        );

    return base.copyWith(
      displaySmall: s(32, FontWeight.w800, letter: -0.6, h: 1.1),
      headlineMedium: s(24, FontWeight.w800, letter: -0.4, h: 1.15),
      headlineSmall: s(20, FontWeight.w700, letter: -0.3, h: 1.2),
      titleLarge: s(18, FontWeight.w700, letter: -0.2, h: 1.2),
      titleMedium: s(16, FontWeight.w700, letter: -0.2, h: 1.25),
      titleSmall: s(14, FontWeight.w600, letter: -0.1, h: 1.3),
      bodyLarge: s(15, FontWeight.w500, letter: -0.1, h: 1.35),
      bodyMedium: s(14, FontWeight.w500, letter: -0.05, h: 1.4),
      bodySmall: s(
        12,
        FontWeight.w500,
        letter: 0,
        h: 1.35,
      ).copyWith(color: scheme.onSurfaceVariant),
      labelLarge: s(14, FontWeight.w600, letter: 0, h: 1.2),
      labelMedium: s(12, FontWeight.w600, letter: 0.1, h: 1.2),
      labelSmall: s(11, FontWeight.w600, letter: 0.2, h: 1.2),
    );
  }
}
