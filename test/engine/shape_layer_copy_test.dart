import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Field-preservation suite for [ShapeLayer]. Same intent as the
/// equivalent suites for [ImageLayer] / [TextLayer] / [PaintLayer]:
/// catch the field-loss failure mode the moment any `with*` /
/// `copyAll` drops a peer field on a path the existing tests don't
/// exercise.
void main() {
  group('ShapeLayer — copyAll preserves every field across codec', () {
    ShapeLayer makeLoaded() => const ShapeLayer(
          id: 'shp-loaded',
          transform: LayerTransform(
            position: Offset(50, 60),
            size: Size(300, 200),
            rotation: 0.25,
          ),
          kind: ShapeKind.rectangle,
          fillColor: Color(0xFF4488FF),
          fill: LinearGradientBackground(
            startColor: Color(0xFFFF0000),
            endColor: Color(0xFF00FF00),
            angleDegrees: 45,
          ),
          fillOpacity: 0.7,
          strokeColor: Color(0xFF112233),
          strokeWidth: 4,
          cornerRadius: 16,
          shadowColor: Color(0xFF222222),
          shadowBlur: 12,
          shadowOffset: Offset(2, 4),
          shadowOpacity: 0.6,
          resizeMode: ShapeResizeMode.scale,
          name: 'panel',
          visible: false,
          locked: true,
          opacity: 0.42,
        );

    String encode(ShapeLayer l) => DocumentCodec.encode(
          EditorDocument(layers: [l], width: 1000, height: 1000),
        );

    test('withTransform preserves every other field', () {
      final base = makeLoaded();
      const next = LayerTransform(
        position: Offset(0, 0),
        size: Size(10, 10),
      );
      final mutated = base.withTransform(next) as ShapeLayer;
      expect(mutated.kind, base.kind);
      expect(mutated.fillColor, base.fillColor);
      expect(mutated.fill, base.fill);
      expect(mutated.fillOpacity, base.fillOpacity);
      expect(mutated.strokeColor, base.strokeColor);
      expect(mutated.strokeWidth, base.strokeWidth);
      expect(mutated.cornerRadius, base.cornerRadius);
      expect(mutated.shadowColor, base.shadowColor);
      expect(mutated.shadowBlur, base.shadowBlur);
      expect(mutated.shadowOffset, base.shadowOffset);
      expect(mutated.shadowOpacity, base.shadowOpacity);
      expect(mutated.resizeMode, base.resizeMode);
      expect(mutated.name, base.name);
      expect(mutated.visible, base.visible);
      expect(mutated.locked, base.locked);
      expect(mutated.opacity, base.opacity);
      expect(mutated.transform, next);
    });

    test('withVisibility / withLocked / withOpacity preserve all peers',
        () {
      final base = makeLoaded();
      final shown = base.withVisibility(true) as ShapeLayer;
      expect(shown.visible, true);
      expect(shown.fill, base.fill);
      expect(shown.shadowOpacity, base.shadowOpacity);

      final unlocked = base.withLocked(false) as ShapeLayer;
      expect(unlocked.locked, false);
      expect(unlocked.fill, base.fill);
      expect(unlocked.cornerRadius, base.cornerRadius);

      final dim = base.withOpacity(0.1) as ShapeLayer;
      expect(dim.opacity, 0.1);
      expect(dim.fill, base.fill);
      expect(dim.strokeColor, base.strokeColor);
    });

    test('round-trip is byte-identical', () {
      final base = makeLoaded();
      final raw = encode(base);
      final back = DocumentCodec.decode(raw).layers.single as ShapeLayer;
      expect(back, base);
      expect(encode(back), raw);
    });
  });
}
