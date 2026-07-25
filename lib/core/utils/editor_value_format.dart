import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Locale-aware numeric readouts for editor chrome (tb2 11/16).
///
/// ~30 readout sites hardcoded Latin-digit `'${v}px'` / `'${v}%'`
/// interpolations while the fa locale (the product default) writes
/// its own strings with Persian digits and `٪` — mixed-script
/// numerals all over the Persian UI, and VoiceOver announcing Latin
/// digit strings inside Persian sentences. Every readout formats
/// through this helper instead; the format is also what
/// `semanticFormatterCallback` announces, so visual and spoken
/// values can't diverge.
///
/// Kept deliberately tiny: digits + the three units the editor
/// actually shows (px, %, °). Not a general i18n number formatter —
/// no grouping, no decimals beyond what callers pre-round.
class EditorValueFormat {
  const EditorValueFormat._(this._fa);

  final bool _fa;

  /// Resolve from the ambient locale. Persian gets Persian digits;
  /// every other locale gets ASCII.
  factory EditorValueFormat.of(BuildContext context) =>
      EditorValueFormat.forLanguage(
        Localizations.maybeLocaleOf(context)?.languageCode,
      );

  /// Locale-code variant for call sites without a context (and for
  /// tests).
  factory EditorValueFormat.forLanguage(String? languageCode) =>
      EditorValueFormat._(languageCode == 'fa');

  static const _persianDigits = [
    '۰',
    '۱',
    '۲',
    '۳',
    '۴',
    '۵',
    '۶',
    '۷',
    '۸',
    '۹',
  ];

  /// The number itself, locale-digit mapped. Accepts anything whose
  /// toString is digits/minus/dot (callers pre-round as they always
  /// did).
  String digits(num value) => mapDigits(value.toString());

  /// Locale-digit map over an ALREADY-formatted numeric string —
  /// for values whose formatting carries meaning `toString` would
  /// lose (`toStringAsFixed(2)`'s trailing zeros in the export
  /// file-size line). Only digits and the decimal point are mapped;
  /// everything else passes through untouched.
  String mapDigits(String s) {
    if (!_fa) return s;
    final b = StringBuffer();
    for (final code in s.codeUnits) {
      if (code >= 0x30 && code <= 0x39) {
        b.write(_persianDigits[code - 0x30]);
      } else if (code == 0x2E) {
        b.write('٫'); // Arabic decimal separator
      } else {
        b.writeCharCode(code);
      }
    }
    return b.toString();
  }

  /// Fold locale digits back to ASCII so `int.parse` / `double.parse`
  /// accept them — the inverse of [mapDigits] for *input* fields.
  ///
  /// Needed wherever a numeric field is seeded with [digits] (the
  /// export custom-size dialog) or where a Persian keyboard can put
  /// its own numerals into a field we then parse. Covers both the
  /// Extended Arabic-Indic block Persian uses (U+06F0..U+06F9) and the
  /// Arabic-Indic block (U+0660..U+0669) an Arabic keyboard produces,
  /// plus the `٫` decimal separator. Static because input arrives
  /// before any locale decision matters: every digit set folds the
  /// same way.
  /// Input formatter for a digits-only field in a Persian-first app.
  ///
  /// `FilteringTextInputFormatter.digitsOnly` allows `[0-9]` and
  /// nothing else, so a Persian keyboard's ۸۰۰ was deleted keystroke
  /// by keystroke — the field stayed empty while the user watched
  /// themselves type into it. This accepts all three digit sets the
  /// app can receive; fold the result through [toAsciiDigits] before
  /// parsing.
  static final TextInputFormatter localeDigitsOnly =
      FilteringTextInputFormatter.allow(
        RegExp(r'[0-9\u06F0-\u06F9\u0660-\u0669]'),
      );

  static String toAsciiDigits(String s) {
    final b = StringBuffer();
    for (final code in s.codeUnits) {
      if (code >= 0x06F0 && code <= 0x06F9) {
        b.writeCharCode(0x30 + (code - 0x06F0));
      } else if (code >= 0x0660 && code <= 0x0669) {
        b.writeCharCode(0x30 + (code - 0x0660));
      } else if (code == 0x066B) {
        b.write('.'); // Arabic decimal separator
      } else {
        b.writeCharCode(code);
      }
    }
    return b.toString();
  }

  /// `96px` / `۹۶px` — the pixel unit stays Latin in both scripts
  /// (matches the shipped fa design language, e.g. the size panel's
  /// keypad label).
  String px(num value) => '${digits(value)}px';

  /// `40%` / `۴۰٪` — fa uses ARABIC PERCENT SIGN with no space,
  /// matching the existing fa arb strings.
  String percent(num value) => _fa ? '${digits(value)}٪' : '$value%';

  /// `135°` / `۱۳۵°`.
  String degrees(num value) => '${digits(value)}°';

  /// `1080 × 1350` with locale digits, and in THAT order under RTL.
  ///
  /// Without the isolate this is a genuine wrong-information bug, not
  /// a cosmetic one. `W × H` is two number runs around a neutral `×`;
  /// in an RTL paragraph the bidi algorithm resolves that neutral to
  /// the paragraph direction and renders the pair right-to-left, so
  /// a 1080 × 1350 canvas displayed as "1350 × 1080" — the user reads
  /// the wrong dimensions. Square documents hide it, which is why
  /// every capture missed it: the capture fixture is 1080 × 1080.
  ///
  /// LRI … PDI (U+2066 / U+2069) isolates the whole expression as one
  /// left-to-right run, so the order survives regardless of the
  /// surrounding paragraph direction. Isolating each number alone
  /// would NOT work — the `×` between two isolates is still neutral.
  String dimensions(num w, num h) =>
      '\u2066${digits(w)} \u00D7 ${digits(h)}\u2069';

  /// `+12` / `+۱۲` — a signed delta, with the sign kept in
  /// FRONT of the number.
  ///
  /// Same isolate, same reason as [dimensions] on a smaller scale: a
  /// leading `+` is a bidi-neutral, so in an RTL paragraph it drifts to
  /// the far side of the digits and `+12` paints as `12+`. Negative
  /// values carry U+2212 MINUS rather than a hyphen so the glyph reads
  /// as arithmetic and matches the `+`'s weight.
  String signed(num value) {
    final r = value.round();
    if (r == 0) return digits(0);
    final sign = r > 0 ? '+' : '\u2212';
    return '\u2066$sign${digits(r.abs())}\u2069';
  }
}
