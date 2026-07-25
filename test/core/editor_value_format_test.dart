// tb2 11/16: locale-aware editor readouts. fa (the product default)
// gets Persian digits + the Arabic percent sign; everything else
// gets ASCII. These pins are what the ~30 migrated readout sites
// rely on.

import 'package:canvas_engine/core/utils/editor_value_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fa = EditorValueFormat.forLanguage('fa');
  final en = EditorValueFormat.forLanguage('en');

  test('digits map to Persian under fa, ASCII elsewhere', () {
    expect(fa.digits(96), '۹۶');
    expect(fa.digits(-12), '-۱۲');
    expect(fa.digits(2.5), '۲٫۵');
    expect(en.digits(96), '96');
    expect(EditorValueFormat.forLanguage(null).digits(7), '7');
  });

  test('px keeps the Latin unit in both scripts', () {
    expect(fa.px(96), '۹۶px');
    expect(en.px(96), '96px');
  });

  test('percent uses ٪ with no space under fa', () {
    expect(fa.percent(40), '۴۰٪');
    expect(en.percent(40), '40%');
  });

  test('degrees and dimensions', () {
    expect(fa.degrees(135), '۱۳۵°');
    expect(en.degrees(135), '135°');
    // Dimensions carry bidi isolates — see the dedicated test below
    // for why. Compare on the stripped form here.
    expect(
      fa.dimensions(1080, 1350).replaceAll(RegExp('[\u2066\u2069]'), ''),
      '۱۰۸۰ × ۱۳۵۰',
    );
    expect(
      en.dimensions(1080, 1350).replaceAll(RegExp('[\u2066\u2069]'), ''),
      '1080 × 1350',
    );
  });

  test('dimensions isolate the pair so RTL cannot reverse W and H', () {
    // The bug this guards (found on an Android device, tb7 7/7):
    // `W × H` is two number runs around a NEUTRAL '×'. In an RTL
    // paragraph bidi resolves that neutral to the paragraph direction
    // and paints the pair right-to-left, so a 1080 × 1350 canvas read
    // as "1350 × 1080" — wrong information, not a cosmetic nit.
    // Square documents hide it, which is why the captures never did.
    const lri = '\u2066';
    const pdi = '\u2069';
    expect(fa.dimensions(1080, 1350), '$lri۱۰۸۰ × ۱۳۵۰$pdi');
    expect(en.dimensions(1920, 1080), '${lri}1920 × 1080$pdi');

    // The width still precedes the height inside the isolate — the
    // whole point is that the ORDER is what survives.
    final stripped = fa
        .dimensions(1080, 1350)
        .replaceAll(lri, '')
        .replaceAll(pdi, '');
    expect(stripped.indexOf('۱۰۸۰'), lessThan(stripped.indexOf('۱۳۵۰')));
  });

  test('mapDigits preserves pre-formatted strings (trailing zeros)', () {
    expect(fa.mapDigits('2.00'), '۲٫۰۰');
    expect(en.mapDigits('2.00'), '2.00');
    expect(fa.mapDigits('1.5 KB'), '۱٫۵ KB');
  });
}
