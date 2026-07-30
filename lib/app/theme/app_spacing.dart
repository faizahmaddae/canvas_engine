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
///
/// Design-system doc §3 ("pill/button 14, card 16, sheet-top 26,
/// thumb 12") reconciles onto this class rather than duplicating it:
/// `card` (16) already matches exactly; `thumb` (12, `TemplateThumb`)
/// coincides with [button] today and reuses it directly rather than
/// adding a same-valued alias. Only [primaryButton] (14) and
/// [sheetTop] (26) are genuinely new values.
abstract final class AppRadii {
  static const double button = 12;
  static const double card = 16;
  static const double hero = 24;
  static const double pill = 999;

  /// `AppPrimaryButton`'s corner radius — distinct from [button]
  /// (Material `FilledButton`/`IconButton` shape) since the two are
  /// allowed to diverge independently later.
  static const double primaryButton = 14;

  /// Top-corner radius for a sheet rising off the surface behind it
  /// (design doc §4). Bottom corners stay square — a sheet is
  /// anchored to the edge it rises from.
  static const double sheetTop = 26;
}
