import 'package:canvas_engine/core/constants/engine_constants.dart';
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

/// Gesture routing under the interaction contract, §5 rows 4, 6 and 7
/// (tb3 1/7): the selection's CHROME QUAD — the rotated bbox plus the
/// drawn handle outset — is the claim boundary, and everything
/// outside it belongs to the viewport.
///
///   * 1 finger ON the quad         → translates the selected layer
///   * 2 fingers, first ON the quad → pinch/rotate the layer (the
///                                    second finger may land anywhere)
///   * 1 finger OFF the quad        → translates the selection too
///                                    (row 7 as amended: drag-anywhere;
///                                    the viewport stays put — one-finger
///                                    pan requires no selection, a
///                                    multi-selection, or a locked/hidden
///                                    selection)
///   * 2 fingers OFF the quad       → viewport pinch, even with a
///                                    selection (row 6)
///   * 2nd finger ON the quad joining a sequence whose 1st finger
///     started OFF it               → still a viewport pinch (row 6
///                                    sequence continuation)
///   * tap / long-press OFF the quad → unselect / multi-select entry
///     (now via the canvas-level recognisers, since nothing claims
///     those pointers any more)
///
/// These tests guard the `shouldClaimBody` chrome-quad predicate in
/// `editor_canvas.dart` and the `_BodyMultiTouchRecognizer`
/// first-pointer gate in `selection_overlay.dart`.

ProviderContainer _setup(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpEditorWithLayer(
  WidgetTester tester,
  ProviderContainer container, {
  Offset position = const Offset(370, 370),
  Size size = const Size(60, 60),
}) async {
  container
      .read(documentControllerProvider.notifier)
      .newDocument(width: 800, height: 800);
  container
      .read(documentControllerProvider.notifier)
      .execute(
        AddLayerCommand(
          ShapeLayer(
            id: 'shape',
            transform: LayerTransform(position: position, size: size),
            kind: ShapeKind.rectangle,
          ),
        ),
      );
  container.read(selectionControllerProvider.notifier).select('shape');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Offset _toScreen(ProviderContainer container, Offset canvas) {
  final vp = container.read(viewportControllerProvider);
  return canvas * vp.scale + vp.translation;
}

void main() {
  // The layer spans canvas (370, 370) → (430, 430) in every test;
  // its centre is (400, 400).

  testWidgets('two-finger pinch off the layer zooms the viewport and leaves '
      'the layer + selection untouched (contract §5 row 6)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithLayer(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);
    final centre = _toScreen(container, const Offset(400, 400));
    final p1 = centre + const Offset(-200, 0);
    final p2 = centre + const Offset(200, 0);

    final f1 = await tester.startGesture(p1, pointer: 41);
    await tester.pump();
    final f2 = await tester.startGesture(p2, pointer: 42);
    await tester.pump();

    await f1.moveBy(const Offset(-100, 0));
    await f2.moveBy(const Offset(100, 0));
    await tester.pump();

    expect(
      container.read(interactionControllerProvider).session,
      isNull,
      reason: 'Off-quad fingers must never start a layer session.',
    );
    final viewportDuring = container.read(viewportControllerProvider);
    expect(
      viewportDuring.scale,
      greaterThan(viewportBefore.scale),
      reason: 'Off-quad pinch must zoom the viewport.',
    );

    await f1.up();
    await f2.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final layer = container
        .read(documentControllerProvider)
        .layerById('shape')!;
    expect(layer.transform.position, const Offset(370, 370));
    expect(layer.transform.size, const Size(60, 60));
    expect(
      container.read(selectionControllerProvider).selectedId,
      'shape',
      reason: 'Viewport navigation must not clear the selection.',
    );
  });

  testWidgets('second finger landing ON the quad after an off-quad first '
      'finger stays a viewport pinch (row 6 sequence continuation)', (
    tester,
  ) async {
    final container = _setup(tester);
    await _pumpEditorWithLayer(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    // First finger far off the layer; it stays sub-slop (unclaimed,
    // arena still open) when the second finger lands on the layer.
    final f1 = await tester.startGesture(const Offset(100, 400), pointer: 43);
    await tester.pump();
    final f2 = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
      pointer: 44,
    );
    await tester.pump();

    expect(
      container.read(interactionControllerProvider).session,
      isNull,
      reason:
          'A finger joining a sequence whose first finger was refused '
          'must be refused too — the pair belongs to the viewport.',
    );

    await f1.moveBy(const Offset(-60, 0));
    await f2.moveBy(const Offset(60, 0));
    await tester.pump();

    expect(container.read(interactionControllerProvider).session, isNull);
    final viewportDuring = container.read(viewportControllerProvider);
    expect(
      viewportDuring.scale,
      greaterThan(viewportBefore.scale),
      reason: 'The pair must drive the viewport pinch.',
    );

    await f1.up();
    await f2.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final layer = container
        .read(documentControllerProvider)
        .layerById('shape')!;
    expect(layer.transform.position, const Offset(370, 370));
    expect(layer.transform.size, const Size(60, 60));
  });

  testWidgets('two fingers with the first ON the layer pinch the layer '
      '(small-object pinch: second finger may land anywhere)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithLayer(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);
    final p1 = _toScreen(container, const Offset(400, 400));
    // Second finger well outside the layer.
    final p2 = _toScreen(container, const Offset(650, 400));

    final f1 = await tester.startGesture(p1, pointer: 45);
    await tester.pump();
    // Claim ≠ start (tb3 3/7): the arena is claimed on down, but the
    // session waits for slop or a second finger — a stationary hold
    // must be able to become a long-press.
    expect(container.read(interactionControllerProvider).session, isNull);

    final f2 = await tester.startGesture(p2, pointer: 46);
    await tester.pump();
    // Second finger promotes the deferred claim into a session
    // immediately (pinch needs no slop).
    final session = container.read(interactionControllerProvider).session;
    expect(session, isNotNull);
    expect(session!.layerId, 'shape');
    await f1.moveBy(const Offset(-60, 0));
    await f2.moveBy(const Offset(60, 0));
    await tester.pump();

    final live = container.read(interactionControllerProvider).liveTransform;
    expect(live, isNotNull);
    expect(live!.size.width, greaterThan(60 * 1.1));

    final viewportAfter = container.read(viewportControllerProvider);
    expect(viewportAfter.scale, viewportBefore.scale);
    expect(viewportAfter.translation, viewportBefore.translation);

    await f1.up();
    await f2.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('one-finger drag on the layer translates it '
      '(viewport stays put)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithLayer(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    final session = container.read(interactionControllerProvider).session;
    expect(session, isNotNull);
    expect(session!.layerId, 'shape');
    final live = container.read(interactionControllerProvider).liveTransform;
    expect(live, isNotNull);
    expect(live!.position, isNot(const Offset(370, 370)));

    final viewportAfter = container.read(viewportControllerProvider);
    expect(
      viewportAfter.translation,
      viewportBefore.translation,
      reason: 'Viewport must NOT pan while the layer is being dragged.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('one-finger drag off the layer translates the selection — '
      'drag-anywhere — and the viewport stays put (contract §5 row 7 as '
      'amended)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithLayer(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(const Offset(80, 80));
    await tester.pump();
    // Sub-slop: the claim is lazy, so nothing has started yet — a
    // release here would still be the E3 deselect tap.
    expect(container.read(interactionControllerProvider).session, isNull);

    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    final session = container.read(interactionControllerProvider).session;
    expect(
      session,
      isNotNull,
      reason: 'Off-quad drag with a movable selection must move it.',
    );
    expect(session!.layerId, 'shape');
    final live = container.read(interactionControllerProvider).liveTransform;
    expect(live!.position, isNot(const Offset(370, 370)));
    final viewportDuring = container.read(viewportControllerProvider);
    expect(
      viewportDuring.translation,
      viewportBefore.translation,
      reason: 'Drag-anywhere must NOT pan the viewport alongside.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final layer = container
        .read(documentControllerProvider)
        .layerById('shape')!;
    expect(layer.transform.position, isNot(const Offset(370, 370)));
    expect(
      container.read(selectionControllerProvider).selectedId,
      'shape',
      reason: 'Drag-anywhere must not change the selection.',
    );
  });

  testWidgets('press in the outset ring (outside the bbox, inside the drawn '
      'chrome) still grabs the layer — the claim boundary is the chrome '
      'quad, not the raw bbox', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithLayer(tester, container);

    // Midpoint of the outset ring, left of the layer's left edge: the
    // drawn chrome sits EngineConstants.selectionOutset SCREEN px
    // outside the bbox, i.e. outset / viewport.scale canvas units.
    final vp = container.read(viewportControllerProvider);
    final ringCanvas = Offset(
      370 - (EngineConstants.selectionOutset / vp.scale) / 2,
      400,
    );
    final gesture = await tester.startGesture(_toScreen(container, ringCanvas));
    await tester.pump();
    // Ring presses defer the session start (tap-cycling on the frame
    // edge must survive) — promotion happens on movement past slop.
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();

    final session = container.read(interactionControllerProvider).session;
    expect(
      session,
      isNotNull,
      reason: 'A ring press that drags must translate the layer.',
    );
    expect(session!.layerId, 'shape');
    final live = container.read(interactionControllerProvider).liveTransform;
    expect(live!.position, isNot(const Offset(370, 370)));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('long-press off the layer with a selection enters multi-select '
      'mode (off-quad pointers reach the canvas long-press recogniser)', (
    tester,
  ) async {
    final container = _setup(tester);
    await _pumpEditorWithLayer(tester, container);

    expect(container.read(selectionModeProvider), SelectionMode.single);
    expect(container.read(selectionControllerProvider).hasSelection, isTrue);

    final gesture = await tester.startGesture(const Offset(80, 80));
    await tester.pump();
    // Pump well past kLongPressTimeout (500ms).
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      container.read(selectionModeProvider),
      SelectionMode.multi,
      reason:
          'Long-press off the quad must reach the canvas long-press '
          'handler now that the body surface no longer claims it.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('single tap on empty canvas still unselects', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithLayer(tester, container);

    expect(container.read(selectionControllerProvider).hasSelection, isTrue);

    await tester.tapAt(const Offset(80, 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(
      container.read(selectionControllerProvider).hasSelection,
      isFalse,
      reason:
          'Empty-canvas tap must still unselect via the canvas-level '
          'tap recogniser.',
    );
  });
}
