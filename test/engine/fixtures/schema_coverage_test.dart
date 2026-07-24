import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Schema-coverage gate.
///
/// The codec advertises support for `minSupportedSchemaVersion`
/// (`1`) through `schemaVersion` (`3`). The fixture corpus already
/// happens to exercise all three (v1: solid-bg, v2: gradient-bg,
/// v3: per-layer effect stacks) but nothing guarantees that today —
/// a refactor that quietly stopped writing v1-shaped output for
/// `01_empty.json` would only be caught by the byte-identity gate
/// telling you that *something* changed, not that **a whole schema
/// version is no longer covered**.
///
/// This test enumerates `[fixtureDir, fileName]` pairs grouped by
/// the wire-format version each file declares and asserts:
///
///   1. Every supported schema version (`minSupportedSchemaVersion`
///      .. `schemaVersion`) has at least one fixture covering it.
///   2. Each fixture's stamped `"version"` matches the bucket it
///      was placed in (catches a hand-edit that silently changed
///      the version field of a check-in fixture).
///   3. Each fixture decodes without error (the legacy reader path
///      for v1 / v2 still works in the current build).
///
/// This is the inverse of `_corpus_byte_identity_test.dart`: byte
/// identity asserts the **writer** is stable. This file asserts the
/// **reader** still understands every version we promise to support.
void main() {
  // Map of `version → list of fixture relative paths`. Keep this
  // list in sync with the on-disk fixtures: when a new version
  // lands, add a bucket here and at least one file under it.
  const corpus = <int, List<String>>{
    1: <String>[
      'test/engine/fixtures/v2/01_empty.json',
      'test/engine/fixtures/v2/02_solid_bg.json',
      'test/engine/fixtures/v2/04_text_shape_paint.json',
      'test/engine/fixtures/v2/05_image_with_crop_and_adjustments.json',
    ],
    2: <String>['test/engine/fixtures/v2/03_gradient_bg.json'],
    3: <String>['test/engine/fixtures/v3/01_image_with_effects.json'],
  };

  test('every supported schema version has at least one fixture', () {
    for (
      var v = DocumentCodec.minSupportedSchemaVersion;
      v <= DocumentCodec.schemaVersion;
      v++
    ) {
      final bucket = corpus[v];
      expect(
        bucket,
        isNotNull,
        reason:
            'no fixture bucket for schema v$v — add one before '
            'shipping a new schema version',
      );
      expect(bucket!, isNotEmpty, reason: 'schema v$v bucket is empty');
    }
  });

  for (final entry in corpus.entries) {
    final declaredVersion = entry.key;
    for (final path in entry.value) {
      test('$path declares version $declaredVersion and decodes', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'fixture missing: $path');
        final raw = file.readAsStringSync();

        // Cross-check the on-disk version stamp against the bucket.
        // A drift here is almost certainly a hand-edit; failing fast
        // beats silently re-categorising a fixture into the wrong
        // version's coverage.
        final json = jsonDecode(raw) as Map<String, dynamic>;
        expect(
          json['version'],
          declaredVersion,
          reason:
              '$path is in the v$declaredVersion bucket but its '
              'on-disk "version" field disagrees',
        );

        // Reader path still works for this version. We do NOT assert
        // byte identity here — that's the job of the sibling
        // `_corpus_byte_identity_test.dart` files. Any non-throw
        // decode is enough to prove the legacy reader is alive.
        expect(
          () => DocumentCodec.decode(raw),
          returnsNormally,
          reason:
              '$path failed to decode under the current build — '
              'the reader for schema v$declaredVersion has regressed',
        );
      });
    }
  }
}
