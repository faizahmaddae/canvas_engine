import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Field-preservation suite for [PaintLayer]. Mirrors the equivalent
/// suites for [ImageLayer] / [TextLayer] / [ShapeLayer].
void main() {
  group('PaintLayer — copyAll preserves every field across codec', () {
    PaintLayer makeLoaded() => PaintLayer(
      id: 'pnt-loaded',
      transform: LayerTransform(
        position: Offset(50, 60),
        size: Size(300, 200),
        rotation: 0.25,
      ),
      kind: PaintKind.polygon,
      normalizedPoints: [
        Offset(0.0, 0.5),
        Offset(0.25, 0.0),
        Offset(0.5, 0.75),
        Offset(0.75, 0.25),
        Offset(1.0, 0.5),
      ],
      strokeColor: Color(0xFF112233),
      strokeWidth: 8,
      fillColor: Color(0xFF445566),
      sides: 7,
      // blurSigma intentionally left at the constructor default —
      // the codec only persists it when `kind == blur` (it's a
      // kind-scoped field). Using the default keeps the
      // round-trip exact for a polygon layer.
      resizeMode: PaintResizeMode.scale,
      name: 'stroke',
      visible: false,
      locked: true,
      opacity: 0.42,
    );

    String encode(PaintLayer l) => DocumentCodec.encode(
      EditorDocument(layers: [l], width: 1000, height: 1000),
    );

    test('withTransform preserves every other field', () {
      final base = makeLoaded();
      const next = LayerTransform(position: Offset(0, 0), size: Size(10, 10));
      final mutated = base.withTransform(next) as PaintLayer;
      expect(mutated.kind, base.kind);
      expect(mutated.normalizedPoints, base.normalizedPoints);
      expect(mutated.strokeColor, base.strokeColor);
      expect(mutated.strokeWidth, base.strokeWidth);
      expect(mutated.fillColor, base.fillColor);
      expect(mutated.sides, base.sides);
      expect(mutated.blurSigma, base.blurSigma);
      expect(mutated.resizeMode, base.resizeMode);
      expect(mutated.name, base.name);
      expect(mutated.visible, base.visible);
      expect(mutated.locked, base.locked);
      expect(mutated.opacity, base.opacity);
      expect(mutated.transform, next);
    });

    test('withVisibility / withLocked / withOpacity preserve all peers', () {
      final base = makeLoaded();
      final shown = base.withVisibility(true) as PaintLayer;
      expect(shown.visible, true);
      expect(shown.normalizedPoints, base.normalizedPoints);
      expect(shown.fillColor, base.fillColor);

      final unlocked = base.withLocked(false) as PaintLayer;
      expect(unlocked.locked, false);
      expect(unlocked.fillColor, base.fillColor);

      final dim = base.withOpacity(0.1) as PaintLayer;
      expect(dim.opacity, 0.1);
      expect(dim.fillColor, base.fillColor);
      expect(dim.sides, base.sides);
    });

    test('round-trip is byte-identical', () {
      final base = makeLoaded();
      final raw = encode(base);
      final back = DocumentCodec.decode(raw).layers.single as PaintLayer;
      expect(back, base);
      expect(encode(back), raw);
    });
  });
}
