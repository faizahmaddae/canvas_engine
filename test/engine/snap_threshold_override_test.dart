import 'package:canvas_engine/features/editor/engine/interaction/snap_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The controller passes a viewport-scaled threshold so the magnetic
/// radius stays constant in screen pixels. This test verifies the
/// engine's per-call [threshold] override actually changes the snap
/// reach as expected.
void main() {
  const engine = SnapEngine(threshold: 6);

  test('per-call threshold widens snap reach (zoomed-out simulation)', () {
    // Layer of 48px placed so its centre is 16 px away from the canvas
    // centre line on X, and far from any centre on Y.
    //   left=760, cx=784, right=808 → distances to canvas centre 800 are
    //   {40, 16, 8}. None is ≤ 6 (default), but at threshold 30 the
    //   right edge (8) and centre (16) both engage.
    const proposed = Offset(760, 700);
    const size = Size(48, 48);
    const canvas = Size(1600, 1600);

    final defaultRun = engine.snapPosition(
      proposed: proposed,
      size: size,
      peerRects: const <Rect>[],
      canvasSize: canvas,
    );
    expect(defaultRun.guides, isEmpty,
        reason: 'min vertical distance is 8 px > 6 px default.');

    final zoomedOut = engine.snapPosition(
      proposed: proposed,
      size: size,
      peerRects: const <Rect>[],
      canvasSize: canvas,
      threshold: 30,
    );
    expect(zoomedOut.guides, isNotEmpty,
        reason: 'A 30 px override should pull in the centre-line snap.');
  });

  test('per-call threshold narrows snap reach (zoomed-in simulation)', () {
    // Layer of 6px placed so its right edge is 3 px away from the canvas
    // centre line on X, and far from any centre on Y.
    //   left=791, cx=794, right=797 → distances to canvas centre 800 are
    //   {9, 6, 3}. With threshold 6 the right edge engages; with 1.5 it
    //   does not.
    const proposed = Offset(791, 700);
    const size = Size(6, 6);
    const canvas = Size(1600, 1600);

    final defaultRun = engine.snapPosition(
      proposed: proposed,
      size: size,
      peerRects: const <Rect>[],
      canvasSize: canvas,
    );
    expect(defaultRun.guides, isNotEmpty);

    final zoomedIn = engine.snapPosition(
      proposed: proposed,
      size: size,
      peerRects: const <Rect>[],
      canvasSize: canvas,
      threshold: 1.5,
    );
    expect(zoomedIn.guides, isEmpty);
  });
}
