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
    expect(fa.dimensions(1080, 1350), '۱۰۸۰ × ۱۳۵۰');
    expect(en.dimensions(1080, 1350), '1080 × 1350');
  });

  test('mapDigits preserves pre-formatted strings (trailing zeros)', () {
    expect(fa.mapDigits('2.00'), '۲٫۰۰');
    expect(en.mapDigits('2.00'), '2.00');
    expect(fa.mapDigits('1.5 KB'), '۱٫۵ KB');
  });
}
