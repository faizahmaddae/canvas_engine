// Dimension strings carry bidi isolates (U+2066 / U+2069) so that
// `W × H` cannot be reversed by an RTL paragraph — see
// `EditorValueFormat.dimensions`. Tests assert on the human-readable
// form, so they strip the marks first.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The isolate characters `EditorValueFormat.dimensions` wraps with.
const String kLri = '\u2066';
const String kPdi = '\u2069';

/// Drop bidi isolate marks so an expectation can read naturally.
String stripBidi(String s) => s.replaceAll(kLri, '').replaceAll(kPdi, '');

/// `find.text`, but isolate-insensitive.
Finder findBidiText(String expected) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && stripBidi(w.data!) == expected,
  description: 'Text "$expected" (ignoring bidi isolates)',
);
