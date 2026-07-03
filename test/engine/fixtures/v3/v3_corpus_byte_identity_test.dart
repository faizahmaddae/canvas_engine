import 'dart:io';

import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Byte-identity gate for the v3 fixture corpus.
///
/// v3 is the schema stamped whenever a layer's [EffectStack] is
/// non-empty OR carries a stackMask. The gate's contract: every
/// fixture in this folder must decode then re-encode to
/// byte-identical output. Any future schema bump (v4+) must keep
/// these files round-tripping or version itself out via the
/// min-version writer (see `DocumentCodec._writerVersion`).
const _fixtureDir = 'test/engine/fixtures/v3';
const _fixtureFiles = <String>[
  '01_image_with_effects.json',
  '02_image_with_stack_mask.json',
];

void main() {
  for (final name in _fixtureFiles) {
    test('$name re-encodes to byte-identical content', () {
      final file = File('$_fixtureDir/$name');
      expect(file.existsSync(), isTrue,
          reason: 'fixture missing — run _generate_v3_fixtures_test.dart');
      final raw = file.readAsStringSync();
      final doc = DocumentCodec.decode(raw);
      final reencoded = '${DocumentCodec.encode(doc)}\n';
      expect(reencoded, raw,
          reason: '$name no longer encodes byte-identically. Either a '
              'codec change dropped/added a key, or a default-value '
              'omission was broken. Inspect the diff before regenerating.');
    });
  }
}
