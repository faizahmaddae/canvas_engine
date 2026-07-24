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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;

/// The tb3 6/7 handle set (decision D-a): FOUR resize corners and a
/// dedicated, stemmed rotation knob above the selection's top-centre.
///
///   * every corner — including the restored top-right — resizes;
///   * the knob rotates, with the soft-snap + haptic seam intact
///     (rotation math is position-agnostic);
///   * grabbing the knob or its stem never falls through to viewport
///     pan (the 3.1 chrome-quad claim includes the stem capsule).

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
            id: 'shape',
            transform: const LayerTransform(
              position: Offset(370, 370),
              size: Size(60, 60),
            ),
            kind: ShapeKind.rectangle,
          ),
        ),
      );
  container.read(selectionControllerProvider.notifier).select('shape');
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

void main() {
  testWidgets('all four corners resize the layer (top-right restored)', (
    tester,
  ) async {
    // Outward drag direction per corner, along its diagonal.
    const cases = <(Offset corner, Offset outsetSign, Offset drag)>[
      (Offset(370, 370), Offset(-1, -1), Offset(-40, -40)), // topLeft
      (Offset(430, 370), Offset(1, -1), Offset(40, -40)), // topRight
      (Offset(370, 430), Offset(-1, 1), Offset(-40, 40)), // bottomLeft
      (Offset(430, 430), Offset(1, 1), Offset(40, 40)), // bottomRight
    ];
    const o = EngineConstants.selectionOutset;

    for (final (corner, sign, drag) in cases) {
      final c = _setup(tester);
      await _pump(tester, c);

      final handleScreen =
          _toScreen(c, corner) + Offset(sign.dx * o, sign.dy * o);
      final gesture = await tester.startGesture(handleScreen);
      await tester.pump();
      await gesture.moveBy(drag);
      await tester.pump();

      final session = c.read(interactionControllerProvider).session;
      expect(
        session,
        isNotNull,
        reason: 'corner at $corner must start a resize session',
      );
      expect(
        session!.handle,
        isNot(InteractionHandle.rotate),
        reason: 'every corner resizes now — rotate lives on the knob',
      );

      await gesture.up();
      await tester.pump();

      final after = c
          .read(documentControllerProvider)
          .layerById('shape')!
          .transform;
      expect(
        after.size.width,
        greaterThan(60),
        reason: 'outward drag from $corner must grow the layer',
      );
      expect(after.size.height, greaterThan(60));

      await tester.pump(const Duration(milliseconds: 800));
    }
  });

  testWidgets('the stemmed knob rotates the layer and commits', (tester) async {
    final c = _setup(tester);
    await _pump(tester, c);

    // Knob centre in screen space: top-edge midpoint of the OUTSET
    // frame, pushed rotateHandleOffset further up (screen-dp).
    final topEdgeY =
        _toScreen(c, const Offset(400, 370)).dy -
        EngineConstants.selectionOutset;
    final knob = Offset(
      _toScreen(c, const Offset(400, 370)).dx,
      topEdgeY - EngineConstants.rotateHandleOffset,
    );
    final centre = _toScreen(c, const Offset(400, 400));
    final radius = (knob - centre).distance;

    final gesture = await tester.startGesture(knob);
    await tester.pump();
    expect(
      c.read(interactionControllerProvider).session?.handle,
      InteractionHandle.rotate,
      reason: 'the knob must start a rotate session on pointer-down',
    );

    // Swing the pointer from 12 o\'clock to 3 o\'clock (+90°).
    await gesture.moveTo(centre + Offset(radius, 0));
    await tester.pump();

    final live = c.read(interactionControllerProvider).liveTransform;
    expect(live, isNotNull);
    // The live transform runs through the time-based smoother (whose
    // Stopwatch reads wall-clock time and so lags under tester.pump);
    // assert direction + magnitude, not the exact settled angle.
    expect(
      live!.rotation,
      greaterThan(0.05),
      reason:
          'rotation is a pure pointer-angle delta about the centre '
          '(the smoother lags under fake time, so only direction and '
          'movement are asserted; the snap check below pins the RAW '
          'angle deterministically)',
    );
    expect(
      c.read(interactionControllerProvider).isRotationSnapped,
      isTrue,
      reason:
          '90° sits inside the cardinal soft-snap zone (snap reads the '
          'RAW pointer angle, not the smoothed transform)',
    );

    await gesture.up();
    await tester.pump();
    final committed = c
        .read(documentControllerProvider)
        .layerById('shape')!
        .transform;
    expect(committed.rotation, isNot(0));
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('entering the snap zone from the knob fires the haptic seam', (
    tester,
  ) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final c = _setup(tester);
    await _pump(tester, c);

    final topEdgeY =
        _toScreen(c, const Offset(400, 370)).dy -
        EngineConstants.selectionOutset;
    final knob = Offset(
      _toScreen(c, const Offset(400, 370)).dx,
      topEdgeY - EngineConstants.rotateHandleOffset,
    );
    final centre = _toScreen(c, const Offset(400, 400));
    final radius = (knob - centre).distance;

    final gesture = await tester.startGesture(knob);
    await tester.pump();
    // Park at +20° rotation first — outside every snap zone (targets
    // sit at 45° multiples with a 4–6° magnet), so the snap edge is
    // clean when we then swing into the 90° cardinal zone.
    await gesture.moveTo(
      centre +
          Offset(
            radius * math.cos(-70 * math.pi / 180),
            radius * math.sin(-70 * math.pi / 180),
          ),
    );
    await tester.pump();
    haptics.clear();
    await gesture.moveTo(centre + Offset(radius, 0));
    await tester.pump();

    expect(c.read(interactionControllerProvider).isRotationSnapped, isTrue);
    expect(
      haptics,
      isNotEmpty,
      reason: 'entering the snap zone must fire the selection-click haptic',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('a grab on the stem capsule (outside the knob box) claims the '
      'layer, never the viewport', (tester) async {
    final c = _setup(tester);
    await _pump(tester, c);

    final viewportBefore = c.read(viewportControllerProvider);
    final topMidX = _toScreen(c, const Offset(400, 370)).dx;
    final frameTopY =
        _toScreen(c, const Offset(400, 370)).dy -
        EngineConstants.selectionOutset;
    // 12dp beside the stem, 1dp above the frame edge: outside the
    // chrome quad, outside the knob's 48dp box (which ends 10dp
    // higher), inside the stem capsule.
    final probe = Offset(topMidX + 12, frameTopY - 1);

    final gesture = await tester.startGesture(probe);
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();

    final session = c.read(interactionControllerProvider).session;
    expect(
      session,
      isNotNull,
      reason: 'the stem capsule is part of the chrome-quad claim',
    );
    expect(session!.layerId, 'shape');
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
