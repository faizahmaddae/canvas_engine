import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: every [ImageLayer] command rebuilds the layer through
/// the private `_rebuild` helper. That helper must forward the layer
/// opacity — the [ImageLayer] constructor defaults `opacity` to 1.0,
/// so any missed forward silently overwrites the user's setting on
/// the next style edit.
void main() {
  ImageLayer makeImage({double opacity = 0.5}) => ImageLayer(
        id: 'img-1',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(100, 100),
        ),
        source: const ImageSource.asset('stub.png'),
        opacity: opacity,
      );

  group('ImageLayer command opacity preservation', () {
    test('SetImageBorderCommand preserves non-default opacity', () {
      final layer = makeImage(opacity: 0.5);
      var doc = EditorDocument.empty.addLayer(layer);

      doc = const SetImageBorderCommand(
        layerId: 'img-1',
        color: Color(0xFFFF0000),
        width: 4,
      ).apply(doc);

      final next = doc.layerById('img-1') as ImageLayer;
      expect(next.opacity, 0.5);
      expect(next.borderColor, const Color(0xFFFF0000));
      expect(next.borderWidth, 4);
    });
  });

  group('ReplaceImageSourceCommand crop preservation on undo', () {
    test('apply resets crop, invert restores both source AND crop', () {
      const originalCrop = Rect.fromLTRB(0.1, 0.1, 0.8, 0.8);
      final layer = ImageLayer(
        id: 'img-1',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(100, 100),
        ),
        source: const ImageSource.asset('a.png'),
        cropRect: originalCrop,
      );
      final before = EditorDocument.empty.addLayer(layer);

      const replace = ReplaceImageSourceCommand(
        layerId: 'img-1',
        source: ImageSource.asset('b.png'),
      );

      // Forward: source swaps, crop is intentionally reset.
      final after = replace.apply(before);
      final afterLayer = after.layerById('img-1') as ImageLayer;
      expect(afterLayer.source, const ImageSource.asset('b.png'));
      expect(afterLayer.cropRect, ImageLayer.fullCrop);

      // Inverse must restore BOTH the source and the original crop.
      final inverse = replace.invert(before);
      final restored = inverse.apply(after);
      final restoredLayer = restored.layerById('img-1') as ImageLayer;
      expect(restoredLayer.source, const ImageSource.asset('a.png'));
      expect(restoredLayer.cropRect, originalCrop);
    });
  });
}
