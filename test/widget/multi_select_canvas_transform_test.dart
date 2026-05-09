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

/// Multi-select gesture-routing parity with single-select.
///
/// Spec: when 2+ layers are selected, the entire canvas behaves as a
/// transform surface for the group:
///
///   * 1 finger drag anywhere     → moves the whole group
///   * 2 fingers anywhere         → scale / rotate the group
///   * pause-then-drag            → still moves (claim-on-down)
///
/// Direct handle interactions and per-layer toggling on tap are
/// covered by other test files; this file only guards the new
/// off-group / pause-then-drag deferred-claim plumbing in
/// `GroupSelectionOverlay`.

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
  container.read(documentControllerProvider.notifier).execute(
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
  container.read(documentControllerProvider.notifier).execute(
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
  // Enter multi-select with both layers selected.
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
  testWidgets(
    'one-finger drag on empty canvas moves the whole group '
    '(deferred claim promotes on slop)',
    (tester) async {
      final container = _setup(tester);
      await _pumpEditorWithGroup(tester, container);

      final viewportBefore = container.read(viewportControllerProvider);

      // Drag from far off-group (top-left of viewport).
      final gesture = await tester.startGesture(const Offset(80, 80));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();

      final ui = container.read(interactionControllerProvider);
      expect(ui.groupSession, isNotNull,
          reason: 'One-finger off-group drag must promote the deferred '
              'claim into a GROUP session.');
      expect(ui.groupLive.length, 2);
      // Both layers must have moved relative to their original
      // positions.
      expect(ui.groupLive['a']!.position, isNot(const Offset(380, 380)));
      expect(ui.groupLive['b']!.position, isNot(const Offset(450, 380)));

      final viewportAfter = container.read(viewportControllerProvider);
      expect(viewportAfter.translation, viewportBefore.translation,
          reason: 'Viewport must NOT pan when a group is selected.');

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    },
  );

  testWidgets(
    'two-finger pinch starting entirely outside the group transforms '
    'the group (viewport stays put)',
    (tester) async {
      final container = _setup(tester);
      await _pumpEditorWithGroup(tester, container);

      final viewportBefore = container.read(viewportControllerProvider);
      Offset toScreen(Offset c) =>
          c * viewportBefore.scale + viewportBefore.translation;
      // Group spans roughly canvas (380, 380) → (490, 420). Centre on
      // screen, fingers ±220 px on either side.
      final centre = toScreen(const Offset(435, 400));
      final p1 = centre + const Offset(-220, 0);
      final p2 = centre + const Offset(220, 0);

      final f1 = await tester.startGesture(p1, pointer: 51);
      await tester.pump();
      expect(container.read(interactionControllerProvider).groupSession,
          isNull,
          reason: 'Deferred-claim: first off-group pointer must NOT '
              'start a session yet.');

      final f2 = await tester.startGesture(p2, pointer: 52);
      await tester.pump();
      final session =
          container.read(interactionControllerProvider).groupSession;
      expect(session, isNotNull);

      await f1.moveBy(const Offset(-100, 0));
      await f2.moveBy(const Offset(100, 0));
      await tester.pump();

      final ui = container.read(interactionControllerProvider);
      expect(ui.groupLiveBounds, isNotNull);
      // Group AABB must have grown horizontally.
      expect(ui.groupLiveBounds!.width, greaterThan(110 * 1.1));

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
    'pause-then-drag on empty canvas with a group selected still '
    'moves the group (claim-on-down beats the long-press recogniser)',
    (tester) async {
      final container = _setup(tester);
      await _pumpEditorWithGroup(tester, container);

      final gesture = await tester.startGesture(const Offset(80, 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        container.read(interactionControllerProvider).groupSession,
        isNull,
        reason: 'During the pause the recogniser owns the arena but '
            'has not emitted DragPhase.start yet.',
      );

      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();

      final ui = container.read(interactionControllerProvider);
      expect(ui.groupSession, isNotNull,
          reason: 'Pause-then-drag must still promote to a group '
              'session — long-press / tap recognisers must NOT steal '
              'the gesture.');
      expect(ui.groupLive['a']!.position, isNot(const Offset(380, 380)));

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    },
  );
}
