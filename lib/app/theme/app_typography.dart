import 'package:flutter/material.dart';

/// Type-scale roles (design doc §2) — deliberately larger sizes and
/// taller line-heights than Material's defaults, tuned for Persian
/// body text (which needs more breathing room than the Latin-tuned
/// default `TextTheme`). RTL is the default script direction
/// throughout the app; these roles carry no directionality of their
/// own.
///
/// `fontFamily` and `color` are deliberately omitted:
/// * font family inherits from the ambient `Theme` (see
///   `AppTheme._uiFamilyFor`, which already resolves the Persian vs.
///   Latin UI face per locale) — every other screen in this app
///   composes raw `TextStyle`s the same way, so a role-specific
///   override here would be the one inconsistent copy.
/// * colour comes from `AppTokens` at the call site, since the same
///   role reads in `textPrimary` in one context and `textSecondary`
///   or `onBrand` in another.
///
/// **The one slot where that inheritance does NOT happen: a
/// `ButtonStyle.textStyle`.** `ButtonStyleButton` resolves that
/// property with `??` (never a merge) and hands the winner to
/// `Material.textStyle`, which REPLACES the ambient `DefaultTextStyle`
/// outright — so a role passed there arrives with `fontFamily: null`
/// and the label falls back to the platform UI face. Persian then
/// renders in the system font beside a screen of Vazir, which is
/// exactly how «مشاهده همه» ended up in the wrong face on Home.
///
/// So: put weight/size on the button's CHILD `Text` (whose style
/// merges into the inherited one) and leave `ButtonStyle` to colour
/// and geometry. `AppTheme` makes the same fix from the other side for
/// the component styles it owns — filled buttons, the nav bar and the
/// app bar each bake `fontFamily`/`fontFamilyFallback` in by hand.
abstract final class AppTypeScale {
  static const TextStyle display = TextStyle(
    fontSize: 44,
    fontWeight: FontWeight.w900,
    height: 1.05,
  );

  static const TextStyle titleLg = TextStyle(
    fontSize: 23,
    fontWeight: FontWeight.w900,
    height: 1.4,
  );

  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.5,
  );

  /// Weight 500 (the doc's "400/500" row defaults to the more
  /// emphasized of the two) — pass `.copyWith(fontWeight: FontWeight.w400)`
  /// for the plainer variant without altering size/line-height.
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.85,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.6,
  );
}
