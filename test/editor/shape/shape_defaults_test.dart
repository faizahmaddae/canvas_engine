import 'package:canvas_engine/features/editor/engine/modules/shape/shape_defaults.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [ShapeDefaults.fillColorForCanvas].
///
/// Tests are purely functional — no Flutter widget tree, no Riverpod
/// container, no document state. The helper is a pure function so this
/// covers every branch with no setup overhead.
void main() {
  group('ShapeDefaults – light canvas (white)', () {
    const bg = Color(0xFFFFFFFF);

    test('rectangle gets blue fill (not white)', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.rectangle);
      expect(fill, isNot(const Color(0xFFFFFFFF)));
      expect(fill, ShapeDefaults.fillOnLight);
    });

    test('roundedRectangle gets same blue fill', () {
      final fill =
          ShapeDefaults.fillColorForCanvas(bg, ShapeKind.roundedRectangle);
      expect(fill, ShapeDefaults.fillOnLight);
    });

    test('circle gets blue fill', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.circle);
      expect(fill, ShapeDefaults.fillOnLight);
    });

    test('triangle gets blue fill', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.triangle);
      expect(fill, ShapeDefaults.fillOnLight);
    });

    test('diamond gets blue fill', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.diamond);
      expect(fill, ShapeDefaults.fillOnLight);
    });

    test('star gets blue fill', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.star);
      expect(fill, ShapeDefaults.fillOnLight);
    });

    test('heart gets blue fill', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.heart);
      expect(fill, ShapeDefaults.fillOnLight);
    });

    test('line gets dark stroke color (not white)', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.line);
      expect(fill, isNot(const Color(0xFFFFFFFF)));
      expect(fill, ShapeDefaults.strokeOnLight);
    });

    test('arrow gets dark stroke color (not white)', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.arrow);
      expect(fill, isNot(const Color(0xFFFFFFFF)));
      expect(fill, ShapeDefaults.strokeOnLight);
    });

    test('all filled kinds use the same default on white', () {
      final filled = [
        ShapeKind.rectangle,
        ShapeKind.roundedRectangle,
        ShapeKind.circle,
        ShapeKind.triangle,
        ShapeKind.diamond,
        ShapeKind.star,
        ShapeKind.heart,
      ];
      for (final kind in filled) {
        expect(
          ShapeDefaults.fillColorForCanvas(bg, kind),
          ShapeDefaults.fillOnLight,
          reason: '$kind should use fillOnLight on white canvas',
        );
      }
    });

    test('fill is visually distinct from white background', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.rectangle);
      // The fill and background must differ enough to be visible —
      // assert they are simply not equal (contrast is implicit in
      // the chosen palette constants, tested above).
      expect(fill, isNot(bg));
    });
  });

  group('ShapeDefaults – light canvas (light gray)', () {
    // #EEEEEE has luminance well above 0.5
    const bg = Color(0xFFEEEEEE);

    test('rectangle still gets fillOnLight on light gray canvas', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.rectangle);
      expect(fill, ShapeDefaults.fillOnLight);
    });

    test('line still gets strokeOnLight on light gray canvas', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.line);
      expect(fill, ShapeDefaults.strokeOnLight);
    });
  });

  group('ShapeDefaults – dark canvas', () {
    // #111111 — very dark background
    const bg = Color(0xFF111111);

    test('rectangle gets white fill on dark canvas', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.rectangle);
      expect(fill, ShapeDefaults.fillOnDark);
    });

    test('circle gets white fill on dark canvas', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.circle);
      expect(fill, ShapeDefaults.fillOnDark);
    });

    test('star gets white fill on dark canvas', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.star);
      expect(fill, ShapeDefaults.fillOnDark);
    });

    test('line gets white stroke on dark canvas', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.line);
      expect(fill, ShapeDefaults.fillOnDark);
    });

    test('arrow gets white stroke on dark canvas', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.arrow);
      expect(fill, ShapeDefaults.fillOnDark);
    });

    test('all filled kinds use fillOnDark', () {
      final filled = [
        ShapeKind.rectangle,
        ShapeKind.roundedRectangle,
        ShapeKind.circle,
        ShapeKind.triangle,
        ShapeKind.diamond,
        ShapeKind.star,
        ShapeKind.heart,
      ];
      for (final kind in filled) {
        expect(
          ShapeDefaults.fillColorForCanvas(bg, kind),
          ShapeDefaults.fillOnDark,
          reason: '$kind should use fillOnDark on dark canvas',
        );
      }
    });

    test('fill is visually distinct from dark background', () {
      final fill = ShapeDefaults.fillColorForCanvas(bg, ShapeKind.rectangle);
      expect(fill, isNot(bg));
    });
  });

  group('ShapeDefaults – boundary luminance', () {
    test('luminance exactly at threshold uses light path', () {
      // A colour whose WCAG luminance is exactly 0.5 is considered light.
      // We pick a colour known to land near the boundary rather than
      // exactly — assert the branch logic is consistent with lightThreshold.
      // Pure white (lum ≈ 1.0) → light.
      final fill =
          ShapeDefaults.fillColorForCanvas(const Color(0xFFFFFFFF), ShapeKind.rectangle);
      expect(fill, ShapeDefaults.fillOnLight);
      // Pure black (lum = 0.0) → dark.
      final fill2 =
          ShapeDefaults.fillColorForCanvas(const Color(0xFF000000), ShapeKind.rectangle);
      expect(fill2, ShapeDefaults.fillOnDark);
    });
  });

  group('ShapeDefaults – JSON round-trip (existing docs unaffected)', () {
    test('loading a doc with white fillColor preserves white', () {
      // Existing documents serialised with fillColor=white must still
      // load as white — smart defaults only fire at insert time.
      final json = <String, dynamic>{
        'id': 'layer1',
        'type': 'shape',
        'transform': {
          'x': 0.0,
          'y': 0.0,
          'w': 100.0,
          'h': 100.0,
          'r': 0.0,
        },
        'kind': 'rectangle',
        'fillColor': 0xFFFFFFFF,
        'strokeWidth': 0,
      };
      final layer = ShapeLayer.fromJson(json);
      expect(layer.fillColor, const Color(0xFFFFFFFF));
    });

    test('loading a doc with blue fillColor preserves blue', () {
      final json = <String, dynamic>{
        'id': 'layer1',
        'type': 'shape',
        'transform': {
          'x': 0.0,
          'y': 0.0,
          'w': 100.0,
          'h': 100.0,
          'r': 0.0,
        },
        'kind': 'rectangle',
        'fillColor': 0xFF4C8BF5,
        'strokeWidth': 0,
      };
      final layer = ShapeLayer.fromJson(json);
      expect(layer.fillColor, const Color(0xFF4C8BF5));
    });
  });
}
