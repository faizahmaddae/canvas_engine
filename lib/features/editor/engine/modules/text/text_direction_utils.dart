import 'package:flutter/painting.dart';

/// Heuristic: is [content] predominantly Arabic / Persian script?
///
/// Counts code points in the Arabic block (U+0600..U+06FF) plus
/// the Arabic Presentation Forms ranges (U+FB50..U+FDFF, U+FE70..
/// U+FEFF) and compares to the count of basic Latin letters. Empty
/// or punctuation-only text returns false (defaults to Latin).
///
/// Pure script-detection. Lives in the engine because [TextLayer]'s
/// render path needs the same answer for [TextDirection] resolution
/// and the engine cannot reach into application/domain code.
bool textIsArabicScript(String content) {
  var arabic = 0;
  var latin = 0;
  for (final rune in content.runes) {
    if ((rune >= 0x0600 && rune <= 0x06FF) ||
        (rune >= 0xFB50 && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF)) {
      arabic++;
    } else if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A)) {
      latin++;
    }
  }
  if (arabic == 0 && latin == 0) return false;
  return arabic >= latin;
}

/// Resolve the writing direction for [content] using the
/// Arabic-vs-Latin dominance heuristic from [textIsArabicScript].
/// Empty / punctuation-only text falls back to LTR.
TextDirection textDirectionForContent(String content) {
  return textIsArabicScript(content)
      ? TextDirection.rtl
      : TextDirection.ltr;
}
