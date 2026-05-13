import 'dart:io';

import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Read-side transparency gate for legacy v2 documents that still
/// carry the retired `adjustments: {...}` slot on image layers.
///
/// Step 6 retired [ImageLayer.adjustments] as a stored field. The
/// codec's read path now lifts the legacy slot into the equivalent
/// [EffectStack] entries on decode. This test pins that lift so a
/// future refactor of the bridge function can't silently change
/// the per-knob values a v2 doc rehydrates with.
///
/// The companion v2 corpus byte-identity gate (see
/// `v2_corpus_byte_identity_test.dart`) skips fixture 05 because
/// re-encode now writes the v3 `effects: [...]` shape, not the
/// v2 `adjustments: {...}` shape. The wire-format change is
/// *to* the current schema; no on-disk doc becomes unreadable.
void main() {
  test(
      'legacy adjustments slot lifts to EffectStack entries on read '
      '(brightness=12, contrast=1.1, saturation=0.9)', () {
    final raw = File(
      'test/engine/fixtures/v2/05_image_with_crop_and_adjustments.json',
    ).readAsStringSync();
    final doc = DocumentCodec.decode(raw);
    final layer = doc.layers.single as ImageLayer;
    // The lifted effect stack carries the same per-knob values
    // (in canonical order) the legacy struct held.
    final types = layer.effects.effects.map((e) => e.type).toList();
    expect(types, <String>['saturation', 'contrast', 'brightness']);
    final adj = ImageAdjustments.fromEffectStack(layer.effects);
    expect(adj.brightness, 12);
    expect(adj.contrast, closeTo(1.1, 1e-9));
    expect(adj.saturation, closeTo(0.9, 1e-9));
    expect(adj.exposure, 0);
    expect(adj.warmth, 0);
  });

  test(
      're-encoding the lifted document writes the v3 effects shape '
      'and never the legacy adjustments key', () {
    final raw = File(
      'test/engine/fixtures/v2/05_image_with_crop_and_adjustments.json',
    ).readAsStringSync();
    final doc = DocumentCodec.decode(raw);
    final reencoded = DocumentCodec.encode(doc);
    expect(reencoded.contains('"adjustments"'), isFalse,
        reason: 'writer must not emit the retired adjustments key');
    expect(reencoded.contains('"effects"'), isTrue,
        reason: 'lifted effects must surface on re-encode');
    // Round-trip stability: the v3 form is a fixed point of the
    // codec going forward (re-encode → decode → re-encode is
    // byte-identical, even if the very first encode reshaped).
    final round2 = DocumentCodec.encode(DocumentCodec.decode(reencoded));
    expect(round2, reencoded);
  });
}
