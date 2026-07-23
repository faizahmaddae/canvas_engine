import 'dart:math' as math;
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/interaction/group_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = GroupEngine();

  LayerTransform t({
    required Offset pos,
    Size size = const Size(100, 100),
    double rotation = 0,
  }) =>
      LayerTransform(position: pos, size: size, rotation: rotation);

  Map<String, LayerTransform> twoLayers() => {
        'a': t(pos: const Offset(0, 0)),
        'b': t(pos: const Offset(200, 0)),
      };

  Matcher closeToOffset(Offset expected, {double tol = 1e-6}) =>
      predicate<Offset>(
        (o) => (o - expected).distance < tol,
        'within $tol of $expected',
      );

  group('computeBounds', () {
    test('axis-aligned union of unrotated rects', () {
      final r = engine.computeBounds(twoLayers().values);
      expect(r, const Rect.fromLTRB(0, 0, 300, 100));
    });

    test('uses rotated corners (square at 45° has bounds wider than its size)',
        () {
      final r = engine.computeBounds([
        t(pos: const Offset(0, 0), rotation: math.pi / 4),
      ]);
      // A 100x100 square rotated 45° fits in a 100*sqrt(2) ≈ 141.42 box.
      expect(r.width, closeTo(100 * math.sqrt2, 1e-6));
      expect(r.height, closeTo(100 * math.sqrt2, 1e-6));
      // Centered on the original centre (50, 50).
      expect(r.center, closeToOffset(const Offset(50, 50)));
    });

    test('empty input returns Rect.zero', () {
      expect(engine.computeBounds(const []), Rect.zero);
    });
  });

  group('translate', () {
    test('shifts every layer by the same delta; sizes/rotations unchanged',
        () {
      final out = engine.translate(twoLayers(), const Offset(10, 20));
      expect(out['a']!.position, const Offset(10, 20));
      expect(out['b']!.position, const Offset(210, 20));
      expect(out['a']!.size, const Size(100, 100));
      expect(out['a']!.rotation, 0);
    });

    test('preserves relative distances exactly', () {
      final initials = twoLayers();
      final out = engine.translate(initials, const Offset(123.5, -45.25));
      final initialDelta = initials['b']!.center - initials['a']!.center;
      final outDelta = out['b']!.center - out['a']!.center;
      expect((outDelta - initialDelta).distance, lessThan(1e-9));
    });
  });

  group('scale', () {
    test('uniform 2x around top-left anchor doubles every layer\'s '
        'distance from the anchor and doubles every size', () {
      final initials = twoLayers();
      final anchor = const Offset(0, 0);
      final res = engine.scale(initials, anchor: anchor, scale: 2.0);
      final out = res.transforms;
      // No constraint hit: applied scale equals the requested scale.
      expect(res.appliedScale, 2.0);
      // a was at center (50,50); becomes (100,100) → top-left (0,0)
      expect(out['a']!.position, closeToOffset(const Offset(0, 0)));
      expect(out['a']!.size, const Size(200, 200));
      // b was at center (250,50); becomes (500,100) → top-left (400,0)
      expect(out['b']!.position, closeToOffset(const Offset(400, 0)));
      expect(out['b']!.size, const Size(200, 200));
    });

    test('scale by 1.0 is identity', () {
      final initials = twoLayers();
      final out = engine.scale(initials,
          anchor: const Offset(150, 50), scale: 1.0).transforms;
      for (final id in initials.keys) {
        expect(out[id]!.position, closeToOffset(initials[id]!.position));
        expect(out[id]!.size, initials[id]!.size);
      }
    });

    test('clamps scale to [minScale, maxScale]', () {
      final res =
          engine.scale(twoLayers(), anchor: Offset.zero, scale: 1000.0);
      final out = res.transforms;
      // Requested 1000 clamps to the default maxScale 64.
      expect(res.appliedScale, 64.0);
      // Max default is 64 — every size should be ≤ initial * 64.
      expect(out['a']!.size.width, 100 * 64);
    });

    test('preserves relative ratios after scale', () {
      final initials = twoLayers();
      // Anchor strictly outside any layer centre to avoid div-by-zero.
      final anchor = const Offset(-100, -100);
      final out = engine.scale(initials, anchor: anchor, scale: 1.5).transforms;
      final initialRatio =
          (initials['b']!.center - anchor).distance /
              (initials['a']!.center - anchor).distance;
      final outRatio = (out['b']!.center - anchor).distance /
          (out['a']!.center - anchor).distance;
      expect(outRatio, closeTo(initialRatio, 1e-9));
    });
  });

  group('rotate', () {
    test('rotating 90° around bounds centre swaps relative axes', () {
      final initials = twoLayers();
      final center = const Offset(150, 50); // bounds centre of a + b
      final out = engine.rotate(initials,
          center: center, delta: math.pi / 2);
      // a's centre was at (50,50); rotated 90° CCW around (150,50)
      // becomes (150, -50).
      expect(out['a']!.center, closeToOffset(const Offset(150, -50),
          tol: 1e-9));
      expect(out['b']!.center, closeToOffset(const Offset(150, 150),
          tol: 1e-9));
      // Each layer's own rotation also advances by delta.
      expect(out['a']!.rotation, closeTo(math.pi / 2, 1e-9));
      expect(out['b']!.rotation, closeTo(math.pi / 2, 1e-9));
    });

    test('rotating then rotating back is the identity', () {
      final initials = twoLayers();
      final center = const Offset(150, 50);
      final once =
          engine.rotate(initials, center: center, delta: 0.7);
      final back = engine.rotate(once, center: center, delta: -0.7);
      for (final id in initials.keys) {
        expect(back[id]!.position,
            closeToOffset(initials[id]!.position, tol: 1e-9));
        expect(back[id]!.rotation, closeTo(initials[id]!.rotation, 1e-9));
      }
    });
  });

  group('pinch', () {
    test('pure scale (rotation=0, translation=0) matches scale()', () {
      final initials = twoLayers();
      final anchor = const Offset(150, 50);
      final viaScale =
          engine.scale(initials, anchor: anchor, scale: 1.7).transforms;
      final viaPinch = engine.pinch(initials,
          anchor: anchor, scale: 1.7, rotation: 0.0).transforms;
      for (final id in initials.keys) {
        expect(viaPinch[id]!.position,
            closeToOffset(viaScale[id]!.position, tol: 1e-9));
        expect(viaPinch[id]!.size, viaScale[id]!.size);
      }
    });

    test('pure rotation (scale=1) matches rotate()', () {
      final initials = twoLayers();
      final anchor = const Offset(150, 50);
      final viaRotate =
          engine.rotate(initials, center: anchor, delta: 0.5);
      final viaPinch = engine.pinch(initials,
          anchor: anchor, scale: 1.0, rotation: 0.5).transforms;
      for (final id in initials.keys) {
        expect(viaPinch[id]!.position,
            closeToOffset(viaRotate[id]!.position, tol: 1e-9));
        expect(viaPinch[id]!.rotation,
            closeTo(viaRotate[id]!.rotation, 1e-9));
      }
    });

    test('translation component shifts every centre by the same delta', () {
      final initials = twoLayers();
      final anchor = const Offset(0, 0);
      final shift = const Offset(7, 13);
      final out = engine.pinch(initials,
          anchor: anchor,
          scale: 1.0,
          rotation: 0.0,
          translation: shift).transforms;
      for (final id in initials.keys) {
        expect(out[id]!.center - initials[id]!.center,
            closeToOffset(shift, tol: 1e-9));
      }
    });
  });

  group('GroupHandle anchors', () {
    const r = Rect.fromLTRB(10, 20, 110, 120);
    test('anchor is the opposite corner', () {
      expect(GroupHandle.topLeft.anchorIn(r), r.bottomRight);
      expect(GroupHandle.topRight.anchorIn(r), r.bottomLeft);
      expect(GroupHandle.bottomLeft.anchorIn(r), r.topRight);
      expect(GroupHandle.bottomRight.anchorIn(r), r.topLeft);
    });
    test('corner is itself', () {
      expect(GroupHandle.topLeft.cornerIn(r), r.topLeft);
    });
  });

  group('hardening: per-layer min/max constraints', () {
    test('scale tightens factor so smallest layer never crosses min side',
        () {
      // 50px and 200px layers; ask for 0.05 scale (smallest would be 2.5)
      // with minLayerSide = 24. Effective scale must be >= 24/50 = 0.48.
      final initials = <String, LayerTransform>{
        'small': t(pos: Offset.zero, size: const Size(50, 50)),
        'big': t(pos: const Offset(200, 0), size: const Size(200, 200)),
      };
      final res = engine.scale(
        initials,
        anchor: Offset.zero,
        scale: 0.05,
        minLayerSide: 24,
      );
      final out = res.transforms;
      // Applied scale tightened to the small layer's floor: 24/50 = 0.48.
      expect(res.appliedScale, closeTo(24 / 50, 1e-9));
      expect(out['small']!.size.width, closeTo(24, 1e-9));
      // Big layer scaled by the same effective factor, preserving rigidity.
      expect(out['big']!.size.width, closeTo(200 * (24 / 50), 1e-6));
    });

    test('scale tightens factor so largest layer never crosses max side', () {
      final initials = <String, LayerTransform>{
        'small': t(pos: Offset.zero, size: const Size(50, 50)),
        'big': t(pos: const Offset(200, 0), size: const Size(2000, 2000)),
      };
      final res = engine.scale(
        initials,
        anchor: Offset.zero,
        scale: 10,
        maxLayerSide: 8000,
      );
      final out = res.transforms;
      // 2000 * 4 = 8000 is the ceiling. Effective scale must be <= 4.
      expect(res.appliedScale, closeTo(8000 / 2000, 1e-9));
      expect(out['big']!.size.width, closeTo(8000, 1e-6));
      expect(out['small']!.size.width, closeTo(50 * 4, 1e-6));
    });

    test('pinch obeys the same min/max constraints', () {
      final initials = <String, LayerTransform>{
        'a': t(pos: Offset.zero, size: const Size(50, 50)),
      };
      final res = engine.pinch(
        initials,
        anchor: Offset.zero,
        scale: 0.01,
        rotation: 0,
        minLayerSide: 24,
      );
      final out = res.transforms;
      // 50px layer floored at 24 => applied scale 24/50 = 0.48.
      expect(res.appliedScale, closeTo(24 / 50, 1e-9));
      expect(out['a']!.size.width, closeTo(24, 1e-9));
    });

    test('empty initials short-circuit on scale / pinch / rotate', () {
      final empty = <String, LayerTransform>{};
      expect(engine.scale(empty, anchor: Offset.zero, scale: 2).transforms,
          isEmpty);
      expect(
          engine.pinch(empty, anchor: Offset.zero, scale: 2, rotation: 0)
              .transforms,
          isEmpty);
      expect(engine.rotate(empty, center: Offset.zero, delta: 1), isEmpty);
    });

    test('zero rotation delta returns identity', () {
      final initials = twoLayers();
      final out = engine.rotate(initials, center: Offset.zero, delta: 0);
      expect(out['a']!.position, initials['a']!.position);
      expect(out['b']!.position, initials['b']!.position);
      expect(out['a']!.rotation, initials['a']!.rotation);
    });
  });
}
