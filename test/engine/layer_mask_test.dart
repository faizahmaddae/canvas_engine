import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [LayerMask]. Pure-data leaf — no engine wiring yet.
/// Coverage:
///   * tagged round-trip for every variant
///   * default-omit invariants (`inverted`, `feather`, `fillType`)
///   * sampleAlpha math (featherless + feathered) for [RectMask] and
///     [EllipseMask]; [PathMask] sampling lands with the renderer
///   * composedAlpha = min(α) at strategic points
///   * structural equality / hashCode
///   * positional [PathSegment] encoding regression (kind tag stays
///     a string; coordinates stay ungrouped)
void main() {
  group('RectMask', () {
    final r = const RectMask(rect: Rect.fromLTWH(10, 10, 80, 60));

    test('round-trip preserves rect and omits defaults', () {
      final json = r.toJson() as Map<String, dynamic>;
      expect(json[LayerMask.shapeRect != 'rect' ? 'shape' : 'shape'],
          LayerMask.shapeRect);
      expect(json['rect'], <double>[10, 10, 80, 60]);
      expect(json.containsKey('inverted'), isFalse);
      expect(json.containsKey('feather'), isFalse);

      final back = LayerMask.fromJson(json) as RectMask;
      expect(back, r);
    });

    test('inverted + feather are persisted when non-default', () {
      final m = const RectMask(
        rect: Rect.fromLTWH(0, 0, 100, 100),
        inverted: true,
        feather: 8.5,
      );
      final json = m.toJson() as Map<String, dynamic>;
      expect(json['inverted'], true);
      expect(json['feather'], 8.5);
      expect(LayerMask.fromJson(json), m);
    });

    test('sampleAlpha is binary inside/outside without feather', () {
      expect(r.sampleAlpha(const Offset(50, 40)), 1.0);
      expect(r.sampleAlpha(const Offset(0, 0)), 0.0);
      // Edge points are inclusive (matches Rect.contains semantics).
      expect(r.sampleAlpha(const Offset(10, 10)), 1.0);
    });

    test('feathered rect ramps linearly outside the boundary', () {
      final m = const RectMask(
        rect: Rect.fromLTWH(0, 0, 100, 100),
        feather: 10,
      );
      // Deep inside → 1.0.
      expect(m.sampleAlpha(const Offset(50, 50)), 1.0);
      // Boundary itself → still 1.0 (ramp extends outward).
      expect(m.sampleAlpha(const Offset(100, 50)), 1.0);
      // 5 px outside → mid-ramp (0.5).
      expect(m.sampleAlpha(const Offset(105, 50)), closeTo(0.5, 1e-9));
      // 11 px outside → past the ramp.
      expect(m.sampleAlpha(const Offset(111, 50)), 0.0);
    });

    test('inverted flips alpha (1 - α)', () {
      final m = const RectMask(
        rect: Rect.fromLTWH(0, 0, 100, 100),
        inverted: true,
      );
      expect(m.sampleAlpha(const Offset(50, 50)), 0.0);
      expect(m.sampleAlpha(const Offset(-1, -1)), 1.0);
    });
  });

  group('EllipseMask', () {
    final m = const EllipseMask(bounds: Rect.fromLTWH(0, 0, 100, 100));

    test('round-trip preserves bounds and omits defaults', () {
      final json = m.toJson() as Map<String, dynamic>;
      expect(json['shape'], LayerMask.shapeEllipse);
      expect(json['bounds'], <double>[0, 0, 100, 100]);
      expect(json.containsKey('inverted'), isFalse);
      expect(json.containsKey('feather'), isFalse);
      expect(LayerMask.fromJson(json), m);
    });

    test('sampleAlpha is binary inside / outside circle without feather',
        () {
      expect(m.sampleAlpha(const Offset(50, 50)), 1.0); // center
      expect(m.sampleAlpha(const Offset(50, 0)), 1.0); // boundary inclusive
      expect(m.sampleAlpha(const Offset(0, 0)), 0.0); // corner
      expect(m.sampleAlpha(const Offset(100, 100)), 0.0);
    });

    test('feathered ellipse ramps outside the unit boundary', () {
      final feathered = const EllipseMask(
        bounds: Rect.fromLTWH(0, 0, 100, 100),
        feather: 10,
      );
      // Inside boundary stays 1.
      expect(feathered.sampleAlpha(const Offset(50, 50)), 1.0);
      // 5 px past boundary along x → mid-ramp (~0.5).
      expect(
        feathered.sampleAlpha(const Offset(105, 50)),
        closeTo(0.5, 1e-9),
      );
      // 11 px past → 0.
      expect(feathered.sampleAlpha(const Offset(111, 50)), 0.0);
    });

    test('zero-area ellipse samples 0 everywhere (no NaN)', () {
      const m = EllipseMask(bounds: Rect.fromLTWH(50, 50, 0, 0));
      expect(m.sampleAlpha(const Offset(50, 50)), 0.0);
    });
  });

  group('PathMask', () {
    final p = PathMask(
      contours: [
        const PathContour(
          start: Offset(0, 0),
          segments: [
            LineSegment(end: Offset(100, 0)),
            QuadSegment(control: Offset(150, 50), end: Offset(100, 100)),
            CubicSegment(
              control1: Offset(75, 120),
              control2: Offset(25, 120),
              end: Offset(0, 100),
            ),
            LineSegment(end: Offset(0, 0)),
          ],
        ),
      ],
    );

    test('round-trip preserves contours, segments, and fill type', () {
      final json = p.toJson() as Map<String, dynamic>;
      expect(json['shape'], LayerMask.shapePath);
      expect(json.containsKey('fillType'), isFalse); // default = nonZero
      final back = LayerMask.fromJson(json) as PathMask;
      expect(back, p);
    });

    test('non-default fillType (evenOdd) round-trips and is persisted',
        () {
      final m = PathMask(
        contours: p.contours,
        fillType: PathFillType.evenOdd,
      );
      final json = m.toJson() as Map<String, dynamic>;
      expect(json['fillType'], 'evenOdd');
      expect(LayerMask.fromJson(json), m);
    });

    test('sampleAlpha returns binary inside/outside coverage', () {
      // PathMask used to throw UnimplementedError pre-renderer.
      // The renderer now ships a coverage sampler that materialises
      // the path lazily and queries `path.contains` — feather is
      // intentionally still ignored (see PathMask.sampleAlpha doc).
      // The shape spans roughly (0,0)..(150,120).
      expect(p.sampleAlpha(const Offset(50, 50)), 1.0,
          reason: 'point well inside the shape reads opaque');
      expect(p.sampleAlpha(const Offset(500, 500)), 0.0,
          reason: 'point outside the shape reads zero');
    });

    test('inverted PathMask flips inside/outside', () {
      final inverted = PathMask(
        contours: p.contours,
        fillType: p.fillType,
        inverted: true,
      );
      expect(inverted.sampleAlpha(const Offset(50, 50)), 0.0);
      expect(inverted.sampleAlpha(const Offset(500, 500)), 1.0);
    });

    test('PathSegment positional encoding: kind tag is a STRING, '
        'coordinates are flat doubles (size regression)', () {
      final seg = const CubicSegment(
        control1: Offset(1, 2),
        control2: Offset(3, 4),
        end: Offset(5, 6),
      );
      final json = seg.toJson();
      expect(json, <Object>['cubic', 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
      // Specifically: NOT [3, ...] (int tag) and NOT
      // [{"type": "cubic", "control1": {...}, ...}] (named map).
      expect(json[0], isA<String>());
      expect(json.length, 7);
    });

    test('every PathSegment kind round-trips via PathSegment.fromJson',
        () {
      const segs = <PathSegment>[
        LineSegment(end: Offset(10, 20)),
        QuadSegment(control: Offset(5, 5), end: Offset(15, 25)),
        CubicSegment(
          control1: Offset(1, 1),
          control2: Offset(2, 2),
          end: Offset(3, 3),
        ),
      ];
      for (final s in segs) {
        expect(PathSegment.fromJson(s.toJson()), s);
      }
    });
  });

  group('LayerMask.composedAlpha (min α)', () {
    final r = const RectMask(rect: Rect.fromLTWH(0, 0, 100, 100));
    final e = const EllipseMask(bounds: Rect.fromLTWH(50, 0, 100, 100));

    test('null + null = 1.0', () {
      expect(LayerMask.composedAlpha(null, null, Offset.zero), 1.0);
    });

    test('one null defers to the other', () {
      expect(
        LayerMask.composedAlpha(r, null, const Offset(50, 50)),
        1.0,
      );
      expect(
        LayerMask.composedAlpha(null, r, const Offset(-1, -1)),
        0.0,
      );
    });

    test('both opaque → 1.0; one transparent → 0.0', () {
      // (75, 50) is inside both rect [0..100]² and ellipse centered
      // at (100, 50) with rx=ry=50.
      expect(
        LayerMask.composedAlpha(r, e, const Offset(75, 50)),
        1.0,
      );
      // (25, 50) is inside the rect but outside the ellipse.
      expect(
        LayerMask.composedAlpha(r, e, const Offset(25, 50)),
        0.0,
      );
    });
  });

  group('LayerMask.fromJson error handling', () {
    test('non-Map input throws FormatException', () {
      expect(() => LayerMask.fromJson(42), throwsFormatException);
    });

    test('unknown shape discriminator throws', () {
      expect(
        () => LayerMask.fromJson({'shape': 'pentagon'}),
        throwsFormatException,
      );
    });

    test('out-of-range feather throws', () {
      expect(
        () => LayerMask.fromJson({
          'shape': 'rect',
          'rect': [0, 0, 10, 10],
          'feather': LayerMask.maxFeatherPx + 1,
        }),
        throwsFormatException,
      );
    });

    test('malformed rect throws', () {
      expect(
        () => LayerMask.fromJson({'shape': 'rect', 'rect': [0, 0, 10]}),
        throwsFormatException,
      );
    });

    test('malformed PathSegment throws', () {
      expect(
        () => PathSegment.fromJson(<dynamic>['line', 1]),
        throwsFormatException,
      );
      expect(
        () => PathSegment.fromJson(<dynamic>['unknown', 1, 2]),
        throwsFormatException,
      );
    });
  });

  group('equality / hashCode', () {
    test('RectMask: structural equality on all fields', () {
      const a = RectMask(rect: Rect.fromLTWH(0, 0, 10, 10));
      const b = RectMask(rect: Rect.fromLTWH(0, 0, 10, 10));
      const c = RectMask(rect: Rect.fromLTWH(0, 0, 10, 11));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('EllipseMask: feather and inverted participate', () {
      const a = EllipseMask(bounds: Rect.fromLTWH(0, 0, 10, 10));
      const b = EllipseMask(
        bounds: Rect.fromLTWH(0, 0, 10, 10),
        feather: 1,
      );
      expect(a, isNot(b));
    });

    test('PathMask: structural equality reaches into segments', () {
      final a = PathMask(contours: [
        const PathContour(
          start: Offset(0, 0),
          segments: [LineSegment(end: Offset(10, 10))],
        ),
      ]);
      final b = PathMask(contours: [
        const PathContour(
          start: Offset(0, 0),
          segments: [LineSegment(end: Offset(10, 10))],
        ),
      ]);
      final c = PathMask(contours: [
        const PathContour(
          start: Offset(0, 0),
          segments: [LineSegment(end: Offset(10, 11))],
        ),
      ]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('asserts', () {
    test('feather > maxFeatherPx asserts', () {
      expect(
        () => RectMask(
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          feather: LayerMask.maxFeatherPx + 1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('negative feather asserts', () {
      expect(
        () => RectMask(
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          feather: -1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
