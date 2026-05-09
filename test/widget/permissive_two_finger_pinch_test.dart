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

/// "Selected layer owns the canvas" gesture-routing regressions.
///
/// Spec: when a layer is selected, the entire canvas acts as a
/// transform surface for it.
///
///   * 1 finger drag anywhere     → moves the selected layer
///   * 2 fingers anywhere         → scale / rotate the selected layer
///   * tap on empty canvas        → unselects
///   * pause-then-drag            → still moves (long-press / tap
///                                   recognisers must NOT steal it)
///
/// These tests guard the `_BodyMultiTouchRecognizer` deferred-claim
/// state machine and its long-press timer.

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
  container.read(documentControllerProvider.notifier).execute(
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

void main() {
  testWidgets(
    'two-finger pinch starting entirely outside a selected layer '
    'transforms the layer (viewport stays put)',
    (tester) async {
      final container = _setup(tester);
      const layerPos = Offset(370, 370);
      const layerSize = Size(60, 60);
      await _pumpEditorWithLayer(tester, container,
          position: layerPos, size: layerSize);

      final viewportBefore = container.read(viewportControllerProvider);
      Offset toScreen(Offset c) =>
          c * viewportBefore.scale + viewportBefore.translation;
      final centreScreen = toScreen(
          layerPos + Offset(layerSize.width / 2, layerSize.height / 2));
      final p1 = centreScreen + const Offset(-200, 0);
      final p2 = centreScreen + const Offset(200, 0);

      final f1 = await tester.startGesture(p1, pointer: 41);
      await tester.pump();
      expect(
        container.read(interactionControllerProvider).session,
        isNull,
        reason: 'Deferred-claim: first off-object pointer must NOT '
            'start a session yet.',
      );

      final f2 = await tester.startGesture(p2, pointer: 42);
      await tester.pump();
      final session =
          container.read(interactionControllerProvider).session;
      expect(session, isNotNull);
      expect(session!.layerId, 'shape');

      await f1.moveBy(const Offset(-100, 0));
      await f2.moveBy(const Offset(100, 0));
      await tester.pump();

      final live =
          container.read(interactionControllerProvider).liveTransform;
      expect(live, isNotNull);
      expect(live!.size.width, greaterThan(layerSize.width * 1.1));

      final viewportAfter = container.read(viewportControllerProvider);
      expect(viewportAfter.scale, viewportBefore.scale);
      expect(viewportAfter.translation, viewportBefore.translation);

      await f1.up();
      await f2.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    },
  );

  testWidgets(
    'one-finger drag on empty canvas moves the selected layer '
    '(deferred claim promotes on slop)',
    (tester) async {
      final container = _setup(tester);
      const layerPos = Offset(370, 370);
      await _pumpEditorWithLayer(tester, container, position: layerPos);

      final viewportBefore = container.read(viewportControllerProvider);

      final gesture = await tester.startGesture(const Offset(80, 80));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();

      final session =
          container.read(interactionControllerProvider).session;
      expect(session, isNotNull,
          reason: 'One-finger off-object drag must promote the '
              'deferred claim into a body session.');
      expect(session!.layerId, 'shape');

      final live =
          container.read(interactionControllerProvider).liveTransform;
      expect(live, isNotNull);
      expect(live!.position, isNot(layerPos));

      final viewportAfter = container.read(viewportControllerProvider);
      expect(viewportAfter.translation, viewportBefore.translation,
          reason: 'Viewport must NOT pan when a layer is selected.');

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    },
  );

  testWidgets(
    'pause-then-drag on empty canvas still moves the selected layer '
    '(claim-on-down beats the long-press recogniser)',
    (tester) async {
      final container = _setup(tester);
      const layerPos = Offset(370, 370);
      await _pumpEditorWithLayer(tester, container, position: layerPos);

      // Touch down off-object, hold for 250ms (well into the window
      // where the viewport's tap / long-press recognisers historically
      // would have stolen the gesture), THEN start dragging.
      final gesture = await tester.startGesture(const Offset(80, 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        container.read(interactionControllerProvider).session,
        isNull,
        reason: 'During the pause the recogniser owns the arena but '
            'has not emitted DragPhase.start yet.',
      );

      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();

      final session =
          container.read(interactionControllerProvider).session;
      expect(session, isNotNull,
          reason: 'Pause-then-drag must promote to a body session — '
              "the framework's long-press / tap recognisers must NOT "
              'steal the gesture during the pause.');
      expect(session!.layerId, 'shape');

      final live =
          container.read(interactionControllerProvider).liveTransform;
      expect(live, isNotNull);
      expect(live!.position, isNot(layerPos));

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    },
  );

  testWidgets(
    'long-press off-object with a layer selected enters multi-select '
    'mode (deferred-claim long-press timer routes through onBodyLongPress)',
    (tester) async {
      final container = _setup(tester);
      await _pumpEditorWithLayer(tester, container);

      // Sanity: not in multi mode yet, layer is selected.
      expect(container.read(selectionModeProvider), SelectionMode.single);
      expect(container.read(selectionControllerProvider).hasSelection, isTrue);

      // Touch down off-object and hold past the long-press timeout
      // without moving. With the new claim-on-down policy the body
      // surface owns this pointer from the start, so the canvas-level
      // `GestureDetector.onLongPressStart` never fires; the timer
      // inside `_BodyMultiTouchRecognizer` is what re-injects the
      // long-press intent via `onBodyLongPress` → `_handleLongPress`.
      final gesture = await tester.startGesture(const Offset(80, 80));
      await tester.pump();
      // Pump well past kLongPressTimeout (500ms). Use a single big
      // pump so the timer's microtask resolves cleanly.
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        container.read(selectionModeProvider),
        SelectionMode.multi,
        reason: 'Long-press off-object with selection must reach the '
            'canvas long-press handler via onBodyLongPress.',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    },
  );

  testWidgets(
    'single tap on empty canvas still unselects '
    '(deferred claim routes through onTap on lift-without-movement)',
    (tester) async {
      final container = _setup(tester);
      await _pumpEditorWithLayer(tester, container);

      expect(container.read(selectionControllerProvider).hasSelection, isTrue);

      await tester.tapAt(const Offset(80, 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        container.read(selectionControllerProvider).hasSelection,
        isFalse,
        reason: 'Empty-canvas tap must still unselect — onTap callback '
            'fires on lift-without-movement and routes to _handleTap.',
      );
    },
  );
}
