import 'dart:math' as math;
import 'dart:ui';

import 'package:canvas_engine/features/editor/engine/commands/shape_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:canvas_engine/features/editor/engine/interaction/interaction_engine.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the generic interaction + document pipeline works for a third
/// layer type (primitive shapes), with NO engine changes.
void main() {
  const engine = InteractionEngine();

  ShapeLayer makeRect() => const ShapeLayer(
    id: 'rect-1',
    transform: LayerTransform(position: Offset(50, 50), size: Size(200, 100)),
    kind: ShapeKind.rectangle,
  );

  ShapeLayer makeCircle() => const ShapeLayer(
    id: 'circle-1',
    transform: LayerTransform(position: Offset(0, 0), size: Size(120, 120)),
    kind: ShapeKind.circle,
  );

  group('ShapeLayer — capabilities', () {
    test(
      'rectangle: movable/resizable/rotatable/deletable, not editable, free aspect',
      () {
        final c = makeRect().capabilities;
        expect(c.movable, isTrue);
        expect(c.resizable, isTrue);
        expect(c.rotatable, isTrue);
        expect(c.deletable, isTrue);
        expect(c.editable, isFalse);
        expect(c.keepsAspectRatio, isFalse);
      },
    );

    test('circle locks aspect by default (mirrors Paint scale mode)', () {
      // Bug fix: dragging a circle's corner used to stretch it into an
      // oval. The fix is the same principle PaintLayer already uses —
      // expose `keepsAspectRatio: true` via capabilities and let the
      // generic InteractionEngine.updateResize honour it.
      expect(makeCircle().capabilities.keepsAspectRatio, isTrue);
    });

    test('aspect-locked vs free per ShapeKind matches the contract', () {
      // Single source of truth so the constructor's inline conditional
      // and the public predicate cannot drift apart.
      const aspectLocked = {
        ShapeKind.circle,
        ShapeKind.triangle,
        ShapeKind.diamond,
        ShapeKind.hexagon,
        ShapeKind.star,
        ShapeKind.heart,
        ShapeKind.plus,
        ShapeKind.check,
        ShapeKind.cross,
        // 2026-08 growth (shape studio doc §2): fixed-silhouette
        // kinds lock; container / free-form kinds stay free.
        ShapeKind.pentagon,
        ShapeKind.octagon,
        ShapeKind.ring,
        ShapeKind.sparkle,
        ShapeKind.seal,
        ShapeKind.bolt,
        ShapeKind.shield,
        ShapeKind.crescent,
      };
      for (final k in ShapeKind.values) {
        expect(
          isAspectLockedShapeKind(k),
          aspectLocked.contains(k),
          reason: 'mismatch for $k',
        );
        final layer = ShapeLayer(
          id: 'k-${k.name}',
          transform: const LayerTransform(
            position: Offset.zero,
            size: Size(100, 100),
          ),
          kind: k,
        );
        expect(
          layer.capabilities.keepsAspectRatio,
          aspectLocked.contains(k),
          reason: 'capability mismatch for $k',
        );
      }
    });
  });

  group('ShapeLayer — generic interaction engine', () {
    test('move translates rectangle by pointer delta', () {
      final shape = makeRect();
      final s = engine.startMove(
        layerId: shape.id,
        transform: shape.transform,
        pointer: const Offset(100, 100),
      );
      final next = engine.updateMove(s, const Offset(130, 120));
      expect(next.position, const Offset(80, 70));
      expect(next.size, shape.transform.size);
    });

    test('pinch scales circle uniformly around focal', () {
      final shape = makeCircle();
      final s = engine.startGesture(
        layerId: shape.id,
        transform: shape.transform,
        focalPoint: shape.transform.center,
      );
      final r = engine.updateGesture(
        s,
        focalPoint: shape.transform.center,
        scale: 2.0,
        rotation: 0,
        capabilities: shape.capabilities,
      );
      expect(r.transform.size.width, closeTo(240, 1e-6));
      expect(r.transform.size.height, closeTo(240, 1e-6));
      expect(r.transform.center.dx, closeTo(shape.transform.center.dx, 1e-6));
      expect(r.transform.center.dy, closeTo(shape.transform.center.dy, 1e-6));
    });

    test('rotate around center', () {
      final shape = makeRect();
      final s = engine.startRotate(
        layerId: shape.id,
        transform: shape.transform,
        pointer: Offset(
          shape.transform.center.dx + 50,
          shape.transform.center.dy,
        ), // +X
      );
      final next = engine.updateRotate(
        s,
        Offset(shape.transform.center.dx, shape.transform.center.dy + 50), // +Y
      );
      expect(next.rotation, closeTo(math.pi / 2, 1e-6));
    });

    test('non-uniform corner resize: free aspect (rectangle)', () {
      final shape = makeRect();
      final s = engine.startResize(
        layerId: shape.id,
        transform: shape.transform,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(250, 150), // at bottom-right corner
      );
      final next = engine.updateResize(
        s,
        const Offset(350, 250), // +100 both axes
        capabilities: shape.capabilities,
      );
      expect(next.size.width, closeTo(300, 1e-6));
      expect(next.size.height, closeTo(200, 1e-6));
      // Top-left anchor unchanged.
      expect(next.position, shape.transform.position);
    });

    test('corner resize on circle preserves aspect (stays a circle)', () {
      // Bug repro: dragging the bottom-right corner of a 120x120 circle
      // by an unequal pointer delta used to produce an oval. Now the
      // engine consults `keepsAspectRatio` and normalises.
      final shape = makeCircle();
      final s = engine.startResize(
        layerId: shape.id,
        transform: shape.transform,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(120, 120),
      );
      final next = engine.updateResize(
        s,
        const Offset(260, 200), // very unequal delta
        capabilities: shape.capabilities,
      );
      expect(
        next.size.width / next.size.height,
        closeTo(1.0, 1e-9),
        reason: 'circle must remain 1:1',
      );
    });

    test('corner resize on star preserves aspect', () {
      final shape = ShapeLayer(
        id: 'star-1',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(200, 200),
        ),
        kind: ShapeKind.star,
      );
      final s = engine.startResize(
        layerId: shape.id,
        transform: shape.transform,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(200, 200),
      );
      final next = engine.updateResize(
        s,
        const Offset(420, 280),
        capabilities: shape.capabilities,
      );
      expect(next.size.width / next.size.height, closeTo(1.0, 1e-9));
    });

    test('corner resize on roundedRectangle still stretches freely', () {
      // Container kinds intentionally remain free — the user can make
      // a wide button or a tall sidebar by dragging.
      final shape = ShapeLayer(
        id: 'rr-1',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(200, 100),
        ),
        kind: ShapeKind.roundedRectangle,
      );
      final s = engine.startResize(
        layerId: shape.id,
        transform: shape.transform,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(200, 100),
      );
      final next = engine.updateResize(
        s,
        const Offset(400, 150), // +200 width, +50 height
        capabilities: shape.capabilities,
      );
      expect(next.size.width, closeTo(400, 1e-6));
      expect(next.size.height, closeTo(150, 1e-6));
    });

    test('gesture on non-editable shape still moves/scales/rotates', () {
      // editable=false must not block transformation — only text editing
      // (a future concern) respects that flag.
      final shape = makeRect();
      final s = engine.startGesture(
        layerId: shape.id,
        transform: shape.transform,
        focalPoint: shape.transform.center,
      );
      final r = engine.updateGesture(
        s,
        focalPoint: shape.transform.center,
        scale: 1.2,
        rotation: math.pi / 6,
        capabilities: shape.capabilities,
      );
      expect(r.transform.size.width, closeTo(240, 1e-6));
      expect(r.transform.rotation, closeTo(math.pi / 6, 1e-6));
    });
  });

  group('ShapeLayer — document pipeline', () {
    test('add / replace (transform) / remove round-trips', () {
      var doc = EditorDocument.empty;
      final shape = makeRect();
      doc = AddLayerCommand(shape).apply(doc);
      expect(doc.layerById(shape.id)!.type, 'shape');

      doc = SetLayerTransformCommand(
        layerId: shape.id,
        transform: shape.transform.copyWith(rotation: 0.3),
      ).apply(doc);
      final rotated = doc.layerById(shape.id)!;
      expect(rotated, isA<ShapeLayer>());
      expect(rotated.transform.rotation, 0.3);
      // Shape-specific fields preserved across generic transform update.
      expect((rotated as ShapeLayer).kind, ShapeKind.rectangle);

      doc = RemoveLayerCommand(shape.id).apply(doc);
      expect(doc.layerById(shape.id), isNull);
    });
  });

  group('ShapeLayer — explicit resizeMode override', () {
    test('rectangle with resizeMode: scale locks aspect on corner drag', () {
      // The user picked Scale on the floating toolbar; the engine
      // must respect that even though rectangles default to free.
      const shape = ShapeLayer(
        id: 'rect-scale',
        transform: LayerTransform(position: Offset(0, 0), size: Size(200, 100)),
        kind: ShapeKind.rectangle,
        resizeMode: ShapeResizeMode.scale,
      );
      expect(shape.capabilities.keepsAspectRatio, isTrue);
      expect(shape.effectiveResizeMode, ShapeResizeMode.scale);

      final s = engine.startResize(
        layerId: shape.id,
        transform: shape.transform,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(200, 100),
      );
      final next = engine.updateResize(
        s,
        const Offset(420, 280), // very unequal delta
        capabilities: shape.capabilities,
      );
      expect(
        next.size.width / next.size.height,
        closeTo(200 / 100, 1e-9),
        reason: 'rectangle in Scale must keep its starting 2:1 ratio',
      );
    });

    test('circle with resizeMode: free stretches into an oval', () {
      // The user picked Free on the floating toolbar; the engine
      // must allow stretch even though circles default to scale.
      const shape = ShapeLayer(
        id: 'circle-free',
        transform: LayerTransform(position: Offset(0, 0), size: Size(120, 120)),
        kind: ShapeKind.circle,
        resizeMode: ShapeResizeMode.free,
      );
      expect(shape.capabilities.keepsAspectRatio, isFalse);
      expect(shape.effectiveResizeMode, ShapeResizeMode.free);

      final s = engine.startResize(
        layerId: shape.id,
        transform: shape.transform,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(120, 120),
      );
      final next = engine.updateResize(
        s,
        const Offset(260, 200),
        capabilities: shape.capabilities,
      );
      expect(next.size.width, closeTo(260, 1e-6));
      expect(next.size.height, closeTo(200, 1e-6));
    });

    test('effectiveResizeMode falls back to kind default when null', () {
      expect(makeRect().effectiveResizeMode, ShapeResizeMode.free);
      expect(makeCircle().effectiveResizeMode, ShapeResizeMode.scale);
    });
  });

  group('ShapeLayer — resizeMode JSON round-trip', () {
    test('explicit resizeMode is persisted and restored', () {
      const original = ShapeLayer(
        id: 'rect-scale',
        transform: LayerTransform(position: Offset(0, 0), size: Size(200, 100)),
        kind: ShapeKind.rectangle,
        resizeMode: ShapeResizeMode.scale,
      );
      final json = original.toJson();
      expect(json['resizeMode'], 'scale');
      final restored = ShapeLayer.fromJson(json);
      expect(restored.resizeMode, ShapeResizeMode.scale);
      expect(restored.capabilities.keepsAspectRatio, isTrue);
    });

    test('legacy JSON without resizeMode falls back to kind default', () {
      final json = makeCircle().toJson();
      // Pre-resize-mode files never wrote this field.
      expect(json.containsKey('resizeMode'), isFalse);
      final restored = ShapeLayer.fromJson(json);
      expect(restored.resizeMode, isNull);
      expect(restored.effectiveResizeMode, ShapeResizeMode.scale);
      expect(restored.capabilities.keepsAspectRatio, isTrue);
    });

    test('null resizeMode is omitted; explicit free is persisted', () {
      const free = ShapeLayer(
        id: 'circle-free',
        transform: LayerTransform(position: Offset.zero, size: Size(100, 100)),
        kind: ShapeKind.circle,
        resizeMode: ShapeResizeMode.free,
      );
      final json = free.toJson();
      expect(json['resizeMode'], 'free');
      final restored = ShapeLayer.fromJson(json);
      expect(restored.resizeMode, ShapeResizeMode.free);
      expect(restored.capabilities.keepsAspectRatio, isFalse);
    });
  });

  group('SetShapeResizeModeCommand — invert', () {
    // Circle with a null (kind-default) resizeMode; its effective mode
    // resolves to scale. Setting it to an explicit `scale` is a real
    // change (null -> scale), and undo must restore the null so the
    // document serializes byte-identically to before the edit.
    EditorDocument seedCircle() => EditorDocument(layers: [makeCircle()]);

    test('restores a null (kind-default) resizeMode on undo', () {
      final before = seedCircle();
      expect(before.layerById('circle-1')! is ShapeLayer, isTrue);
      final layer0 = before.layerById('circle-1')! as ShapeLayer;
      expect(layer0.resizeMode, isNull);
      expect(layer0.effectiveResizeMode, ShapeResizeMode.scale);

      const cmd = SetShapeResizeModeCommand(
        layerId: 'circle-1',
        mode: ShapeResizeMode.scale,
      );
      final after = cmd.apply(before);
      final movedLayer = after.layerById('circle-1')! as ShapeLayer;
      expect(
        movedLayer.resizeMode,
        ShapeResizeMode.scale,
        reason: 'apply stores the explicit override',
      );

      // invert(before).apply(after) must reproduce `before` exactly.
      final restored = cmd.invert(before).apply(after);
      final restoredLayer = restored.layerById('circle-1')! as ShapeLayer;
      expect(
        restoredLayer.resizeMode,
        isNull,
        reason: 'undo clears the override back to the kind default',
      );
      expect(restoredLayer, equals(layer0));
    });

    test('undo round-trips byte-identical JSON', () {
      final before = seedCircle();
      const cmd = SetShapeResizeModeCommand(
        layerId: 'circle-1',
        mode: ShapeResizeMode.scale,
      );
      final after = cmd.apply(before);
      final restored = cmd.invert(before).apply(after);

      final beforeJson = (before.layerById('circle-1')! as ShapeLayer).toJson();
      final restoredJson = (restored.layerById('circle-1')! as ShapeLayer)
          .toJson();
      expect(
        restoredJson.containsKey('resizeMode'),
        isFalse,
        reason: 'a restored kind-default must omit the field, as before',
      );
      expect(restoredJson, equals(beforeJson));
    });
  });
}
