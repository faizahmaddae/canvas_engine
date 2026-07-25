import 'package:flutter/widgets.dart';

/// Width [text] will actually occupy when painted in [context].
///
/// For deciding whether an optional segment fits before committing to
/// showing it — the app does this rather than ellipsising wherever the
/// thing at risk of being cut is a NUMBER, because half of "1080 ×
/// 1350" reads as a different canvas rather than as truncated text.
///
/// The two details that make this correct, and that a hand-rolled
/// `TextPainter` at each call site kept getting wrong:
///
///   * **Resolve the style first.** `AppTypeScale`'s roles omit
///     `fontFamily` on purpose — the family comes from the theme, and
///     under fa that is Vazir, whose Persian glyphs are appreciably
///     wider than the fallback a bare `TextStyle` measures in. A
///     painter fed the unresolved style under-measures and the caller
///     confidently paints a string that then gets clipped.
///   * **Carry the text scaler.** Otherwise every measurement assumes
///     the user left their system font size at the default.
double measuredTextWidth(
  BuildContext context,
  String text, {
  required TextStyle style,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}

/// True when [text] fits inside [maxWidth] as painted in [context].
bool textFits(
  BuildContext context,
  String text, {
  required TextStyle style,
  required double maxWidth,
}) => measuredTextWidth(context, text, style: style) <= maxWidth;
