// The denominator that converts a user-facing image-pixel ratio
// ("16:9") into the normalised ratio the crop draft obeys.
//
// Two sites needed it — the preset chips (`setAspectRatio`) and the
// handle drag (`crop_mode_overlay`) — and both were dividing by the
// LAYER BOX aspect. The box only describes the same rectangle as the
// draft basis while the layer paints its window without stretching
// it. Under an anisotropic fit the box aspect is a property of the
// stretch, not of the pixels, and a chip labelled «۱:۱» produced a
// frame nearly twice as tall as it was wide.

import 'dart:ui';

import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CropSession session({
    double? sourceAspect,
    Rect displayBasis = ImageLayer.fullCrop,
    double? originalAspect,
  }) => CropSession(
    active: true,
    sourceAspect: sourceAspect,
    displayBasis: displayBasis,
    originalAspect: originalAspect,
  );

  test('an uncropped layer: the basis IS the source, so both agree', () {
    // Layer box aspect and draft-unit aspect coincide here — which is
    // exactly why the old code looked correct for so long.
    final s = session(sourceAspect: 1.5, originalAspect: 1.5);
    expect(s.draftUnitAspect, closeTo(1.5, 1e-9));
  });

  test('a proportional crop keeps the two in agreement', () {
    // Source 1080×1080. A 16:9 commit leaves the box at 1080×608 AND
    // the basis at the centred 16:9 strip, so both describe the same
    // rectangle. This case never misbehaved — worth pinning so a
    // future change to the denominator does not break it.
    final s = session(
      sourceAspect: 1.0,
      displayBasis: const Rect.fromLTWH(0, 0.21875, 1, 0.5625),
      originalAspect: 1080 / 608,
    );
    expect(s.draftUnitAspect, closeTo(16 / 9, 1e-6));
    expect(s.draftUnitAspect, closeTo(s.originalAspect!, 1e-2));
  });

  test('an anisotropic fit makes the two DIVERGE', () {
    // The case that broke. `fit: fill` stretches the WHOLE bitmap onto
    // the layer box, so the box can be 16:9 while the window the draft
    // normalises over is still the square source. The box aspect is
    // then a property of the stretch, not of the pixels.
    final s = session(
      sourceAspect: 1.0,
      displayBasis: ImageLayer.fullCrop,
      originalAspect: 1080 / 608,
    );

    expect(
      s.draftUnitAspect,
      closeTo(1.0, 1e-9),
      reason: 'the source is square',
    );
    expect(
      s.draftUnitAspect,
      isNot(closeTo(s.originalAspect!, 0.5)),
      reason: 'if these agreed the bug could not have existed',
    );
  });

  test('a 1:1 request on that draft is a square in image pixels', () {
    final s = session(
      sourceAspect: 1.0,
      displayBasis: ImageLayer.fullCrop,
      originalAspect: 1080 / 608,
    );
    // fitAspect divides the requested image-pixel ratio by the
    // draft-unit aspect. Over a square window, "1:1" is 1.0 — a
    // genuine square.
    expect(1.0 / s.draftUnitAspect, closeTo(1.0, 1e-9));

    // The old denominator asked for a normalised 0.563 — a frame
    // almost twice as tall as it is wide, from a chip labelled «۱:۱».
    final wrong = 1.0 / s.originalAspect!;
    expect(wrong, closeTo(0.563, 1e-3));
    expect((1.0 / s.draftUnitAspect - wrong).abs(), greaterThan(0.4));
  });

  test('falls back to the layer box before the source resolves', () {
    // `sourceAspect` is null until the overlay reports it; every
    // caller that never resolves an image keeps the old behaviour.
    final s = session(sourceAspect: null, originalAspect: 1.25);
    expect(s.draftUnitAspect, 1.25);

    final bare = session();
    expect(bare.draftUnitAspect, 1.0, reason: 'and 1.0 when nothing is known');
  });

  test('a degenerate basis cannot produce a NaN or a zero divisor', () {
    for (final basis in const [
      Rect.fromLTWH(0, 0, 0, 0.5),
      Rect.fromLTWH(0, 0, 0.5, 0),
    ]) {
      final s = session(
        sourceAspect: 1.5,
        displayBasis: basis,
        originalAspect: 2.0,
      );
      expect(s.draftUnitAspect, 2.0);
      expect(s.draftUnitAspect.isFinite, isTrue);
    }
  });
}
