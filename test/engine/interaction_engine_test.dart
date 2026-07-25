import 'dart:math' as math;
import 'dart:ui';

import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_capabilities.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:canvas_engine/features/editor/engine/interaction/interaction_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = InteractionEngine();
  final base = LayerTransform(
    position: const Offset(100, 100),
    size: const Size(200, 100),
  );

  group('move', () {
    test('translates by pointer delta', () {
      final session = engine.startMove(
        layerId: 'a',
        transform: base,
        pointer: const Offset(150, 150),
      );
      final next = engine.updateMove(session, const Offset(200, 180));
      expect(next.position, const Offset(150, 130));
      expect(next.size, base.size);
      expect(next.rotation, base.rotation);
    });
  });

  group('resize (axis-aligned)', () {
    test('bottomRight grows width/height, keeps top-left pinned', () {
      final session = engine.startResize(
        layerId: 'a',
        transform: base,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(300, 200), // at bottom-right corner
      );
      final next = engine.updateResize(session, const Offset(400, 260));
      expect(next.position, base.position);
      expect(next.size, const Size(300, 160));
    });

    test('topLeft shrinks, keeps bottom-right pinned', () {
      final session = engine.startResize(
        layerId: 'a',
        transform: base,
        corner: InteractionHandle.topLeft,
        pointer: const Offset(100, 100),
      );
      final next = engine.updateResize(session, const Offset(150, 130));
      // bottom-right must still be at (300, 200)
      final br = Offset(
        next.position.dx + next.size.width,
        next.position.dy + next.size.height,
      );
      expect(br.dx, closeTo(300, 1e-6));
      expect(br.dy, closeTo(200, 1e-6));
    });

    test('enforces minimum size', () {
      final session = engine.startResize(
        layerId: 'a',
        transform: base,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(300, 200),
      );
      final next = engine.updateResize(session, const Offset(-500, -500));
      expect(next.size.width, greaterThanOrEqualTo(24));
      expect(next.size.height, greaterThanOrEqualTo(24));
    });
  });

  group('resize (rotated)', () {
    test('bottomRight resize on 90deg-rotated layer keeps anchor stable', () {
      final rotated = base.copyWith(rotation: math.pi / 2);
      // After rotating 90deg about center (200,150): local bottom-right
      // (300,200) maps to canvas (150, 250). That's where the user grabs.
      final anchor = rotated.corners[0]; // top-left is anchor (opposite BR)
      final session = engine.startResize(
        layerId: 'a',
        transform: rotated,
        corner: InteractionHandle.bottomRight,
        pointer: rotated.corners[2],
      );
      // Move grabbed corner 30 units in canvas space.
      final next = engine.updateResize(
        session,
        rotated.corners[2] + const Offset(30, 40),
      );
      // The anchor corner (top-left of local rect, index 0 in corners) should
      // remain (approx) unchanged after the resize.
      final newAnchor = next.corners[0];
      expect(newAnchor.dx, closeTo(anchor.dx, 1e-3));
      expect(newAnchor.dy, closeTo(anchor.dy, 1e-3));
    });
  });

  group('rotate', () {
    test('rotates by angle delta around center', () {
      final session = engine.startRotate(
        layerId: 'a',
        transform: base,
        pointer: const Offset(300, 150), // to the right of center
      );
      final next = engine.updateRotate(session, const Offset(200, 250));
      // from +X axis to +Y axis => +pi/2 delta
      expect(next.rotation, closeTo(math.pi / 2, 1e-6));
    });

    test('snaps to nearest 45deg multiple within threshold', () {
      // 44.5deg should snap to 45deg (pi/4).
      expect(
        engine.snapRotation(44.5 * math.pi / 180),
        closeTo(math.pi / 4, 1e-9),
      );
      // 40deg is outside the ~4deg threshold of 45deg -> unchanged.
      expect(
        engine.snapRotation(40 * math.pi / 180),
        closeTo(40 * math.pi / 180, 1e-9),
      );
      // 0deg is a snap target.
      expect(engine.snapRotation(2 * math.pi / 180), closeTo(0, 1e-9));
    });

    test('snap=false bypasses magnetic zone', () {
      final session = engine.startRotate(
        layerId: 'a',
        transform: base,
        pointer: const Offset(300, 150),
      );
      // End point 1deg away from the start direction.
      final next = engine.updateRotate(
        session,
        const Offset(300, 150 + 5), // tiny angle delta
        snap: false,
      );
      // Must NOT be clamped to 0.
      expect(next.rotation.abs(), greaterThan(0));
    });
  });

  group('capabilities min size', () {
    test('respects LayerCapabilities.minWidth over engine floor', () {
      final session = engine.startResize(
        layerId: 'a',
        transform: base,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(300, 200),
      );
      final next = engine.updateResize(
        session,
        const Offset(-500, -500),
        capabilities: const LayerCapabilities(minWidth: 80, minHeight: 60),
      );
      expect(next.size.width, closeTo(80, 1e-6));
      expect(next.size.height, closeTo(60, 1e-6));
    });

    test('an aspect-locked resize still clears BOTH floors', () {
      // The aspect correction shrinks one axis, which could undo the
      // min-size clamp applied just before it. On a 200x100 layer the
      // width clamped to 24, then the lock pulled height down to 12 —
      // half the engine floor. Both axes have to clear it, and the
      // ratio has to survive.
      final session = engine.startResize(
        layerId: 'a',
        transform: base,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(300, 200),
      );
      final next = engine.updateResize(
        session,
        const Offset(-500, -500),
        capabilities: const LayerCapabilities(keepsAspectRatio: true),
      );

      expect(
        next.size.width,
        greaterThanOrEqualTo(EngineConstants.minLayerSize - 1e-6),
      );
      expect(
        next.size.height,
        greaterThanOrEqualTo(EngineConstants.minLayerSize - 1e-6),
      );
      expect(
        next.size.width / next.size.height,
        closeTo(base.size.width / base.size.height, 1e-6),
        reason: 'the bump is uniform, so the locked ratio survives it',
      );
    });

    test('a portrait aspect-locked resize clears them too', () {
      final portrait = LayerTransform(
        position: const Offset(0, 0),
        size: const Size(1080, 1350),
      );
      final session = engine.startResize(
        layerId: 'a',
        transform: portrait,
        corner: InteractionHandle.bottomRight,
        pointer: const Offset(1080, 1350),
      );
      final next = engine.updateResize(
        session,
        const Offset(-9000, -9000),
        capabilities: const LayerCapabilities(keepsAspectRatio: true),
      );
      expect(
        math.min(next.size.width, next.size.height),
        greaterThanOrEqualTo(EngineConstants.minLayerSize - 1e-6),
      );
      expect(next.size.width / next.size.height, closeTo(1080 / 1350, 1e-6));
    });
  });

  group('gesture', () {
    test('two-finger pinch scales size uniformly around the focal point', () {
      final session = engine.startGesture(
        layerId: 'a',
        transform: base,
        focalPoint: base.center,
      );
      final r = engine.updateGesture(
        session,
        focalPoint: base.center,
        scale: 2.0,
        rotation: 0,
      );
      expect(r.transform.size.width, closeTo(400, 1e-6));
      expect(r.transform.size.height, closeTo(200, 1e-6));
      // Focal at center ⇒ center is the anchor ⇒ it should not move.
      expect(r.transform.center.dx, closeTo(base.center.dx, 1e-6));
      expect(r.transform.center.dy, closeTo(base.center.dy, 1e-6));
      expect(r.snapped, isTrue); // rotation 0 is a snap target
    });

    test('scale is clamped to capability minimum preserving aspect', () {
      final session = engine.startGesture(
        layerId: 'a',
        transform: base,
        focalPoint: base.center,
      );
      final r = engine.updateGesture(
        session,
        focalPoint: base.center,
        scale: 0.01,
        rotation: 0,
        capabilities: const LayerCapabilities(minWidth: 50, minHeight: 50),
      );
      // Width hits its min of 50 first; effective scale = 50/200 = 0.25,
      // so height becomes 25... but height's floor is max(engineFloor=24,
      // capability=50) = 50. The second clamp picks that up.
      expect(r.transform.size.height, closeTo(50, 1e-6));
    });

    test('rotation snaps to nearest 45° within threshold', () {
      final session = engine.startGesture(
        layerId: 'a',
        transform: base,
        focalPoint: base.center,
      );
      // 44° is inside the ~4° snap zone around 45°.
      final r = engine.updateGesture(
        session,
        focalPoint: base.center,
        scale: 1.0,
        rotation: 44 * math.pi / 180,
      );
      expect(r.transform.rotation, closeTo(math.pi / 4, 1e-6));
      expect(r.snapped, isTrue);
    });

    test('scale-in-place: the layer scales around its own centre '
        'regardless of where the focal is', () {
      // Previous engine behaviour anchored the point under the initial
      // focal to stay under the current focal ("Procreate free-transform"
      // model). That produced visible positional drift whenever the
      // focal was off-centre, which users experience as "the object
      // flies away when I pinch". Current behaviour (matches Canva /
      // CapCut / Figma mobile): scale and rotation are applied around
      // the layer's own centre; the focal delta contributes only
      // translation.
      final focal0 = base.position; // Top-left, i.e. off-centre.
      final session = engine.startGesture(
        layerId: 'a',
        transform: base,
        focalPoint: focal0,
      );
      // Focal does not move, scale 0.5, rotation 0 \u2192 layer should
      // shrink around its own centre with zero translation.
      final r = engine.updateGesture(
        session,
        focalPoint: focal0,
        scale: 0.5,
        rotation: 0,
      );
      expect(r.transform.center.dx, closeTo(base.center.dx, 1e-4));
      expect(r.transform.center.dy, closeTo(base.center.dy, 1e-4));
      expect(r.transform.size.width, closeTo(base.size.width * 0.5, 1e-4));
      expect(r.transform.size.height, closeTo(base.size.height * 0.5, 1e-4));
    });

    test('focal delta translates the layer 1:1', () {
      final focal0 = base.center;
      final session = engine.startGesture(
        layerId: 'a',
        transform: base,
        focalPoint: focal0,
      );
      // Scale 1, rotation 0, focal moves by (30, -40) \u2192 layer
      // centre must move by exactly that delta.
      final r = engine.updateGesture(
        session,
        focalPoint: focal0 + const Offset(30, -40),
        scale: 1.0,
        rotation: 0,
      );
      expect(r.transform.center.dx, closeTo(base.center.dx + 30, 1e-4));
      expect(r.transform.center.dy, closeTo(base.center.dy - 40, 1e-4));
      expect(r.transform.size, base.size);
    });

    test('extreme pinch up is clamped to maxGestureScale and maxLayerSize', () {
      final session = engine.startGesture(
        layerId: 'a',
        transform: base,
        focalPoint: base.center,
      );
      final r = engine.updateGesture(
        session,
        focalPoint: base.center,
        scale: 1000.0,
        rotation: 0,
      );
      // Two clamps are in play; the tighter wins.
      //   * Per-gesture scale cap: maxGestureScale = 8x
      //     → 200 * 8 = 1600 px wide.
      //   * Absolute size cap:    maxLayerSize     = 8000 px.
      // For a 200-wide layer the gesture-scale cap is much tighter,
      // so width is clamped to 1600 and aspect (2:1) is preserved.
      expect(
        r.transform.size.width,
        closeTo(base.size.width * EngineConstants.maxGestureScale, 1e-6),
      );
      expect(
        r.transform.size.width,
        lessThanOrEqualTo(EngineConstants.maxLayerSize),
      );
      expect(
        r.transform.size.width / r.transform.size.height,
        closeTo(base.size.width / base.size.height, 1e-6),
      );
    });

    test('extreme pinch down is clamped to minGestureScale', () {
      final session = engine.startGesture(
        layerId: 'a',
        transform: base,
        focalPoint: base.center,
      );
      final r = engine.updateGesture(
        session,
        focalPoint: base.center,
        scale: 0.0001,
        rotation: 0,
      );
      // minGestureScale = 0.02 would give 4x2, but minHeight floor of 24
      // clamps height; aspect preservation then raises width above 4.
      expect(r.transform.size.height, greaterThanOrEqualTo(24));
      expect(
        r.transform.size.width / r.transform.size.height,
        closeTo(base.size.width / base.size.height, 1e-6),
      );
    });

    test('maxLayerSize cap applies when initial layer is already large', () {
      final big = LayerTransform(
        position: Offset.zero,
        size: const Size(2000, 1000),
      );
      final session = engine.startGesture(
        layerId: 'a',
        transform: big,
        focalPoint: big.center,
      );
      final r = engine.updateGesture(
        session,
        focalPoint: big.center,
        scale: 8.0,
        rotation: 0,
      );
      // 2000 * 8 = 16000 would exceed the 8000 cap; effective scale
      // collapses to 8000/2000 = 4 and height follows aspect.
      expect(r.transform.size.width, closeTo(8000, 1e-6));
      expect(r.transform.size.height, closeTo(4000, 1e-6));
    });
  });
}
