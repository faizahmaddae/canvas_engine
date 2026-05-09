import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/selection_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the selection-outset rule. Without this, a regression that
/// re-anchors the chrome to the raw layer corners would silently
/// reintroduce the "outline glued to content" bug.
void main() {
  test('selectionOutset constant stays positive and small', () {
    expect(EngineConstants.selectionOutset, greaterThan(0));
    expect(
      EngineConstants.selectionOutset,
      lessThanOrEqualTo(12),
      reason: 'Larger than ~12dp starts to look detached from the layer.',
    );
  });

  group('outsetSelectionQuad', () {
    const d = 6.0;

    test('axis-aligned rect grows by d on every side', () {
      final out = outsetSelectionQuad(
        const Offset(100, 100),
        const Offset(200, 100),
        const Offset(100, 160),
        const Offset(200, 160),
        d,
      );
      expect(out[0], const Offset(94, 94));
      expect(out[1], const Offset(206, 94));
      expect(out[2], const Offset(94, 166));
      expect(out[3], const Offset(206, 166));
    });

    test('rotated 90° quad still grows along its local axes', () {
      // 100x60 rect rotated 90° around its centre. Each corner moves
      // by d along the local right axis AND by d along the local
      // down axis, so the local-frame displacement of every corner
      // grows from (30, 50) to (36, 56).
      final out = outsetSelectionQuad(
        const Offset(100, 100),
        const Offset(100, 200),
        const Offset(40, 100),
        const Offset(40, 200),
        d,
      );
      const centre = Offset(70, 150);
      // sqrt(36^2 + 56^2) = sqrt(4432) ≈ 66.5733
      const expected = 66.5733;
      for (final p in out) {
        final fromCentre = (p - centre).distance;
        expect(fromCentre, closeTo(expected, 0.05));
      }
    });

    test('returns input unchanged when d is zero', () {
      const tl = Offset(10, 10);
      const tr = Offset(20, 10);
      const bl = Offset(10, 20);
      const br = Offset(20, 20);
      final out = outsetSelectionQuad(tl, tr, bl, br, 0);
      expect(out, [tl, tr, bl, br]);
    });

    test('returns input unchanged when an edge has degenerate length', () {
      // Brand-new layer with zero width — must not produce NaN.
      const tl = Offset(10, 10);
      const tr = Offset(10, 10);
      const bl = Offset(10, 20);
      const br = Offset(10, 20);
      final out = outsetSelectionQuad(tl, tr, bl, br, 6);
      expect(out, [tl, tr, bl, br]);
      for (final p in out) {
        expect(p.dx.isFinite, isTrue);
        expect(p.dy.isFinite, isTrue);
      }
    });
  });
}
