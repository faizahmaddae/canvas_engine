/// 4 / 8 dp spacing scale used across the app. Keep this short — if
/// a value isn't here, prefer composing two existing ones over
/// inventing a new one, so the app stays on a consistent rhythm.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Standard horizontal page gutter on phone widths.
  static const double pageGutter = 20;
}

/// Corner-radius tokens. Larger radii read more "premium" on dark
/// surfaces; the hero CTAs intentionally use the largest one.
abstract final class AppRadii {
  static const double button = 12;
  static const double card = 16;
  static const double hero = 24;
  static const double pill = 999;
}
