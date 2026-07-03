import 'package:flutter/painting.dart';

/// User-facing direction mode for a text layer.
///
/// [auto] resolves from the first strong script character in the
/// content. [rtl] and [ltr] force the base paragraph direction while
/// leaving font selection and glyph shaping to the existing text
/// pipeline.
enum TextDirectionMode { auto, rtl, ltr }

/// Heuristic: should [content]'s base script be Arabic / Persian?
///
/// Scans for the first strong Arabic/Persian or basic Latin letter.
/// Digits, punctuation, whitespace, emoji and symbols are skipped.
/// Empty or neutral-only text returns false (defaults to Latin).
///
/// Pure script-detection. Lives in the engine because [TextLayer]'s
/// render path needs the same answer for [TextDirection] resolution
/// and the engine cannot reach into application/domain code.
bool textIsArabicScript(String content) {
  for (final rune in content.runes) {
    if ((rune >= 0x0600 && rune <= 0x06FF) ||
        (rune >= 0xFB50 && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF)) {
      return true;
    } else if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A)) {
      return false;
    }
  }
  return false;
}

/// Resolve the writing direction for [content] and [mode].
///
/// [TextDirectionMode.auto] uses the first-strong-character heuristic
/// from [textIsArabicScript]. Empty / punctuation-only text falls
/// back to LTR.
TextDirection textDirectionForContent(
  String content, {
  TextDirectionMode mode = TextDirectionMode.auto,
}) {
  switch (mode) {
    case TextDirectionMode.auto:
      return textIsArabicScript(content)
          ? TextDirection.rtl
          : TextDirection.ltr;
    case TextDirectionMode.rtl:
      return TextDirection.rtl;
    case TextDirectionMode.ltr:
      return TextDirection.ltr;
  }
}
