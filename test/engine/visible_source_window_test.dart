import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';

/// Pure-math tests for [ImageLayer.visibleSourceWindow] — the
/// display-basis → source-window mapping the crop commit relies on.
void main() {
  const eps = 1e-9;

  void expectRect(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, eps));
    expect(actual.top, closeTo(expected.top, eps));
    expect(actual.width, closeTo(expected.width, eps));
    expect(actual.height, closeTo(expected.height, eps));
  }

  group('cover', () {
    test('source wider than box clips a centred horizontal strip', () {
      // Source 2:1 in a square box → visible width fraction = 1/2.
      expectRect(
        ImageLayer.visibleSourceWindow(
          fit: BoxFit.cover,
          cropRect: ImageLayer.fullCrop,
          boxAspect: 1.0,
          sourceAspect: 2.0,
        ),
        const Rect.fromLTWH(0.25, 0, 0.5, 1),
      );
    });

    test('source taller than box clips a centred vertical strip', () {
      // Source 1:2 in a square box → visible height fraction = 1/2.
      expectRect(
        ImageLayer.visibleSourceWindow(
          fit: BoxFit.cover,
          cropRect: ImageLayer.fullCrop,
          boxAspect: 1.0,
          sourceAspect: 0.5,
        ),
        const Rect.fromLTWH(0, 0.25, 1, 0.5),
      );
    });

    test('matching aspects show the full source', () {
      expectRect(
        ImageLayer.visibleSourceWindow(
          fit: BoxFit.cover,
          cropRect: ImageLayer.fullCrop,
          boxAspect: 1.5,
          sourceAspect: 1.5,
        ),
        ImageLayer.fullCrop,
      );
    });

    test('cropRect composes inside the cover strip', () {
      // Left half of the visible strip of a 2:1 source in a square
      // box → left quarter-to-half of the source.
      expectRect(
        ImageLayer.visibleSourceWindow(
          fit: BoxFit.cover,
          cropRect: const Rect.fromLTWH(0, 0, 0.5, 1),
          boxAspect: 1.0,
          sourceAspect: 2.0,
        ),
        const Rect.fromLTWH(0.25, 0, 0.25, 1),
      );
    });
  });

  group('fill', () {
    test('is the identity mapping over cropRect', () {
      const crop = Rect.fromLTWH(0.1, 0.35, 0.8, 0.3);
      expectRect(
        ImageLayer.visibleSourceWindow(
          fit: BoxFit.fill,
          cropRect: crop,
          boxAspect: 3.2,
          sourceAspect: 0.7,
        ),
        crop,
      );
    });
  });

  test('degenerate aspects fall back to the fill mapping', () {
    const crop = Rect.fromLTWH(0.2, 0.2, 0.6, 0.6);
    expectRect(
      ImageLayer.visibleSourceWindow(
        fit: BoxFit.cover,
        cropRect: crop,
        boxAspect: 0,
        sourceAspect: 2.0,
      ),
      crop,
    );
  });
}
