// Run with:
//   flutter test test/engine/fixtures/v3/_generate_v3_fixtures_test.dart
//
// Writes the canonical v3 fixture corpus to disk. v3 is the schema
// stamped whenever a layer carries any non-empty [EffectStack]
// (see `DocumentCodec._writerVersion`). These fixtures are the
// forward-gating baseline: every future Phase 2+ change must keep
// them byte-identical, just like v1/v2 fixtures stay byte-identical
// for legacy docs.
//
// Why a separate folder: the v2 corpus locks the *legacy* shape
// (no effects key, optional `adjustments`, …). v3 fixtures lock the
// *current* shape (`effects: [...]`, never `adjustments: {...}`).
// Splitting keeps each gate's failure modes legible — a regression
// in legacy compat shows up only here-or-there, not as ambiguous
// noise across one mixed corpus.
import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/engine/fixtures/v3';

EditorDocument _imageWithEffects() => EditorDocument(
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
      // v3-shaped: the effect stack is the canonical home for
      // colour adjustments. Constructed via the same
      // [ImageAdjustments] helper the UI uses, then projected
      // to its effect-list form.
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

/// A3 trap #2: a layer whose stack has NO effects but DOES have a
/// stackMask. This is the exact shape that used to be mis-stamped v1
/// (`_writerVersion` only looked at `effects.isNotEmpty`), letting old
/// readers open the doc and silently drop the mask on resave. The
/// fixture locks both the stamped version and the wire shape: a
/// `stackMask` key with no `effects` key.
EditorDocument _imageWithStackMask() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-1',
      transform: const LayerTransform(
        position: Offset(60, 60),
        size: Size(960, 720),
      ),
      source: const ImageSource.asset('assets/sample.jpg'),
      effects: const EffectStack(
        <EditorEffect>[],
        stackMask: RectMask(
          rect: Rect.fromLTWH(0, 0, 800, 400),
          feather: 12,
          inverted: true,
        ),
      ),
    ),
  ],
  basePhotoLayerId: 'img-1',
  projectKind: ProjectKind.photo,
);

/// Step 6: a per-effect mask alongside an unmasked effect. Locks the
/// wire shape of `mask` on an effect entry and (via the byte-identity
/// gate) that the Step 6 renderer work never touches serialization.
EditorDocument _imageWithPerEffectMask() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-1',
      transform: const LayerTransform(
        position: Offset(60, 60),
        size: Size(960, 720),
      ),
      source: const ImageSource.asset('assets/sample.jpg'),
      effects: EffectStack(
        List<EditorEffect>.unmodifiable(<EditorEffect>[
          const SaturationEffect(amount: 0.8),
          BrightnessEffect(
            amount: 24,
            mask: const RectMask(
              rect: Rect.fromLTWH(0, 0, 960, 360),
              feather: 32,
            ),
          ),
        ]),
      ),
    ),
  ],
  basePhotoLayerId: 'img-1',
  projectKind: ProjectKind.photo,
);

/// tb4 7/14: a mirrored layer. `flipH`/`flipV` are omit-default, so
/// this fixture is the only place in the corpus where `fx`/`fy`
/// appear at all — every other file proves their absence stays
/// byte-identical.
EditorDocument _flippedLayer() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-flip',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(480, 640),
        rotation: 0.35,
        flipH: true,
      ),
      source: const ImageSource.asset('assets/sample.jpg'),
      effects: EffectStack(
        ImageAdjustments(brightness: 6, contrast: 1.05).toEffectStack(),
      ),
    ),
  ],
);

void main() {
  final fixtures = <String, EditorDocument>{
    '01_image_with_effects.json': _imageWithEffects(),
    '02_image_with_stack_mask.json': _imageWithStackMask(),
    '03_image_with_per_effect_mask.json': _imageWithPerEffectMask(),
    '04_flipped_layer.json': _flippedLayer(),
  };

  test('write v3 fixture corpus', () {
    final dir = Directory(_fixtureDir);
    dir.createSync(recursive: true);
    for (final entry in fixtures.entries) {
      final encoded = DocumentCodec.encode(entry.value);
      _writeFixtureAtomically('$_fixtureDir/${entry.key}', '$encoded\n');
    }
  });

  for (final entry in fixtures.entries) {
    test('${entry.key} round-trips and stamps the v3 schema version', () {
      final encoded = DocumentCodec.encode(entry.value);
      final decoded = DocumentCodec.decode(encoded);
      expect(
        DocumentCodec.encode(decoded),
        encoded,
        reason: '${entry.key} is not a fixed point of encode/decode',
      );
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      // v3 fixtures must stamp v3 — that's the whole point of the
      // separate corpus. If the writer ever forgets to bump the
      // version when a non-empty effect stack is present, this
      // assert catches it before the byte-identity gate does.
      expect(
        json['version'],
        3,
        reason: 'effects- or stackMask-bearing docs must declare schema v3',
      );
    });
  }
}

void _writeFixtureAtomically(String path, String contents) {
  final temp = File('$path.tmp');
  temp.writeAsStringSync(contents, flush: true);
  temp.renameSync(path);
}
