import 'dart:math' as math;
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/interaction/interaction_engine.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';

/// These tests prove that a non-text layer flows through the SAME generic
/// interaction + document pipeline, with no engine changes required.
void main() {
  const engine = InteractionEngine();

  ImageLayer makeImage() => ImageLayer(
    id: 'img-1',
    transform: const LayerTransform(
      position: Offset(100, 100),
      size: Size(200, 200),
    ),
    source: const ImageSource.asset('stub.png'),
  );

  group('ImageLayer — capabilities', () {
    test(
      'keeps aspect ratio and is not editable, but is movable/resizable/rotatable/deletable',
      () {
        final img = makeImage();
        final c = img.capabilities;
        expect(c.keepsAspectRatio, isTrue);
        expect(c.editable, isFalse);
        expect(c.movable, isTrue);
        expect(c.resizable, isTrue);
        expect(c.rotatable, isTrue);
        expect(c.deletable, isTrue);
      },
    );
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
      doc = AddLayerCommand(
        ImageLayer(
          id: 'img-1',
          transform: const LayerTransform(
            position: Offset(100, 100),
            size: Size(200, 200),
          ),
          source: const ImageSource.asset('stub.png'),
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

  // ---------------------------------------------------------------------
  // Field-preservation contract for [ImageLayer.copyAll] and the four
  // generic [EditorLayer] copy methods that delegate to it.
  //
  // The contract: invoking any [with*] (or copyAll with a single field)
  // must change ONLY the targeted JSON keys when round-tripped through
  // [DocumentCodec]. If a future field is added to [ImageLayer] but not
  // to [copyAll], the codec round-trip will silently lose it on every
  // undo/redo / save/reopen — exactly the corruption mode AGENTS.md
  // warns against. This test wedges that closed.
  // ---------------------------------------------------------------------
  group('ImageLayer — copyAll preserves every field across codec', () {
    // Build a "loaded" image with every non-default knob exercised so
    // any dropped field shows up in the encoded JSON diff.
    ImageLayer makeLoaded() => ImageLayer(
      id: 'img-loaded',
      transform: const LayerTransform(
        position: Offset(50, 60),
        size: Size(300, 200),
        rotation: 0.25,
      ),
      source: const ImageSource.asset('a.png'),
      fit: BoxFit.contain,
      mask: ImageMask.circle,
      borderColor: const Color(0xFFAB12CD),
      borderWidth: 4,
      shadowColor: const Color(0xFF112233),
      shadowBlur: 8,
      shadowOffset: const Offset(2, 3),
      shadowOpacity: 0.6,
      effects: EffectStack(
        ImageAdjustments(
          brightness: 12,
          contrast: 1.1,
          saturation: 0.9,
          exposure: -5,
          warmth: 7,
        ).toEffectStack(),
      ),
      cropRect: const Rect.fromLTRB(0.1, 0.2, 0.8, 0.9),
      filterPreset: ImageFilterPreset.warm,
      name: 'hero',
      visible: false,
      locked: true,
      opacity: 0.42,
    );

    String encode(ImageLayer l) => DocumentCodec.encode(
      EditorDocument(layers: [l], width: 1000, height: 1000),
    );

    test('copyAll() with no overrides is byte-identical', () {
      final a = makeLoaded();
      expect(encode(a.copyAll()), encode(a));
      expect(a.copyAll(), equals(a));
    });

    test('withTransform changes only the transform JSON keys', () {
      final base = makeLoaded();
      const next = LayerTransform(
        position: Offset(0, 0),
        size: Size(10, 10),
        rotation: 0,
      );
      final mutated = base.withTransform(next) as ImageLayer;
      // Identity check via direct equality on every other field.
      expect(mutated.source, base.source);
      expect(mutated.fit, base.fit);
      expect(mutated.mask, base.mask);
      expect(mutated.borderColor, base.borderColor);
      expect(mutated.borderWidth, base.borderWidth);
      expect(mutated.shadowColor, base.shadowColor);
      expect(mutated.shadowBlur, base.shadowBlur);
      expect(mutated.shadowOffset, base.shadowOffset);
      expect(mutated.shadowOpacity, base.shadowOpacity);
      expect(mutated.adjustments, base.adjustments);
      expect(mutated.cropRect, base.cropRect);
      expect(mutated.filterPreset, base.filterPreset);
      expect(mutated.name, base.name);
      expect(mutated.visible, base.visible);
      expect(mutated.locked, base.locked);
      expect(mutated.opacity, base.opacity);
      expect(mutated.transform, next);
      // Codec contract: must equal `base.copyAll(transform: next)`.
      expect(encode(mutated), encode(base.copyAll(transform: next)));
    });

    test('withVisibility / withLocked / withOpacity preserve all peers', () {
      final base = makeLoaded();

      final hid = base.withVisibility(true) as ImageLayer;
      expect(hid.visible, true);
      expect(encode(hid), encode(base.copyAll(visible: true)));

      final unlocked = base.withLocked(false) as ImageLayer;
      expect(unlocked.locked, false);
      expect(encode(unlocked), encode(base.copyAll(locked: false)));

      final dim = base.withOpacity(0.1) as ImageLayer;
      expect(dim.opacity, 0.1);
      expect(encode(dim), encode(base.copyAll(opacity: 0.1)));
    });

    test(
      'copyAll(opacity:) clamps; copyAll() never re-clamps this.opacity',
      () {
        final base = makeLoaded(); // opacity = 0.42
        // In debug builds, an out-of-range explicit value trips the
        // invariant assert (programmer error is loud). The clamp on
        // the same field is the release-mode safety net for callers
        // that pass a value derived from a slider that briefly leaves
        // the range due to rounding — assertions are stripped there
        // so the clamp is what saves the document.
        expect(
          () => base.copyAll(opacity: 1.5),
          throwsA(isA<AssertionError>()),
        );
        // In-range explicit value passes through unchanged.
        expect(base.copyAll(opacity: 0.0).opacity, 0.0);
        expect(base.copyAll(opacity: 1.0).opacity, 1.0);
        // No-op copyAll preserves the current value verbatim. This is
        // what the undo / redo equality contract relies on.
        expect(base.copyAll().opacity, base.opacity);
      },
    );

    test('copyAll(name:) sentinel: omit preserves; explicit null clears', () {
      final base = makeLoaded(); // name = 'hero'
      expect(base.copyAll().name, 'hero');
      expect(base.copyAll(name: null).name, isNull);
      expect(base.copyAll(name: 'banner').name, 'banner');
    });

    test('full document round-trip: encode → decode → re-encode is stable', () {
      final base = makeLoaded();
      final doc = EditorDocument(layers: [base], width: 1000, height: 1000);
      final encoded = DocumentCodec.encode(doc);
      final decoded = DocumentCodec.decode(encoded);
      expect(DocumentCodec.encode(decoded), encoded);
      // And running every with* through the decoded layer round-trips
      // identically to running it through the original — proves the
      // refactor preserved the codec contract end-to-end.
      final orig = doc.layers.single as ImageLayer;
      final via = decoded.layers.single as ImageLayer;
      expect(
        encode(
          via.withTransform(
                orig.transform.copyWith(position: const Offset(7, 7)),
              )
              as ImageLayer,
        ),
        encode(
          orig.withTransform(
                orig.transform.copyWith(position: const Offset(7, 7)),
              )
              as ImageLayer,
        ),
      );
    });
  });
}
