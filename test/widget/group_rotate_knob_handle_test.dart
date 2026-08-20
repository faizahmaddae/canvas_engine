import 'dart:math' as math;

import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/interaction_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The GROUP frame's handle grammar (ux-audit P3-9): the tb3 6/7
/// single-layer redesign (four resize corners + a dedicated stemmed
/// rotation knob) now applies to multi-selections too. Before this,
/// the group's top-right corner ROTATED where the single frame's
/// resizes — muscle memory from single-layer editing rotated the
/// group when the user meant to resize.
///
///   * every group corner — including top-right — starts a group
///     RESIZE (uniform scale; bounds grow, rotations untouched);
///   * the stemmed knob above the top-centre rotates the group;
///   * grabbing near the knob / its stem claims the group body,
///     never the viewport (the group chrome-quad claim includes the
///     stem capsule, mirroring the single-layer rule).
///
/// Group geography in every test: 'a' (380,380) 40×40 and
/// 'b' (450,380) 40×40 → shared AABB (380,380)→(490,420), centre
/// (435,400), top-edge midpoint (435,380).

ProviderContainer _setup(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);

  container
      .read(documentControllerProvider.notifier)
      .newDocument(width: 800, height: 800);
  container
      .read(documentControllerProvider.notifier)
      .execute(
        AddLayerCommand(
          ShapeLayer(
            id: 'a',
            transform: const LayerTransform(
              position: Offset(380, 380),
              size: Size(40, 40),
            ),
            kind: ShapeKind.rectangle,
          ),
        ),
      );
  container
      .read(documentControllerProvider.notifier)
      .execute(
        AddLayerCommand(
          ShapeLayer(
            id: 'b',
            transform: const LayerTransform(
              position: Offset(450, 380),
              size: Size(40, 40),
            ),
            kind: ShapeKind.rectangle,
          ),
        ),
      );
  container.read(selectionModeProvider.notifier).enterMulti();
  container.read(selectionControllerProvider.notifier).selectMany(['a', 'b']);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Offset _toScreen(ProviderContainer c, Offset canvas) {
  final vp = c.read(viewportControllerProvider);
  return canvas * vp.scale + vp.translation;
}

/// Screen-space centre of the group's rotation knob: the OUTSET
/// frame's top-edge midpoint pushed [EngineConstants.rotateHandleOffset]
/// further up. Both offsets are screen-dp, exactly as the overlay
/// draws them.
Offset _knobCentre(ProviderContainer c) {
  final topMid = _toScreen(c, const Offset(435, 380));
  return Offset(
    topMid.dx,
    topMid.dy -
        EngineConstants.selectionOutset -
        EngineConstants.rotateHandleOffset,
  );
}

void main() {
  testWidgets('all four group corners resize — none rotates', (tester) async {
    // Outward drag per corner, along its diagonal (away from the
    // anchor at the opposite corner).
    const cases =
        <(InteractionHandle handle, Offset corner, Offset sign, Offset drag)>[
          (
            InteractionHandle.topLeft,
            Offset(380, 380),
            Offset(-1, -1),
            Offset(-60, -40),
          ),
          (
            InteractionHandle.topRight,
            Offset(490, 380),
            Offset(1, -1),
            Offset(60, -40),
          ),
          (
            InteractionHandle.bottomLeft,
            Offset(380, 420),
            Offset(-1, 1),
            Offset(-60, 40),
          ),
          (
            InteractionHandle.bottomRight,
            Offset(490, 420),
            Offset(1, 1),
            Offset(60, 40),
          ),
        ];
    const o = EngineConstants.selectionOutset;

    for (final (handle, corner, sign, drag) in cases) {
      final c = _setup(tester);
      await _pump(tester, c);

      final aBefore = c
          .read(documentControllerProvider)
          .layerById('a')!
          .transform;

      final handleScreen =
          _toScreen(c, corner) + Offset(sign.dx * o, sign.dy * o);
      final gesture = await tester.startGesture(handleScreen);
      await tester.pump();
      await gesture.moveBy(drag);
      await tester.pump();

      final session = c.read(interactionControllerProvider).groupSession;
      expect(
        session,
        isNotNull,
        reason: 'corner at $corner must start a group session',
      );
      expect(
        session!.handle,
        handle,
        reason:
            'every corner starts a group RESIZE from its own handle — '
            'rotate lives on the knob',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump();

      final after = c
          .read(documentControllerProvider)
          .layerById('a')!
          .transform;
      expect(
        after.size.width,
        greaterThan(aBefore.size.width),
        reason: 'outward drag from $corner must grow the group members',
      );
      expect(
        after.rotation,
        0,
        reason: 'a corner drag must never rotate the group',
      );

      await tester.pump(const Duration(milliseconds: 800));
    }
  });

  testWidgets('ux-audit P3-9 regression: the top-right corner RESIZES the '
      'group — bounds grow, rotation unchanged', (tester) async {
    final c = _setup(tester);
    await _pump(tester, c);

    Rect groupAabb() {
      final doc = c.read(documentControllerProvider);
      final a = doc.layerById('a')!.transform;
      final b = doc.layerById('b')!.transform;
      return (a.position & a.size).expandToInclude(b.position & b.size);
    }

    final boundsBefore = groupAabb();

    const o = EngineConstants.selectionOutset;
    final topRight = _toScreen(c, const Offset(490, 380)) + const Offset(o, -o);
    final gesture = await tester.startGesture(topRight);
    await tester.pump();
    // Outward along the top-right diagonal — the muscle-memory
    // "make it bigger" drag that used to spin the group instead.
    await gesture.moveBy(const Offset(60, -40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, -40));
    await tester.pump();

    final session = c.read(interactionControllerProvider).groupSession;
    expect(session, isNotNull);
    expect(
      session!.handle,
      InteractionHandle.topRight,
      reason: 'top-right must be a resize corner, not the rotate handle',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump();

    final boundsAfter = groupAabb();
    expect(
      boundsAfter.width,
      greaterThan(boundsBefore.width),
      reason: 'the outward top-right drag must GROW the group bounds',
    );
    expect(boundsAfter.height, greaterThan(boundsBefore.height));
    for (final id in ['a', 'b']) {
      expect(
        c.read(documentControllerProvider).layerById(id)!.transform.rotation,
        0,
        reason: 'member $id must not rotate on a corner drag',
      );
    }

    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('the stemmed knob rotates the group and commits', (tester) async {
    final c = _setup(tester);
    await _pump(tester, c);

    final knob = _knobCentre(c);
    final centre = _toScreen(c, const Offset(435, 400));
    final radius = (knob - centre).distance;

    final gesture = await tester.startGesture(knob);
    await tester.pump();
    expect(
      c.read(interactionControllerProvider).groupSession?.handle,
      InteractionHandle.rotate,
      reason: 'the knob must start a group-rotate session on pointer-down',
    );

    // Swing the pointer from 12 o'clock to 3 o'clock (+90°). Group
    // rotate snaps the raw gesture DELTA (no smoother on this path),
    // so the live and committed angles are deterministic.
    await gesture.moveTo(centre + Offset(radius, 0));
    await tester.pump();

    final live = c.read(interactionControllerProvider).groupLive['a'];
    expect(live, isNotNull);
    expect(live!.rotation, closeTo(math.pi / 2, 1e-6));
    expect(
      c.read(interactionControllerProvider).isRotationSnapped,
      isTrue,
      reason: '90° sits inside the cardinal soft-snap zone',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump();

    for (final id in ['a', 'b']) {
      expect(
        c.read(documentControllerProvider).layerById(id)!.transform.rotation,
        closeTo(math.pi / 2, 1e-6),
        reason: 'member $id must carry the committed group rotation',
      );
    }
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('a grab on the stem capsule (outside the knob box) claims the '
      'group, never the viewport', (tester) async {
    final c = _setup(tester);
    await _pump(tester, c);

    final viewportBefore = c.read(viewportControllerProvider);
    final topMid = _toScreen(c, const Offset(435, 380));
    final frameTopY = topMid.dy - EngineConstants.selectionOutset;
    // 12dp beside the stem, 1dp above the frame edge: outside the
    // inflated bounds, outside the knob's 48dp box (which ends 4dp
    // above the frame edge), inside the stem capsule.
    final probe = Offset(topMid.dx + 12, frameTopY - 1);

    final gesture = await tester.startGesture(probe);
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();

    expect(
      c.read(interactionControllerProvider).groupSession,
      isNotNull,
      reason: 'the stem capsule is part of the group chrome-quad claim',
    );
    expect(
      c.read(viewportControllerProvider).translation,
      viewportBefore.translation,
      reason: 'a near-knob grab must never fall through to viewport pan',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });
}
