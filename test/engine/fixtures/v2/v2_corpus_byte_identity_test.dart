import 'dart:io';

import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Byte-identity gate for the v2 fixture corpus.
///
/// For every JSON file listed below, decoding then re-encoding must
/// produce byte-identical output (modulo the trailing newline the
/// generator writes). This is the contract the rest of Phase 2 relies
/// on:
///   * Step 2a (copyAll refactor): pure refactor — same bytes out.
///   * Step 2b (effects field on EditorLayer): empty `EffectStack` MUST
///     omit its key, so legacy fixtures stay byte-identical.
///   * Step 4 (effect concretes + dual-write): legacy
///     `adjustments` writes still round-trip exactly.
///
/// Step 6 (soft-retire of `ImageLayer.adjustments`) deliberately
/// drops `05_image_with_crop_and_adjustments.json` from this gate.
/// That file's legacy `adjustments: {...}` shape is no longer
/// emitted by the writer (the field was retired), so a re-encode
/// produces v3-shaped `effects: [...]` bytes instead. Read-side
/// transparency for that fixture is asserted by the sibling
/// `v2_legacy_lift_test.dart`.
///
/// Maintained by `_generate_v2_fixtures_test.dart` in this same
/// directory — refresh fixtures only when a *legitimate* schema change
/// lands, and review the diff in the PR.
const _fixtureDir = 'test/engine/fixtures/v2';
const _fixtureFiles = <String>[
  '01_empty.json',
  '02_solid_bg.json',
  '03_gradient_bg.json',
  '04_text_shape_paint.json',
];

void main() {
  for (final name in _fixtureFiles) {
    test('$name re-encodes to byte-identical content', () {
      final file = File('$_fixtureDir/$name');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'fixture missing — run _generate_v2_fixtures_test.dart',
      );
      final raw = file.readAsStringSync();
      final doc = DocumentCodec.decode(raw);
      final reencoded = '${DocumentCodec.encode(doc)}\n';
      expect(
        reencoded,
        raw,
        reason:
            '$name no longer encodes byte-identically. Either a '
            'codec change dropped/added a key, or a default-value '
            'omission was broken. Inspect the diff before regenerating.',
      );
    });
  }
}
