import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/interaction_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: "select multiple objects and scale them — on release,
/// they immediately reset back to where they were."
///
/// Drives the real widget tree (EditorCanvas + GroupSelectionOverlay)
/// with a two-finger pinch starting outside the group, then releases
/// and asserts the document transform is committed (NOT reverted).

ProviderContainer _setup(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpEditorWithGroup(
  WidgetTester tester,
  ProviderContainer container,
) async {
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

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('two-finger pinch on a group commits the scaled transforms to '
      'the document on release (no revert)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithGroup(tester, container);

    final aBefore = container
        .read(documentControllerProvider)
        .layerById('a')!
        .transform;
    final bBefore = container
        .read(documentControllerProvider)
        .layerById('b')!
        .transform;

    final vp = container.read(viewportControllerProvider);
    Offset toScreen(Offset c) => c * vp.scale + vp.translation;
    final centre = toScreen(const Offset(435, 400));
    final p1 = centre + const Offset(-220, 0);
    final p2 = centre + const Offset(220, 0);

    final f1 = await tester.startGesture(p1, pointer: 51);
    await tester.pump();
    final f2 = await tester.startGesture(p2, pointer: 52);
    await tester.pump();

    // Pinch out — fingers move 100px away from each other each side.
    await f1.moveBy(const Offset(-100, 0));
    await f2.moveBy(const Offset(100, 0));
    await tester.pump();
    await f1.moveBy(const Offset(-100, 0));
    await f2.moveBy(const Offset(100, 0));
    await tester.pump();

    // Confirm live preview is applied.
    final liveA = container.read(interactionControllerProvider).groupLive['a']!;
    expect(liveA.size.width, greaterThan(aBefore.size.width));

    await f1.up();
    await f2.up();
    await tester.pump();
    await tester.pump();

    // The bug: after release, document reverts to initial sizes.
    final aAfter = container
        .read(documentControllerProvider)
        .layerById('a')!
        .transform;
    final bAfter = container
        .read(documentControllerProvider)
        .layerById('b')!
        .transform;
    expect(
      aAfter.size.width,
      greaterThan(aBefore.size.width),
      reason: 'Layer a must retain its scaled size after release.',
    );
    expect(
      bAfter.size.width,
      greaterThan(bBefore.size.width),
      reason: 'Layer b must retain its scaled size after release.',
    );
    // Drain any lingering double-tap timer so the test shutdown
    // assertion `!timersPending` holds.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('drag on the bottom-right corner handle commits the scaled '
      'transforms to the document on release (no revert)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithGroup(tester, container);

    final aBefore = container
        .read(documentControllerProvider)
        .layerById('a')!
        .transform;
    final bBefore = container
        .read(documentControllerProvider)
        .layerById('b')!
        .transform;

    final vp = container.read(viewportControllerProvider);
    Offset toScreen(Offset c) => c * vp.scale + vp.translation;
    // Group bounds: (380,380)→(490,420). Bottom-right handle at
    // screen-space (490,420) transformed.
    final brHandle = toScreen(const Offset(490, 420));

    final g = await tester.startGesture(brHandle);
    await tester.pump();
    // Drag outward along the diagonal — pointer moves to scale up.
    await g.moveBy(const Offset(60, 40));
    await tester.pump();
    await g.moveBy(const Offset(60, 40));
    await tester.pump();

    final liveA = container.read(interactionControllerProvider).groupLive['a'];
    expect(
      liveA,
      isNotNull,
      reason: 'Corner handle must start a group-resize session.',
    );
    expect(liveA!.size.width, greaterThan(aBefore.size.width));

    await g.up();
    await tester.pump();
    await tester.pump();

    final aAfter = container
        .read(documentControllerProvider)
        .layerById('a')!
        .transform;
    final bAfter = container
        .read(documentControllerProvider)
        .layerById('b')!
        .transform;
    expect(
      aAfter.size.width,
      greaterThan(aBefore.size.width),
      reason: 'Layer a must retain its scaled size after release.',
    );
    expect(
      bAfter.size.width,
      greaterThan(bBefore.size.width),
      reason: 'Layer b must retain its scaled size after release.',
    );
    await tester.pump(const Duration(seconds: 1));
  });
}
