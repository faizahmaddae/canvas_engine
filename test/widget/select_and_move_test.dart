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

/// Select-and-move + drag-anywhere under the interaction contract,
/// §5 rows 5 and 7 (tb3 2/7; drag-anywhere amendment 2026-07-30;
/// selection-wins amendment 2026-08-22).
///
/// The ordering rule, which is what most of these pin: while a
/// movable single selection exists it OWNS the one-finger drag
/// wherever the finger lands (row 7). Row 5 — land on a layer, select
/// and move it in one gesture — applies only when no such selection
/// exists to own the gesture.
///
///   * drag anywhere with a movable single selection → the SELECTION
///     translates, including when the finger starts on another
///     eligible layer's bbox, on a locked/hidden layer's bbox, or on
///     empty canvas; one undo entry (the transform commit —
///     selection is not a document command), viewport still
///   * sub-slop tap on another layer → today's tap-select, NO move,
///     NO history entry (the lazy arena claim resolves at slop, so
///     taps keep their native canvas-recogniser timing) — this is
///     the escape hatch that makes selection-wins liveable
///   * locked / hidden / absent SELECTION → row 7 declines; row 5
///     claims an eligible layer under the finger, else the viewport
///     pans (the protected base photo keeps photo-project navigation)
///   * multi-select mode             → rows 5 + 7-drag disabled,
///     today's behaviour exactly
///   * 2nd finger before the slop claim → the sequence is abandoned
///     to the viewport pinch (row 6 stays strict)
///
/// These tests guard `SelectAndMoveSurface` + the lazy arena mode of
/// `_BodyMultiTouchRecognizer` (selection_overlay.dart) and the
/// `_shouldClaimSelectAndMove` predicate (canvas_gesture_router.dart).

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

  testWidgets('selection-wins: a drag starting ON ANOTHER eligible layer '
      'translates the SELECTION, never the layer under the finger, '
      'committing ONE undo entry', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    _addRect(container, id: 'other', position: const Offset(370, 370));
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    // Dead centre of 'other' — as unambiguous a landing on the
    // neighbour as exists. Row 5 used to claim it; row 7 does now.
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

    // Slop promotion drives the SELECTION. The selection itself never
    // changes: a drag is a verb applied to the declared subject, not
    // a way to re-declare it.
    expect(
      container.read(selectionControllerProvider).selectedId,
      'sel',
      reason: 'A drag must never re-target the selection.',
    );
    final session = container.read(interactionControllerProvider).session;
    expect(session, isNotNull);
    expect(session!.layerId, 'sel');
    final live = container.read(interactionControllerProvider).liveTransform;
    expect(live!.position, isNot(const Offset(100, 100)));

    final viewportAfter = container.read(viewportControllerProvider);
    expect(
      viewportAfter.translation,
      viewportBefore.translation,
      reason: 'Viewport must NOT pan during drag-anywhere.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // Committed on release — and the neighbour the finger sat on is
    // exactly where it started.
    final doc = container.read(documentControllerProvider);
    expect(
      doc.layerById('sel')!.transform.position,
      isNot(const Offset(100, 100)),
    );
    expect(
      doc.layerById('other')!.transform.position,
      const Offset(370, 370),
      reason: 'The layer under the finger must not move.',
    );

    // ONE undo entry for the whole gesture: the first undo restores
    // the position; the SECOND undo removes a layer (the
    // AddLayerCommand), proving nothing else was pushed in between.
    final docCtl = container.read(documentControllerProvider.notifier);
    docCtl.undo();
    expect(
      container
          .read(documentControllerProvider)
          .layerById('sel')!
          .transform
          .position,
      const Offset(100, 100),
    );
    docCtl.undo();
    expect(
      container.read(documentControllerProvider).layerById('other'),
      isNull,
      reason:
          'Second undo must pop the AddLayerCommand — exactly one '
          'entry may sit between it and the top.',
    );
  });

  testWidgets('the escape hatch: tap the neighbour first, THEN drag — the '
      'newly selected layer moves and the old one stays', (tester) async {
    // Selection-wins costs one gesture when the user genuinely wants
    // a different object. This is that path, pinned: without it the
    // rule would be a trap rather than a trade.
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    _addRect(container, id: 'other', position: const Offset(370, 370));
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    await tester.tapAt(_toScreen(container, const Offset(400, 400)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(selectionControllerProvider).selectedId, 'other');

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    expect(
      container.read(interactionControllerProvider).session?.layerId,
      'other',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final doc = container.read(documentControllerProvider);
    expect(
      doc.layerById('other')!.transform.position,
      isNot(const Offset(370, 370)),
    );
    expect(doc.layerById('sel')!.transform.position, const Offset(100, 100));
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

  testWidgets('drag starting on a LOCKED layer bbox is not a row-5 claim: '
      'it drag-anywhere-moves the SELECTION instead (row 7 as amended)', (
    tester,
  ) async {
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

    // A locked layer stays pointer-ineligible (it must never be
    // selected or moved by a drag), so its area reads as background —
    // and background drags now translate the selection. This is the
    // photo-project core case: the base photo is a locked layer
    // covering the whole canvas.
    final session = container.read(interactionControllerProvider).session;
    expect(session, isNotNull);
    expect(session!.layerId, 'sel');
    expect(container.read(selectionControllerProvider).selectedId, 'sel');
    expect(
      container.read(viewportControllerProvider).translation,
      viewportBefore.translation,
      reason: 'Drag-anywhere must not pan the viewport alongside.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final lock = container.read(documentControllerProvider).layerById('lock')!;
    expect(
      lock.transform.position,
      const Offset(370, 370),
      reason: 'The locked layer itself must never move.',
    );
    final sel = container.read(documentControllerProvider).layerById('sel')!;
    expect(sel.transform.position, isNot(const Offset(100, 100)));
  });

  testWidgets('drag starting on a HIDDEN layer bbox reads as empty canvas: '
      'the selection drag-anywhere-moves, the hidden layer stays', (
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

    final session = container.read(interactionControllerProvider).session;
    expect(session, isNotNull);
    expect(session!.layerId, 'sel');
    expect(container.read(selectionControllerProvider).selectedId, 'sel');
    expect(
      container.read(viewportControllerProvider).translation,
      viewportBefore.translation,
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final hid = container.read(documentControllerProvider).layerById('hid')!;
    expect(hid.transform.position, const Offset(370, 370));
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

    // First finger on the un-selected layer — a claim candidate
    // either way (row 7 today, row 5 before selection-wins) — and the
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
      'session and pinches the layer that session owns', (tester) async {
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
    // Session is live for the SELECTION even though the first finger
    // landed on 'other'. The second finger must fall THROUGH the
    // selection overlay and join the recogniser that owns the
    // sequence, one Stack level below.
    expect(
      container.read(interactionControllerProvider).session?.layerId,
      'sel',
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

  testWidgets('drag-anywhere: a drag starting on empty canvas translates the '
      'single movable selection, committing ONE undo entry (row 7 as '
      'amended)', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(500, 500)),
    );
    await tester.pump();
    // Sub-slop: lazy claim — no session yet, so a release here would
    // still resolve as the E3 deselect tap.
    expect(container.read(interactionControllerProvider).session, isNull);

    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    final session = container.read(interactionControllerProvider).session;
    expect(session, isNotNull);
    expect(session!.layerId, 'sel');
    expect(container.read(selectionControllerProvider).selectedId, 'sel');
    expect(
      container.read(viewportControllerProvider).translation,
      viewportBefore.translation,
      reason: 'Drag-anywhere must not pan the viewport alongside.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final moved = container.read(documentControllerProvider).layerById('sel')!;
    expect(moved.transform.position, isNot(const Offset(100, 100)));

    // ONE undo entry for the whole gesture — the first undo restores
    // the position, the second pops the AddLayerCommand.
    final docCtl = container.read(documentControllerProvider.notifier);
    docCtl.undo();
    expect(
      container
          .read(documentControllerProvider)
          .layerById('sel')!
          .transform
          .position,
      const Offset(100, 100),
    );
    docCtl.undo();
    expect(container.read(documentControllerProvider).layerById('sel'), isNull);
  });

  testWidgets('drag-anywhere declines a LOCKED selection: empty-canvas drag '
      'keeps panning (protected base photo keeps photo navigation)', (
    tester,
  ) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(
      container,
      id: 'lockSel',
      position: const Offset(100, 100),
      locked: true,
    );
    // Mimics the base-photo reachability selection: locked layers can
    // be selected (Layers panel, base-photo tap) but never dragged.
    container.read(selectionControllerProvider.notifier).select('lockSel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(500, 500)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    expect(container.read(interactionControllerProvider).session, isNull);
    expect(
      container.read(viewportControllerProvider).translation,
      isNot(viewportBefore.translation),
      reason: 'A locked selection cannot be dragged — the viewport pans.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final lock = container
        .read(documentControllerProvider)
        .layerById('lockSel')!;
    expect(lock.transform.position, const Offset(100, 100));
  });

  testWidgets('drag-anywhere declines a HIDDEN selection: empty-canvas drag '
      'keeps panning', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(
      container,
      id: 'hidSel',
      position: const Offset(100, 100),
      visible: false,
    );
    container.read(selectionControllerProvider.notifier).select('hidSel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(500, 500)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    expect(container.read(interactionControllerProvider).session, isNull);
    expect(
      container.read(viewportControllerProvider).translation,
      isNot(viewportBefore.translation),
      reason: 'A hidden selection has no honest drag — the viewport pans.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('drag-anywhere continues naturally past the canvas bounds: the '
      'session survives the pointer leaving the board and commits where it '
      'ends', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(500, 500)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(100, 80));
    await tester.pump();
    await gesture.moveBy(const Offset(100, 80));
    await tester.pump();
    final liveInside = container
        .read(interactionControllerProvider)
        .liveTransform!;

    // Carry the pointer well beyond the 800×800 viewport in several
    // steps (the single-finger path is EMA-smoothed, so magnitude
    // builds over events, not per jump). The recogniser owns the
    // pointer globally after the slop claim, so the session must keep
    // tracking out there.
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(120, 80));
      await tester.pump();
    }

    final session = container.read(interactionControllerProvider).session;
    expect(
      session,
      isNotNull,
      reason: 'Leaving the canvas bounds must not end the session.',
    );
    expect(session!.layerId, 'sel');
    final liveBeyond = container
        .read(interactionControllerProvider)
        .liveTransform!;
    expect(
      liveBeyond.position.dx,
      greaterThan(liveInside.position.dx + 20),
      reason: 'The layer must keep following the pointer past the bounds.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final moved = container.read(documentControllerProvider).layerById('sel')!;
    expect(moved.transform.position.dx, greaterThan(liveInside.position.dx));
  });

  testWidgets('a second finger joining a drag-anywhere session pinches the '
      'selection about its own centre — no orbit around the remote focal', (
    tester,
  ) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'sel', position: const Offset(100, 100));
    container.read(selectionControllerProvider.notifier).select('sel');
    await _pumpEditor(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final f1 = await tester.startGesture(
      _toScreen(container, const Offset(500, 500)),
      pointer: 71,
    );
    await tester.pump();
    await f1.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(
      container.read(interactionControllerProvider).session?.layerId,
      'sel',
    );
    final liveBefore = container
        .read(interactionControllerProvider)
        .liveTransform!;
    final centreBefore = liveBefore.center;

    final f2 = await tester.startGesture(
      _toScreen(container, const Offset(700, 500)),
      pointer: 72,
    );
    await tester.pump();
    // Symmetric spread: net focal delta is zero, so the layer must
    // scale in place — its centre stays put even though both fingers
    // are far away from it.
    await f1.moveBy(const Offset(-80, 0));
    await f2.moveBy(const Offset(80, 0));
    await tester.pump();

    final liveAfter = container
        .read(interactionControllerProvider)
        .liveTransform!;
    expect(liveAfter.size.width, greaterThan(60 * 1.1));
    expect(liveAfter.center.dx, moreOrLessEquals(centreBefore.dx, epsilon: 1));
    expect(liveAfter.center.dy, moreOrLessEquals(centreBefore.dy, epsilon: 1));
    final viewportAfter = container.read(viewportControllerProvider);
    expect(viewportAfter.scale, viewportBefore.scale);
    expect(viewportAfter.translation, viewportBefore.translation);

    await f1.up();
    await f2.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });
}
