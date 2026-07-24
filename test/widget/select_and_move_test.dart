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

/// Select-and-move under the interaction contract, §5 row 5 (tb3 2/7):
/// a 1-finger drag STARTING on an eligible, un-selected layer's bbox
/// selects that layer and translates it in the same gesture.
///
///   * drag on an un-selected layer  → it becomes selected + moves;
///     the whole gesture lands as ONE undo entry (the transform
///     commit — selection is not a document command)
///   * sub-slop tap on it            → today's tap-select, NO move,
///     NO history entry (the lazy arena claim resolves at slop, so
///     taps keep their native canvas-recogniser timing)
///   * drag on locked / hidden bbox  → viewport pan (not eligible)
///   * empty selection               → same select-and-move; empty
///     canvas still pans (row 7)
///   * multi-select mode             → row 5 disabled, today's
///     behaviour exactly
///   * 2nd finger before the slop claim → the sequence is abandoned
///     to the viewport pinch (row 6 stays strict)
///
/// These tests guard `SelectAndMoveSurface` + the lazy arena mode of
/// `_BodyMultiTouchRecognizer` (selection_overlay.dart) and the
/// `_shouldClaimSelectAndMove` predicate (editor_canvas.dart).

ProviderContainer _setup(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void _addRect(
  ProviderContainer container, {
  required String id,
  required Offset position,
  Size size = const Size(60, 60),
  bool visible = true,
  bool locked = false,
}) {
  container
      .read(documentControllerProvider.notifier)
      .execute(
        AddLayerCommand(
          ShapeLayer(
            id: id,
            transform: LayerTransform(position: position, size: size),
            kind: ShapeKind.rectangle,
            visible: visible,
            locked: locked,
          ),
        ),
      );
}

Future<void> _pumpEditor(
  WidgetTester tester,
  ProviderContainer container,
) async {
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
  // Canvas is 800x800 in every test. Layer geography:
  //   'sel'   at (100, 100) 60x60 — the initially selected layer
  //   'other' at (370, 370) 60x60 — the row-5 drag target (centre
  //                                  (400, 400), far from 'sel')

  testWidgets('drag starting on an un-selected layer selects it and moves it '
      'in the same gesture, committing ONE undo entry', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    _addRect(container, id: 'other', position: const Offset(370, 370));
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    // Sub-slop: nothing has happened yet — no session, no selection
    // change (the arena is still open).
    expect(container.read(interactionControllerProvider).session, isNull);
    expect(container.read(selectionControllerProvider).selectedId, 'sel');

    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    // Slop promotion: 'other' is now selected AND its translate
    // session is live.
    expect(
      container.read(selectionControllerProvider).selectedId,
      'other',
      reason: 'Slop promotion must select the dragged layer.',
    );
    final session = container.read(interactionControllerProvider).session;
    expect(session, isNotNull);
    expect(session!.layerId, 'other');
    final live = container.read(interactionControllerProvider).liveTransform;
    expect(live!.position, isNot(const Offset(370, 370)));

    final viewportAfter = container.read(viewportControllerProvider);
    expect(
      viewportAfter.translation,
      viewportBefore.translation,
      reason: 'Viewport must NOT pan during select-and-move.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // Committed on release.
    final moved = container
        .read(documentControllerProvider)
        .layerById('other')!;
    expect(moved.transform.position, isNot(const Offset(370, 370)));

    // ONE undo entry for the whole gesture: the first undo restores
    // the position; the SECOND undo removes the layer itself (the
    // AddLayerCommand), proving nothing else was pushed in between —
    // the selection switch is a provider write, not a command.
    final docCtl = container.read(documentControllerProvider.notifier);
    docCtl.undo();
    final restored = container
        .read(documentControllerProvider)
        .layerById('other')!;
    expect(restored.transform.position, const Offset(370, 370));
    docCtl.undo();
    expect(
      container.read(documentControllerProvider).layerById('other'),
      isNull,
      reason:
          'Second undo must pop the AddLayerCommand — exactly one '
          'entry may sit between it and the top.',
    );
  });

  testWidgets('sub-slop tap on an un-selected layer stays a tap-select: '
      'no move, no history entry, native tap timing', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    _addRect(container, id: 'other', position: const Offset(370, 370));
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    await tester.tapAt(_toScreen(container, const Offset(400, 400)));
    // Let the double-tap window lapse so the single-tap resolves.
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(selectionControllerProvider).selectedId,
      'other',
      reason: 'A sub-slop release must resolve as today\'s tap-select.',
    );
    final other = container
        .read(documentControllerProvider)
        .layerById('other')!;
    expect(other.transform.position, const Offset(370, 370));

    // No transform entry: the top of the undo stack must still be
    // the AddLayerCommand for 'other'.
    container.read(documentControllerProvider.notifier).undo();
    expect(
      container.read(documentControllerProvider).layerById('other'),
      isNull,
      reason: 'A tap must not push any history entry.',
    );
  });

  testWidgets('drag starting on a LOCKED layer bbox pans the viewport and '
      'leaves the selection alone', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    _addRect(
      container,
      id: 'lock',
      position: const Offset(370, 370),
      locked: true,
    );
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    expect(container.read(interactionControllerProvider).session, isNull);
    expect(container.read(selectionControllerProvider).selectedId, 'sel');
    expect(
      container.read(viewportControllerProvider).translation,
      isNot(viewportBefore.translation),
      reason: 'A locked layer is not an eligible row-5 target — pan.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final lock = container.read(documentControllerProvider).layerById('lock')!;
    expect(lock.transform.position, const Offset(370, 370));
  });

  testWidgets('drag starting on a HIDDEN layer bbox pans the viewport', (
    tester,
  ) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    _addRect(
      container,
      id: 'hid',
      position: const Offset(370, 370),
      visible: false,
    );
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    expect(container.read(interactionControllerProvider).session, isNull);
    expect(container.read(selectionControllerProvider).selectedId, 'sel');
    expect(
      container.read(viewportControllerProvider).translation,
      isNot(viewportBefore.translation),
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('with NO selection, drag on a layer selects and moves it; '
      'drag on empty canvas still pans (row 7)', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'other', position: const Offset(370, 370));
    await _pumpEditor(tester, container);
    expect(container.read(selectionControllerProvider).hasSelection, isFalse);

    // Part 1: drag on the layer → select + move.
    final onLayer = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await onLayer.moveBy(const Offset(60, 40));
    await tester.pump();
    await onLayer.moveBy(const Offset(60, 40));
    await tester.pump();

    expect(container.read(selectionControllerProvider).selectedId, 'other');
    final session = container.read(interactionControllerProvider).session;
    expect(session, isNotNull);
    expect(session!.layerId, 'other');

    await onLayer.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    final moved = container
        .read(documentControllerProvider)
        .layerById('other')!;
    expect(moved.transform.position, isNot(const Offset(370, 370)));

    // Part 2: clear the selection; empty-canvas drag pans.
    container.read(selectionControllerProvider.notifier).clear();
    await tester.pump();
    final viewportBefore = container.read(viewportControllerProvider);
    final onCanvas = await tester.startGesture(const Offset(80, 80));
    await tester.pump();
    await onCanvas.moveBy(const Offset(60, 40));
    await tester.pump();
    await onCanvas.moveBy(const Offset(60, 40));
    await tester.pump();

    expect(container.read(interactionControllerProvider).session, isNull);
    expect(container.read(selectionControllerProvider).hasSelection, isFalse);
    expect(
      container.read(viewportControllerProvider).translation,
      isNot(viewportBefore.translation),
    );

    await onCanvas.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('multi-select mode: drag on a NON-member layer keeps today\'s '
      'behaviour exactly — viewport pan, membership untouched', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'a', position: const Offset(100, 100));
    _addRect(container, id: 'b', position: const Offset(200, 100));
    _addRect(container, id: 'c', position: const Offset(370, 370));
    container.read(selectionModeProvider.notifier).enterMulti();
    container.read(selectionControllerProvider.notifier).selectMany(['a', 'b']);
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    final ui = container.read(interactionControllerProvider);
    expect(ui.session, isNull);
    expect(ui.groupSession, isNull);
    expect(
      container.read(selectionControllerProvider).selectedIds,
      unorderedEquals(['a', 'b']),
      reason: 'Row 5 must not fire in multi-select mode.',
    );
    expect(
      container.read(viewportControllerProvider).translation,
      isNot(viewportBefore.translation),
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final c = container.read(documentControllerProvider).layerById('c')!;
    expect(c.transform.position, const Offset(370, 370));
  });

  testWidgets('second finger before the slop claim abandons the sequence to '
      'the viewport pinch (row 6 stays strict)', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    _addRect(container, id: 'other', position: const Offset(370, 370));
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    // First finger on the un-selected layer (a row-5 candidate),
    // second finger lands BEFORE any movement.
    final f1 = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
      pointer: 61,
    );
    await tester.pump();
    final f2 = await tester.startGesture(
      _toScreen(container, const Offset(600, 400)),
      pointer: 62,
    );
    await tester.pump();

    await f1.moveBy(const Offset(-80, 0));
    await f2.moveBy(const Offset(80, 0));
    await tester.pump();

    expect(
      container.read(interactionControllerProvider).session,
      isNull,
      reason: 'The pair must belong to the viewport, not the layer.',
    );
    expect(container.read(selectionControllerProvider).selectedId, 'sel');
    expect(
      container.read(viewportControllerProvider).scale,
      greaterThan(viewportBefore.scale),
    );

    await f1.up();
    await f2.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final other = container
        .read(documentControllerProvider)
        .layerById('other')!;
    expect(other.transform.position, const Offset(370, 370));
    expect(other.transform.size, const Size(60, 60));
  });

  testWidgets('a second finger AFTER the slop claim joins the select-and-move '
      'session and pinches the newly selected layer', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    _addRect(container, id: 'other', position: const Offset(370, 370));
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final f1 = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
      pointer: 63,
    );
    await tester.pump();
    await f1.moveBy(const Offset(40, 0));
    await tester.pump();
    // Session is live for 'other'; the selection overlay has just
    // remounted for it. The second finger must fall THROUGH that
    // overlay and join the recogniser that owns the sequence.
    expect(
      container.read(interactionControllerProvider).session?.layerId,
      'other',
    );

    final f2 = await tester.startGesture(
      _toScreen(container, const Offset(650, 400)),
      pointer: 64,
    );
    await tester.pump();
    await f1.moveBy(const Offset(-80, 0));
    await f2.moveBy(const Offset(80, 0));
    await tester.pump();

    final live = container.read(interactionControllerProvider).liveTransform;
    expect(live, isNotNull);
    expect(
      live!.size.width,
      greaterThan(60 * 1.1),
      reason: 'The joined finger must pinch the layer, not the viewport.',
    );
    final viewportAfter = container.read(viewportControllerProvider);
    expect(viewportAfter.scale, viewportBefore.scale);
    expect(viewportAfter.translation, viewportBefore.translation);

    await f1.up();
    await f2.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });
}
