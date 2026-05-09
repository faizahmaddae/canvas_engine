import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/interaction_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;

/// Group session tests — driven through the new
/// `startGroup{Move|Resize|Rotate|Gesture}` controller API.
void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    c.read(documentControllerProvider.notifier).newDocument(
          width: 800,
          height: 800,
        );
    return c;
  }

  void addRect(
    ProviderContainer c, {
    required String id,
    required Offset position,
    Size size = const Size(80, 80),
  }) {
    c.read(documentControllerProvider.notifier).execute(
          AddLayerCommand(
            ShapeLayer(
              id: id,
              transform: LayerTransform(position: position, size: size),
              kind: ShapeKind.rectangle,
            ),
          ),
        );
  }

  group('group move', () {
    test('startGroupMove seeds initials for every eligible layer', () {
      final c = makeContainer();
      addRect(c, id: 'a', position: const Offset(100, 100));
      addRect(c, id: 'b', position: const Offset(300, 100));
      addRect(c, id: 'cc', position: const Offset(500, 100));
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!;
      final b = doc.layerById('b')!;
      final cc = doc.layerById('cc')!;

      c.read(interactionControllerProvider.notifier).startGroupMove(
            layers: [a, b, cc],
            pointer: const Offset(140, 140),
          );

      final state = c.read(interactionControllerProvider);
      expect(state.isGroup, isTrue);
      expect(state.groupSession?.handle, InteractionHandle.body);
      expect(state.groupSession?.initials.keys.toSet(), {'a', 'b', 'cc'});
      expect(state.groupSession?.initials['a'], a.transform);
    });

    test('updateGroup translates every layer by the same delta', () {
      final c = makeContainer();
      addRect(c, id: 'a', position: const Offset(100, 100));
      addRect(c, id: 'b', position: const Offset(300, 100));
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!;
      final b = doc.layerById('b')!;

      c.read(interactionControllerProvider.notifier).startGroupMove(
            layers: [a, b],
            pointer: const Offset(140, 140),
          );
      c.read(interactionControllerProvider.notifier).updateGroup(
            const Offset(190, 165), // delta = (50, 25)
          );

      final state = c.read(interactionControllerProvider);
      final aDelta = state.groupLive['a']!.position - a.transform.position;
      final bDelta = state.groupLive['b']!.position - b.transform.position;
      expect(aDelta, const Offset(50, 25));
      expect(bDelta, const Offset(50, 25));
    });

    test('end commits a CompositeCommand; single undo restores ALL layers',
        () {
      final c = makeContainer();
      addRect(c, id: 'a', position: const Offset(100, 100));
      addRect(c, id: 'b', position: const Offset(300, 100));
      addRect(c, id: 'cc', position: const Offset(500, 100));
      final docBefore = c.read(documentControllerProvider);
      final a = docBefore.layerById('a')!;
      final b = docBefore.layerById('b')!;
      final cc = docBefore.layerById('cc')!;

      c.read(interactionControllerProvider.notifier).startGroupMove(
            layers: [a, b, cc],
            pointer: const Offset(0, 0),
          );
      c.read(interactionControllerProvider.notifier).updateGroup(
            const Offset(100, 100),
          );
      c.read(interactionControllerProvider.notifier).end();

      final docAfter = c.read(documentControllerProvider);
      expect(docAfter.layerById('a')!.transform.position,
          a.transform.position + const Offset(100, 100));
      expect(docAfter.layerById('b')!.transform.position,
          b.transform.position + const Offset(100, 100));
      expect(docAfter.layerById('cc')!.transform.position,
          cc.transform.position + const Offset(100, 100));

      c.read(documentControllerProvider.notifier).undo();
      final docUndone = c.read(documentControllerProvider);
      expect(
          docUndone.layerById('a')!.transform.position, a.transform.position);
      expect(
          docUndone.layerById('b')!.transform.position, b.transform.position);
      expect(docUndone.layerById('cc')!.transform.position,
          cc.transform.position);
    });

    test('locked layers are dropped from the eligible set', () {
      final c = makeContainer();
      addRect(c, id: 'a', position: const Offset(100, 100));
      addRect(c, id: 'b', position: const Offset(300, 100));
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!;
      final bLocked = doc.layerById('b')!.withLocked(true);

      c.read(interactionControllerProvider.notifier).startGroupMove(
            layers: [a, bLocked],
            pointer: const Offset(140, 140),
          );

      final state = c.read(interactionControllerProvider);
      expect(state.groupSession?.initials.keys.toSet(), {'a'});
    });

    test('cancel mid-drag commits nothing for ANY layer', () {
      final c = makeContainer();
      addRect(c, id: 'a', position: const Offset(100, 100));
      addRect(c, id: 'b', position: const Offset(300, 100));
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!;
      final b = doc.layerById('b')!;

      c.read(interactionControllerProvider.notifier).startGroupMove(
            layers: [a, b],
            pointer: const Offset(0, 0),
          );
      c.read(interactionControllerProvider.notifier).updateGroup(
            const Offset(100, 100),
          );
      c.read(interactionControllerProvider.notifier).cancel();

      final docAfter = c.read(documentControllerProvider);
      expect(docAfter.layerById('a')!.transform.position, a.transform.position);
      expect(docAfter.layerById('b')!.transform.position, b.transform.position);
      expect(c.read(interactionControllerProvider).isActive, isFalse);
    });
  });

  group('group resize', () {
    test('uniform scale 2x from bottom-right anchor doubles bounds', () {
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!;
      final b = doc.layerById('b')!;

      // Bounds = (0,0,300,100). Drag top-left from (0,0) to
      // (-300,-100). Anchor = bottom-right (300,100). The pointer's
      // signed projection on anchor→corner diagonal == 2 → uniform
      // scale 2.0 around (300,100).
      c.read(interactionControllerProvider.notifier).startGroupResize(
            layers: [a, b],
            handle: InteractionHandle.topLeft,
            pointer: const Offset(0, 0),
          );
      c.read(interactionControllerProvider.notifier).updateGroup(
            const Offset(-300, -100),
          );
      c.read(interactionControllerProvider.notifier).end();

      final docAfter = c.read(documentControllerProvider);
      final aAfter = docAfter.layerById('a')!.transform;
      final bAfter = docAfter.layerById('b')!.transform;

      expect(aAfter.size, const Size(200, 200));
      expect(bAfter.size, const Size(200, 200));
      // a centre (50,50)  scaled 2x from (300,100): 300 + (50-300)*2 = -200,
      //                                            100 + (50-100)*2 =    0
      //   → centre (-200,0) → top-left (-300,-100)
      expect(aAfter.position.dx, closeTo(-300, 1e-6));
      expect(aAfter.position.dy, closeTo(-100, 1e-6));
      // b centre (250,50) → 300 + (250-300)*2 = 200, 0 → centre (200,0)
      //   → top-left (100,-100)
      expect(bAfter.position.dx, closeTo(100, 1e-6));
      expect(bAfter.position.dy, closeTo(-100, 1e-6));
    });
  });

  group('group rotate', () {
    test('rotates every layer 90° around the group centre', () {
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!;
      final b = doc.layerById('b')!;

      // Bounds (0,0,300,100), centre = (150,50).
      // pointerStart at (250,50): angle 0 around centre.
      // pointerEnd at (150,150): angle π/2 → delta π/2.
      c.read(interactionControllerProvider.notifier).startGroupRotate(
            layers: [a, b],
            pointer: const Offset(250, 50),
          );
      c.read(interactionControllerProvider.notifier).updateGroup(
            const Offset(150, 150),
          );
      c.read(interactionControllerProvider.notifier).end();

      final docAfter = c.read(documentControllerProvider);
      final aAfter = docAfter.layerById('a')!.transform;
      final bAfter = docAfter.layerById('b')!.transform;

      expect(aAfter.rotation, closeTo(1.5707963, 1e-6));
      expect(bAfter.rotation, closeTo(1.5707963, 1e-6));
      // a centre (50,50) rotated 90° around (150,50) → (150,-50)
      // b centre (250,50) rotated 90° around (150,50) → (150,150)
      expect(aAfter.center.dx, closeTo(150, 1e-6));
      expect(aAfter.center.dy, closeTo(-50, 1e-6));
      expect(bAfter.center.dx, closeTo(150, 1e-6));
      expect(bAfter.center.dy, closeTo(150, 1e-6));
    });
  });

  group('group gesture (pinch)', () {
    test('pure scale=2 around bounds centre doubles each layer', () {
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!;
      final b = doc.layerById('b')!;

      // Start at the bounds centre (150,50). The first updateGroupGesture
      // with pointerCount>=2 rebases pointerStart to focalPoint, so we
      // pass the same focal again.
      c.read(interactionControllerProvider.notifier).startGroupGesture(
            layers: [a, b],
            focalPoint: const Offset(150, 50),
          );
      c.read(interactionControllerProvider.notifier).updateGroupGesture(
            focalPoint: const Offset(150, 50),
            scale: 2.0,
            rotation: 0.0,
            pointerCount: 2,
          );
      c.read(interactionControllerProvider.notifier).end();

      final docAfter = c.read(documentControllerProvider);
      final aAfter = docAfter.layerById('a')!.transform;
      final bAfter = docAfter.layerById('b')!.transform;
      expect(aAfter.size, const Size(200, 200));
      expect(bAfter.size, const Size(200, 200));
      // a centre (50,50) scaled 2x from (150,50): 150 + (50-150)*2 = -50, 50
      //   → centre (-50,50) → top-left (-150,-50)
      expect(aAfter.position.dx, closeTo(-150, 1e-6));
      expect(aAfter.position.dy, closeTo(-50, 1e-6));
    });
  });

  group('hardening', () {
    test('group resize cannot flip layers (factor clamped positive)', () {
      // Drag the top-left corner *through* the bottom-right anchor.
      // Without the positive-factor clamp the layers would mirror.
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!;
      final b = doc.layerById('b')!;

      c.read(interactionControllerProvider.notifier).startGroupResize(
            layers: [a, b],
            handle: InteractionHandle.topLeft,
            pointer: const Offset(0, 0),
          );
      // Drag pointer well past bottom-right anchor (300,100) → would be
      // negative factor without the clamp.
      c.read(interactionControllerProvider.notifier).updateGroup(
            const Offset(900, 300),
          );
      c.read(interactionControllerProvider.notifier).end();

      final docAfter = c.read(documentControllerProvider);
      final aAfter = docAfter.layerById('a')!.transform;
      // Sizes must remain positive — no mirroring.
      expect(aAfter.size.width, greaterThan(0));
      expect(aAfter.size.height, greaterThan(0));
    });

    test('group resize never shrinks any layer below minLayerSize', () {
      // Mixed-size group; resize down hard. Smallest layer must be >= 24.
      final c = makeContainer();
      addRect(c, id: 'small',
          position: const Offset(0, 0), size: const Size(40, 40));
      addRect(c, id: 'big',
          position: const Offset(100, 0), size: const Size(400, 400));
      final doc = c.read(documentControllerProvider);
      final small = doc.layerById('small')!;
      final big = doc.layerById('big')!;

      c.read(interactionControllerProvider.notifier).startGroupResize(
            layers: [small, big],
            handle: InteractionHandle.topLeft,
            pointer: const Offset(0, 0),
          );
      // Drag corner almost to anchor → tiny scale factor.
      final bounds = c.read(interactionControllerProvider).groupLiveBounds!;
      c.read(interactionControllerProvider.notifier).updateGroup(
            bounds.bottomRight - const Offset(1, 1),
          );
      c.read(interactionControllerProvider.notifier).end();

      final docAfter = c.read(documentControllerProvider);
      final smallAfter = docAfter.layerById('small')!.transform;
      // Min side enforced at engine floor (24).
      expect(smallAfter.size.width, greaterThanOrEqualTo(24));
      expect(smallAfter.size.height, greaterThanOrEqualTo(24));
    });

    test('group rotate handles ±π branch cut without 2π jump', () {
      // Start the rotate just below the +x axis and end just above.
      // Raw subtraction would give a delta near 2π; shortest-arc keeps
      // the visible rotation tiny.
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!;
      final b = doc.layerById('b')!;

      // Centre = (150,50). Pointer just below -x axis: angle ≈ -π+ε.
      c.read(interactionControllerProvider.notifier).startGroupRotate(
            layers: [a, b],
            pointer: const Offset(50, 49.99),
          );
      // Pointer just above -x axis: angle ≈ +π-ε. Naive delta ≈ 2π.
      c.read(interactionControllerProvider.notifier).updateGroup(
            const Offset(50, 50.01),
          );
      // The shortest-arc delta must be tiny, not a full turn.
      final live = c.read(interactionControllerProvider).groupLive['a']!;
      expect(live.rotation.abs(), lessThan(0.01));
    });

    test('groupLiveBounds is cached \u2014 same identity across reads', () {
      // Ensures the getter is no longer recomputing on every access.
      final c = makeContainer();
      addRect(c, id: 'a', position: const Offset(0, 0));
      addRect(c, id: 'b', position: const Offset(200, 0));
      final doc = c.read(documentControllerProvider);
      c.read(interactionControllerProvider.notifier).startGroupMove(
            layers: [doc.layerById('a')!, doc.layerById('b')!],
            pointer: Offset.zero,
          );
      final s = c.read(interactionControllerProvider);
      final r1 = s.groupLiveBounds;
      final r2 = s.groupLiveBounds;
      expect(identical(r1, r2), isTrue);
    });
  });

  group('group drag snap (gesture-session path \u2014 the real UI route)', () {
    test(
        'single-finger drag on a group session snaps the AABB to a peer '
        'and publishes alignment guides', () {
      // The multi-select overlay routes body drags through
      // `startGroupGesture` / `updateGroupGesture` (NOT the dedicated
      // `startGroupMove` / `updateGroup` path). For a long time this
      // meant group drag had zero snap in production. This test
      // guards the gesture-session translate branch.
      final c = makeContainer();
      // Two group members, AABB right edge ends at x=380.
      addRect(c, id: 'a',
          position: const Offset(100, 200), size: const Size(80, 80));
      addRect(c, id: 'b',
          position: const Offset(300, 200), size: const Size(80, 80));
      // Stationary peer whose left edge sits at x=500 \u2014 our snap
      // target.
      addRect(c, id: 'peer',
          position: const Offset(500, 400), size: const Size(80, 80));
      final doc = c.read(documentControllerProvider);
      final ctl = c.read(interactionControllerProvider.notifier);

      ctl.startGroupGesture(
        layers: [doc.layerById('a')!, doc.layerById('b')!],
        focalPoint: const Offset(190, 240),
      );
      // Drive one frame as a single-finger drag (pointerCount=1).
      // Move the focal so the AABB right edge lands at x=503 \u2014
      // 3 px from the peer's left edge, well inside the 6 px snap.
      ctl.updateGroupGesture(
        focalPoint: const Offset(313, 240),
        scale: 1.0,
        rotation: 0,
        pointerCount: 1,
      );

      final s = c.read(interactionControllerProvider);
      expect(s.snapGuides, isNotEmpty,
          reason: 'group single-finger drag must publish alignment '
              'guides when the AABB lands inside the snap threshold');
      // The 'a' layer originally at x=100 should have been pulled
      // back so the AABB right edge sits exactly on x=500. AABB
      // width is 280 (b.right - a.left = 380 - 100), so a.left =
      // 500 - 280 = 220.
      expect(s.groupLive['a']!.position.dx, closeTo(220, 0.01));
    });

    test(
        'two-finger pinch on a group session does NOT publish snap '
        'guides (raw direct manipulation)', () {
      // Mobile-editor norm: pinch is freeform, no snapping. Verifies
      // we did not over-reach when adding single-finger snap.
      final c = makeContainer();
      addRect(c, id: 'a', position: const Offset(100, 200));
      addRect(c, id: 'b', position: const Offset(300, 200));
      addRect(c, id: 'peer', position: const Offset(500, 400));
      final doc = c.read(documentControllerProvider);
      final ctl = c.read(interactionControllerProvider.notifier);

      ctl.startGroupGesture(
        layers: [doc.layerById('a')!, doc.layerById('b')!],
        focalPoint: const Offset(190, 240),
      );
      ctl.updateGroupGesture(
        focalPoint: const Offset(190, 240),
        scale: 1.5,
        rotation: 0,
        pointerCount: 2,
      );

      final s = c.read(interactionControllerProvider);
      expect(s.snapGuides, isEmpty);
      expect(s.spacingGuides, isEmpty);
    });
  });

  group('group selection frame (rotated chrome)', () {
    test(
        'rotate handle drag publishes a quad whose corners are '
        'rotated around the bounds centre — chrome can paint a '
        'rotated frame', () {
      // Two unit squares at (0..100, 0..100) and (200..300, 0..100).
      // AABB is (0,0,300,100), centre (150, 50).
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);

      // Start at the right-edge midpoint so pointerStartAngle = 0.
      const start = Offset(300, 50);
      c.read(interactionControllerProvider.notifier).startGroupRotate(
            layers: [doc.layerById('a')!, doc.layerById('b')!],
            pointer: start,
          );
      // Drive ~90° rotation: pointer to (150, 200) is +pi/2 from
      // centre (150, 50).
      c.read(interactionControllerProvider.notifier).updateGroup(
            const Offset(150, 200),
          );

      final s = c.read(interactionControllerProvider);
      expect(s.groupLiveQuad, isNotNull,
          reason: 'rotate handle must publish an oriented frame quad');
      final q = s.groupLiveQuad!;
      expect(q, hasLength(4));
      // Original TL (0,0) rotated +90° around (150,50):
      //   relative (-150, -50) -> rotated (50, -150) -> abs (200, -100).
      expect(q[0].dx, closeTo(200, 0.5));
      expect(q[0].dy, closeTo(-100, 0.5));
      // Original TR (300,0) -> relative (150,-50) -> rotated (50,150)
      //   -> abs (200, 200).
      expect(q[1].dx, closeTo(200, 0.5));
      expect(q[1].dy, closeTo(200, 0.5));
    });

    test(
        'translate-only gesture publishes an axis-aligned quad '
        '(no rotation, just translated AABB corners)', () {
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);

      final ctl = c.read(interactionControllerProvider.notifier);
      ctl.startGroupGesture(
        layers: [doc.layerById('a')!, doc.layerById('b')!],
        focalPoint: const Offset(150, 50),
      );
      // Single-finger drag by (40, 30). No peer to snap against.
      ctl.updateGroupGesture(
        focalPoint: const Offset(190, 80),
        scale: 1.0,
        rotation: 0,
        pointerCount: 1,
      );

      final s = c.read(interactionControllerProvider);
      expect(s.groupLiveQuad, isNotNull);
      final q = s.groupLiveQuad!;
      // AABB (0,0,300,100) translated by (40,30) =>
      //   TL (40,30), TR (340,30), BR (340,130), BL (40,130).
      expect(q[0], const Offset(40, 30));
      expect(q[1], const Offset(340, 30));
      expect(q[2], const Offset(340, 130));
      expect(q[3], const Offset(40, 130));
    });

    test(
        'pinch with rotation publishes a quad rotated by the same '
        'angle as the gesture', () {
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);

      final ctl = c.read(interactionControllerProvider.notifier);
      ctl.startGroupGesture(
        layers: [doc.layerById('a')!, doc.layerById('b')!],
        focalPoint: const Offset(150, 50),
      );
      // First go to 2-finger to enter the pinch branch (rebases).
      ctl.updateGroupGesture(
        focalPoint: const Offset(150, 50),
        scale: 1.0,
        rotation: 0,
        pointerCount: 2,
      );
      // Now actually rotate by +90° with the same focal (no
      // translation, no scale change).
      ctl.updateGroupGesture(
        focalPoint: const Offset(150, 50),
        scale: 1.0,
        rotation: math.pi / 2,
        pointerCount: 2,
      );

      final s = c.read(interactionControllerProvider);
      expect(s.groupLiveQuad, isNotNull);
      final q = s.groupLiveQuad!;
      // After the pc=2 rebase, the new initialBounds is the live
      // AABB (still (0,0,300,100), centre (150,50)). Same expected
      // corners as the rotate-handle test above.
      expect(q[0].dx, closeTo(200, 0.5));
      expect(q[0].dy, closeTo(-100, 0.5));
      expect(q[1].dx, closeTo(200, 0.5));
      expect(q[1].dy, closeTo(200, 0.5));
    });
  });

  group('commit hardening', () {
    test(
        'pinch session with 1\u21922\u21921\u21922 pointer oscillation '
        'commits scaled transforms on release (no snap-back)', () {
      // Simulates a user who briefly lifts a finger mid-pinch then
      // re-plants it. Every pointer-count transition rebases the
      // session's `initials`. If the commit path diffs against
      // `initials` it would always match the final live state and
      // skip the commit. Diffing against the document (which never
      // moved during the gesture) must still detect the change.
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);

      final ctrl = c.read(interactionControllerProvider.notifier);
      ctrl.startGroupGesture(
        layers: [doc.layerById('a')!, doc.layerById('b')!],
        focalPoint: const Offset(150, 50),
      );
      // pc=2: first real update, first rebase (firstUpdate && pc\u22652).
      ctrl.updateGroupGesture(
          focalPoint: const Offset(150, 50),
          scale: 1.5,
          rotation: 0,
          pointerCount: 2);
      // pc=1: rebase (snapshots scaled live into initials).
      ctrl.updateGroupGesture(
          focalPoint: const Offset(150, 50),
          scale: 1,
          rotation: 0,
          pointerCount: 1);
      // pc=2 again: rebase.
      ctrl.updateGroupGesture(
          focalPoint: const Offset(150, 50),
          scale: 2.0,
          rotation: 0,
          pointerCount: 2);
      // Final pc=1 frame.
      ctrl.updateGroupGesture(
          focalPoint: const Offset(150, 50),
          scale: 1,
          rotation: 0,
          pointerCount: 1);
      ctrl.end();

      final docAfter = c.read(documentControllerProvider);
      expect(docAfter.layerById('a')!.transform.size.width, greaterThan(100),
          reason: 'Oscillating pointer counts must not prevent the '
              'scaled transform from being committed.');
    });

    test('group rotate commits the rotation on release', () {
      final c = makeContainer();
      addRect(c, id: 'a', position: const Offset(0, 0));
      addRect(c, id: 'b', position: const Offset(200, 0));
      final doc = c.read(documentControllerProvider);

      c.read(interactionControllerProvider.notifier).startGroupRotate(
            layers: [doc.layerById('a')!, doc.layerById('b')!],
            pointer: const Offset(280, 40),
          );
      c.read(interactionControllerProvider.notifier).updateGroup(
            const Offset(140, 180),
          );
      c.read(interactionControllerProvider.notifier).end();

      final docAfter = c.read(documentControllerProvider);
      expect(docAfter.layerById('a')!.transform.rotation, isNot(0));
      expect(docAfter.layerById('b')!.transform.rotation, isNot(0));
    });

    test('gesture that returns to origin pushes NO history entry', () {
      // A pinch that ends exactly where it began must not grow the
      // undo stack — nothing visible changed.
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);
      final undoBefore =
          c.read(documentControllerProvider.notifier).canUndo;

      final ctrl = c.read(interactionControllerProvider.notifier);
      ctrl.startGroupGesture(
        layers: [doc.layerById('a')!, doc.layerById('b')!],
        focalPoint: const Offset(150, 50),
      );
      ctrl.updateGroupGesture(
          focalPoint: const Offset(150, 50),
          scale: 1.0,
          rotation: 0,
          pointerCount: 2);
      ctrl.end();

      expect(c.read(documentControllerProvider.notifier).canUndo,
          undoBefore,
          reason: 'A gesture that did not actually change any layer '
              'must not push a redundant history entry.');
    });

    test('undo mid-drag cancels the active group session cleanly', () {
      // External mutation of a participant's transform (here via
      // undo) must abort the gesture so the pending release does
      // not overwrite the undone state.
      final c = makeContainer();
      addRect(c, id: 'a',
          position: const Offset(0, 0), size: const Size(100, 100));
      addRect(c, id: 'b',
          position: const Offset(200, 0), size: const Size(100, 100));
      final doc = c.read(documentControllerProvider);
      // Seed a history entry so undo has something to do.
      c.read(documentControllerProvider.notifier).execute(
            SetLayerTransformCommand(
              layerId: 'a',
              transform: doc.layerById('a')!.transform.copyWith(
                    position: const Offset(10, 0),
                  ),
            ),
          );
      final docAfterSeed = c.read(documentControllerProvider);
      final aSeeded = docAfterSeed.layerById('a')!;
      final bSeeded = docAfterSeed.layerById('b')!;

      final ctrl = c.read(interactionControllerProvider.notifier);
      ctrl.startGroupMove(
        layers: [aSeeded, bSeeded],
        pointer: Offset.zero,
      );
      ctrl.updateGroup(const Offset(50, 0));
      expect(c.read(interactionControllerProvider).isActive, isTrue);

      // Drive-by undo lands mid-drag.
      c.read(documentControllerProvider.notifier).undo();

      expect(c.read(interactionControllerProvider).isActive, isFalse,
          reason: 'An external transform change must cancel the '
              'active gesture to prevent the release from overwriting '
              'the new document state.');
    });
  });
}
