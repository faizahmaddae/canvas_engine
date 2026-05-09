import 'dart:math' as math;
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:canvas_engine/features/editor/engine/interaction/interaction_engine.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests prove that a non-text layer flows through the SAME generic
/// interaction + document pipeline, with no engine changes required.
void main() {
  const engine = InteractionEngine();

  ImageLayer makeImage() => const ImageLayer(
        id: 'img-1',
        transform: LayerTransform(
          position: Offset(100, 100),
          size: Size(200, 200),
        ),
        source: ImageSource.asset('stub.png'),
      );

  group('ImageLayer — capabilities', () {
    test('keeps aspect ratio and is not editable, but is movable/resizable/rotatable/deletable', () {
      final img = makeImage();
      final c = img.capabilities;
      expect(c.keepsAspectRatio, isTrue);
      expect(c.editable, isFalse);
      expect(c.movable, isTrue);
      expect(c.resizable, isTrue);
      expect(c.rotatable, isTrue);
      expect(c.deletable, isTrue);
    });
  });

  group('ImageLayer — generic interaction engine', () {
    test('move translates by pointer delta', () {
      final img = makeImage();
      final s = engine.startMove(
        layerId: img.id,
        transform: img.transform,
        pointer: const Offset(150, 150),
      );
      final next = engine.updateMove(s, const Offset(220, 170));
      expect(next.position, const Offset(170, 120));
      expect(next.size, img.transform.size);
      expect(next.rotation, 0);
    });

    test('pinch scales uniformly around the focal point', () {
      final img = makeImage();
      final s = engine.startGesture(
        layerId: img.id,
        transform: img.transform,
        focalPoint: img.transform.center,
      );
      final r = engine.updateGesture(
        s,
        focalPoint: img.transform.center,
        scale: 1.5,
        rotation: 0,
        capabilities: img.capabilities,
      );
      expect(r.transform.size.width, closeTo(300, 1e-6));
      expect(r.transform.size.height, closeTo(300, 1e-6));
      expect(r.transform.center.dx, closeTo(img.transform.center.dx, 1e-6));
      expect(r.transform.center.dy, closeTo(img.transform.center.dy, 1e-6));
    });

    test('rotate around center', () {
      final img = makeImage();
      final s = engine.startRotate(
        layerId: img.id,
        transform: img.transform,
        pointer: const Offset(300, 200), // +X from center (200,200)
      );
      final next = engine.updateRotate(s, const Offset(200, 300)); // +Y
      expect(next.rotation, closeTo(math.pi / 2, 1e-6));
    });

    test('corner resize on aspect-locked layer preserves aspect ratio', () {
      final img = makeImage();
      final s = engine.startResize(
        layerId: img.id,
        transform: img.transform,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(300, 300),
      );
      final next = engine.updateResize(
        s,
        const Offset(400, 340), // unequal delta, aspect lock should normalize
        capabilities: img.capabilities,
      );
      // ImageLayer declares keepsAspectRatio=true; resulting aspect must
      // match the original 1:1.
      expect(
        next.size.width / next.size.height,
        closeTo(img.transform.size.width / img.transform.size.height, 1e-9),
      );
    });
  });

  group('ImageLayer — document pipeline', () {
    test('AddLayerCommand then RemoveLayerCommand round-trips generically', () {
      final img = makeImage();
      var doc = EditorDocument.empty;
      doc = const AddLayerCommand(
        ImageLayer(
          id: 'img-1',
          transform: LayerTransform(
            position: Offset(100, 100),
            size: Size(200, 200),
          ),
          source: ImageSource.asset('stub.png'),
        ),
      ).apply(doc);
      expect(doc.layerById(img.id), isNotNull);
      expect(doc.layerById(img.id)!.type, 'image');

      doc = const RemoveLayerCommand('img-1').apply(doc);
      expect(doc.layerById(img.id), isNull);
    });

    test('SetLayerTransformCommand updates an ImageLayer via generic path', () {
      var doc = EditorDocument.empty;
      final img = makeImage();
      doc = AddLayerCommand(img).apply(doc);
      doc = SetLayerTransformCommand(
        layerId: img.id,
        transform: const LayerTransform(
          position: Offset(10, 20),
          size: Size(100, 100),
          rotation: 0.5,
        ),
      ).apply(doc);

      final updated = doc.layerById(img.id)!;
      expect(updated, isA<ImageLayer>());
      expect(updated.transform.position, const Offset(10, 20));
      expect(updated.transform.size, const Size(100, 100));
      expect(updated.transform.rotation, 0.5);
    });
  });
}
