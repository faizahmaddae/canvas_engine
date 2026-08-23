import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [CropController.zoom] — the pure pinch helper the
/// crop stage feeds incremental scale factors through. The window
/// scales *inversely* to the photo (pinching the photo out by 2×
/// halves the window), preserves its aspect exactly, and never
/// leaves the bounds or shrinks under [CropController.minNorm].
void main() {
  const unit = Rect.fromLTWH(0, 0, 1, 1);

  void expectRectClose(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, 1e-9));
    expect(actual.top, closeTo(expected.top, 1e-9));
    expect(actual.right, closeTo(expected.right, 1e-9));
    expect(actual.bottom, closeTo(expected.bottom, 1e-9));
  }

  test('scale 2 about the centre halves the window in place', () {
    const r = Rect.fromLTWH(0.25, 0.25, 0.5, 0.5);
    final next = CropController.zoom(
      r,
      scale: 2,
      focal: const Offset(0.5, 0.5),
    );
    expectRectClose(next, const Rect.fromLTWH(0.375, 0.375, 0.25, 0.25));
  });

  test('the focal point stays fixed under the zoom', () {
    const r = Rect.fromLTWH(0.2, 0.2, 0.4, 0.4);
    const focal = Offset(0.3, 0.5);
    final next = CropController.zoom(r, scale: 1.6, focal: focal);
    // A point at the focal maps to itself: focal + (focal - focal)/s.
    expect(next.left, closeTo(focal.dx + (r.left - focal.dx) / 1.6, 1e-9));
    expect(next.top, closeTo(focal.dy + (r.top - focal.dy) / 1.6, 1e-9));
  });

  test('aspect is preserved exactly (uniform scale)', () {
    const r = Rect.fromLTWH(0.1, 0.1, 0.6, 0.3);
    final next = CropController.zoom(
      r,
      scale: 1.7,
      focal: const Offset(0.4, 0.25),
    );
    expect(next.width / next.height, closeTo(r.width / r.height, 1e-9));
  });

  test('zoom-out is capped so the window never outgrows the bounds', () {
    const r = Rect.fromLTWH(0.25, 0.25, 0.5, 0.5);
    final next = CropController.zoom(
      r,
      scale: 0.1, // photo shrinks 10× → window wants 10×, bounds allow 2×
      focal: const Offset(0.5, 0.5),
    );
    expectRectClose(next, unit);
  });

  test('an off-centre capped zoom-out is translate-clamped inside', () {
    const r = Rect.fromLTWH(0.0, 0.0, 0.5, 0.5);
    final next = CropController.zoom(
      r,
      scale: 0.25,
      focal: const Offset(0.1, 0.1),
    );
    expect(next.left, greaterThanOrEqualTo(0));
    expect(next.top, greaterThanOrEqualTo(0));
    expect(next.right, lessThanOrEqualTo(1));
    expect(next.bottom, lessThanOrEqualTo(1));
    expect(next.width, closeTo(1, 1e-9));
  });

  test('zoom-in is capped at minNorm on the short side', () {
    const r = Rect.fromLTWH(0.4, 0.4, 0.2, 0.1);
    final next = CropController.zoom(
      r,
      scale: 100,
      focal: const Offset(0.5, 0.45),
    );
    expect(next.height, closeTo(CropController.minNorm, 1e-9));
    expect(next.width / next.height, closeTo(2, 1e-9));
  });

  test('wider bounds (non-destructive reach) are honoured', () {
    const bounds = Rect.fromLTRB(-0.5, -0.5, 1.5, 1.5);
    const r = Rect.fromLTWH(0, 0, 1, 1);
    final next = CropController.zoom(
      r,
      scale: 0.5,
      focal: const Offset(0.5, 0.5),
      bounds: bounds,
    );
    expectRectClose(next, bounds);
  });

  test('degenerate scales are ignored', () {
    const r = Rect.fromLTWH(0.2, 0.2, 0.5, 0.5);
    expect(CropController.zoom(r, scale: 0, focal: Offset.zero), r);
    expect(CropController.zoom(r, scale: double.nan, focal: Offset.zero), r);
    expect(
      CropController.zoom(r, scale: double.infinity, focal: Offset.zero),
      r,
    );
  });
}
