import 'dart:convert';
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// A non-finite (NaN / ±Infinity) field can only ever arrive from a math
/// bug, but JSON cannot represent one — a single non-finite value made
/// `JsonEncoder.convert` throw and rendered the whole document unsaveable
/// (and silently dropped the crash-recovery journal write). The
/// serialization boundary now coerces to 0 so a transient bad frame never
/// bricks save/autosave. Finite documents (all real ones) are untouched.
void main() {
  group('LayerTransform.toJson — non-finite guard', () {
    test('coerces NaN / Infinity fields to 0; never emits non-finite', () {
      final t = LayerTransform(
        position: Offset(double.nan, double.infinity),
        size: const Size(double.negativeInfinity, 100),
        rotation: double.nan,
      );
      final json = t.toJson();
      expect(json['x'], 0.0);
      expect(json['y'], 0.0);
      expect(json['w'], 0.0);
      expect(json['h'], 100.0);
      expect(json['r'], 0.0);
    });

    test('finite transforms serialize unchanged (byte-identity preserved)', () {
      const t = LayerTransform(
        position: Offset(12.5, -4),
        size: Size(200, 100),
        rotation: 1.25,
      );
      expect(t.toJson(), {
        'x': 12.5,
        'y': -4.0,
        'w': 200.0,
        'h': 100.0,
        'r': 1.25,
      });
    });

    test(
      'a document with a non-finite transform still encodes to valid JSON',
      () {
        final doc = EditorDocument(
          layers: [
            ShapeLayer(
              id: 's',
              transform: LayerTransform(
                position: Offset(double.nan, 0),
                size: const Size(100, 100),
              ),
              kind: ShapeKind.rectangle,
            ),
          ],
        );
        // Without the guard this threw JsonUnsupportedObjectError('NaN').
        final encoded = DocumentCodec.encode(doc);
        expect(() => jsonDecode(encoded), returnsNormally);
        final round = DocumentCodec.decode(encoded);
        expect(round.layers.single.transform.position.dx, 0.0);
      },
    );
  });
}
