// Run with:
//   flutter test test/engine/fixtures/v2/_generate_v2_fixtures_test.dart
//
// Writes the canonical v2 fixture corpus to disk. The corpus is the
// byte-identity baseline that the Phase 2 Step 2 (EffectStack on
// EditorLayer) implementation must preserve — adding the new field
// must not change any byte of these files because none of them
// contain effects and an empty EffectStack must omit its key.
//
// In Step 3 this generator is kept (so we can refresh fixtures when
// the schema legitimately changes) and a sibling test asserts each
// in-memory document re-encodes to the on-disk bytes verbatim.
//
// Right now the test simply (re)writes the files — running it once
// produces the corpus as the audit deliverable. The files are
// committed and reviewed by humans. After commit, the assert at the
// bottom guards them.
import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir =
    'test/engine/fixtures/v2'; // workspace-relative; cwd is repo root

EditorDocument _empty() => EditorDocument(layers: const []);

EditorDocument _solidBg() => EditorDocument(
  layers: const [],
  background: const SolidBackground(color: Color(0xFF112233)),
);

EditorDocument _gradientBg() => EditorDocument(
  layers: const [],
  background: const LinearGradientBackground(
    startColor: Color(0xFFFF0080),
    endColor: Color(0xFF7928CA),
    angleDegrees: 90,
  ),
);

EditorDocument _textShapePaint() => EditorDocument(
  layers: [
    const TextLayer(
      id: 'txt-1',
      transform: LayerTransform(
        position: Offset(100, 100),
        size: Size(400, 120),
      ),
      content: 'hello',
      style: TextStyleSpec(),
    ),
    const ShapeLayer(
      id: 'shp-1',
      transform: LayerTransform(
        position: Offset(200, 300),
        size: Size(300, 200),
      ),
      kind: ShapeKind.rectangle,
      fillColor: Color(0xFF4488FF),
      cornerRadius: 16,
    ),
    PaintLayer(
      id: 'pnt-1',
      transform: LayerTransform(
        position: Offset(50, 600),
        size: Size(500, 200),
      ),
      kind: PaintKind.freestyle,
      normalizedPoints: [
        Offset(0.0, 0.5),
        Offset(0.25, 0.0),
        Offset(0.5, 0.75),
        Offset(0.75, 0.25),
        Offset(1.0, 0.5),
      ],
      strokeWidth: 8,
    ),
  ],
);

// Kept for grep-ability: documents what the on-disk v2 fixture 05
// (legacy `adjustments: {...}` shape) means in current types. We
// no longer regenerate that fixture (Step 6 retired the field on
// the writer); the file stays committed as a frozen sample for
// `v2_legacy_lift_test.dart`.
// ignore: unused_element
EditorDocument _imageWithCropAndAdjustments() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-1',
      transform: const LayerTransform(
        position: Offset(60, 60),
        size: Size(960, 720),
      ),
      source: const ImageSource.asset('assets/sample.jpg'),
      mask: ImageMask.rounded,
      borderColor: const Color(0xFFFFFFFF),
      borderWidth: 4,
      shadowColor: const Color(0xFF000000),
      shadowBlur: 16,
      shadowOffset: const Offset(0, 6),
      shadowOpacity: 0.4,
      effects: EffectStack(
        ImageAdjustments(
          brightness: 12,
          contrast: 1.1,
          saturation: 0.9,
        ).toEffectStack(),
      ),
      cropRect: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
      filterPreset: ImageFilterPreset.warm,
      opacity: 0.85,
    ),
  ],
  basePhotoLayerId: 'img-1',
  projectKind: ProjectKind.photo,
);

/// Set `REGEN_FIXTURES=1` to rewrite the committed corpus.
///
/// These generators live inside `test/engine/fixtures/` — the exact path
/// CI runs as the serialization byte-identity gate — and they WRITE the
/// files that gate reads. Left ungated, any codec- or default-visible
/// change silently rewrote the baseline in the same step that was
/// supposed to reject it, so `v2_corpus_byte_identity_test` could only
/// ever compare new bytes to new bytes. Worse, separate test files run
/// in separate isolates, so which bytes the gate read was a race, and a
/// plain `flutter test` mutated tracked files as a side effect.
///
/// Regenerate deliberately:  REGEN_FIXTURES=1 flutter test test/engine/fixtures/v2/_generate_v2_fixtures_test.dart
/// `bool.fromEnvironment` would read a COMPILE-TIME define, not the
/// shell variable the command above sets — the guard would silently
/// write nothing and still print "All tests passed!", which is the
/// same silent-success failure this guard exists to remove.
final bool _regen = Platform.environment['REGEN_FIXTURES'] == '1';

void main() {
  // Fixtures 01-04 are pure v2 docs that contain no effects /
  // adjustments and therefore round-trip byte-identically through
  // every schema bump. They stay generator-managed.
  //
  // Fixture 05 is **not** generated here: its legacy
  // `adjustments: {...}` shape is no longer something the writer
  // can emit (Step 6 retired the field), but the file stays
  // committed as a frozen sample for the legacy-read test. The
  // builder above documents what that doc *would* look like in
  // current types — kept for grep-ability when someone reads the
  // v2 fixture and asks "where does this come from?".
  final fixtures = <String, EditorDocument>{
    '01_empty.json': _empty(),
    '02_solid_bg.json': _solidBg(),
    '03_gradient_bg.json': _gradientBg(),
    '04_text_shape_paint.json': _textShapePaint(),
  };

  test('write v2 fixture corpus', () {
    final dir = Directory(_fixtureDir);
    dir.createSync(recursive: true);
    for (final entry in fixtures.entries) {
      final encoded = DocumentCodec.encode(entry.value);
      _writeFixtureAtomically('$_fixtureDir/${entry.key}', '$encoded\n');
    }
    // Fixture 05 is not regenerated; sanity-check it still exists
    // so a stray `git rm` doesn't silently disable the legacy gate.
    expect(
      File('$_fixtureDir/05_image_with_crop_and_adjustments.json').existsSync(),
      isTrue,
      reason: 'frozen v2 legacy-adjustments fixture must stay on disk',
    );
  });

  // Sanity: every generated fixture must round-trip and declare a version
  // that's within the supported window. The codec stamps the
  // *minimum* reader version a doc requires (see
  // `DocumentCodec._writerVersion`) so legacy-shape docs may write
  // v1 even on a v3-aware build — that's intended.
  for (final entry in fixtures.entries) {
    test('${entry.key} round-trips through codec', () {
      final encoded = DocumentCodec.encode(entry.value);
      final decoded = DocumentCodec.decode(encoded);
      expect(
        DocumentCodec.encode(decoded),
        encoded,
        reason: '${entry.key} is not a fixed point of encode/decode',
      );
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final version = json['version'] as int;
      expect(
        version,
        greaterThanOrEqualTo(DocumentCodec.minSupportedSchemaVersion),
      );
      expect(version, lessThanOrEqualTo(DocumentCodec.schemaVersion));
    });
  }
}

void _writeFixtureAtomically(String path, String contents) {
  // Read-only unless explicitly regenerating — see `_regen` above. A
  // no-op here keeps the surrounding decode/round-trip assertions
  // running (they are real coverage) while leaving the committed bytes
  // untouched, so the byte-identity gate reads a baseline it cannot
  // have written in the same run.
  if (!_regen) return;
  final temp = File('$path.tmp');
  temp.writeAsStringSync(contents, flush: true);
  temp.renameSync(path);
}
