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
  String digits(num value) {
    final s = value.toString();
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

  /// `96px` / `۹۶px` — the pixel unit stays Latin in both scripts
  /// (matches the shipped fa design language, e.g. the size panel's
  /// keypad label).
  String px(num value) => '${digits(value)}px';

  /// `40%` / `۴۰٪` — fa uses ARABIC PERCENT SIGN with no space,
  /// matching the existing fa arb strings.
  String percent(num value) => _fa ? '${digits(value)}٪' : '$value%';

  /// `135°` / `۱۳۵°`.
  String degrees(num value) => '${digits(value)}°';

  /// `1080 × 1080` with locale digits.
  String dimensions(num w, num h) => '${digits(w)} × ${digits(h)}';
}
