// Dimension strings carry bidi isolates (U+2066 / U+2069) so that
// `W × H` cannot be reversed by an RTL paragraph — see
// `EditorValueFormat.dimensions`. Tests assert on the human-readable
// form, so they strip the marks first.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The isolate characters `EditorValueFormat.dimensions` wraps with.
const String kLri = '\u2066';
const String kPdi = '\u2069';

/// NO-BREAK SPACE. `EditorValueFormat.dimensions` uses it instead of
/// U+0020 so the pair carries no break opportunity inside its isolate
/// — an ordinary space let the line breaker split «۱۰۸۰ × ۱۳۵۰» and
/// drop the height, which reads as a different canvas size.
const String kNbsp = '\u00A0';

/// Drop bidi isolate marks and normalise no-break spaces so an
/// expectation can read naturally. Tests assert on what a person
/// sees, not on which space codepoint carries it.
String stripBidi(String s) =>
    s.replaceAll(kLri, '').replaceAll(kPdi, '').replaceAll(kNbsp, ' ');

/// `find.text`, but isolate-insensitive.
Finder findBidiText(String expected) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && stripBidi(w.data!) == expected,
  description: 'Text "$expected" (ignoring bidi isolates)',
);

/// `find.textContaining`, but isolate- and nbsp-insensitive.
Finder findBidiTextContaining(String expected) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && stripBidi(w.data!).contains(expected),
  description: 'Text containing "$expected" (ignoring bidi isolates)',
);
