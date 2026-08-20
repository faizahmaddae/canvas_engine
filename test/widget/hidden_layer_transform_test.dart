import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/interaction_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/layer_state_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/quick_capsule.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/selection_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hidden-layer transform gating (ux-audit 2026-07-29 §P2-6; contract
/// §5 pointer-eligibility, §10.2, §10.3).
///
/// A layer hidden WHILE selected (Layers-drawer eye) keeps its
/// selection, but the canvas must stop promising transforms whose
/// commits the interaction controller refuses — before this gate, the
/// full frame + handles + quick capsule rendered over empty space, the
/// drag tracked the finger, and `end()` / `_endGroup` silently dropped
/// the commit on release ("drags a ghost, nothing persists").
///
/// These tests guard:
///   * start/commit parity in `InteractionController` (invariant 5):
///     `start*` and `_eligibleInitials` refuse hidden layers exactly
///     as `end()` (`stillEligible`) and `_endGroup` refuse to commit
///     them, so no armed gesture is ever silently discarded;
///   * the hidden gates in `canvas_chrome.dart`: no
///     [LayerSelectionOverlay] / [QuickCapsule] for a hidden
///     selection, and group chrome that describes only the visible
///     members it will actually drive;
///   * the released chrome quad in `canvas_gesture_router.dart`: a
///     hidden selection reserves no quad, so its area reads as empty
///     canvas — row 5 for an eligible layer underneath, else viewport.
///
/// Row 5/7 claim behaviour for hidden layers (drag ON a hidden
/// non-selected layer, drag-anywhere with a hidden selection) is
/// already pinned in `select_and_move_test.dart`.

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
  testWidgets('hiding the selected layer removes its interactive chrome: '
      'no selection overlay, no quick capsule, selection kept (§10.3)', (
    tester,
  ) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'ghost', position: const Offset(100, 100));
    container.read(selectionControllerProvider.notifier).select('ghost');
    await _pumpEditor(tester, container);

    // Sanity: a visible selection renders its chrome.
    expect(find.byType(LayerSelectionOverlay), findsOneWidget);
    expect(find.byType(QuickCapsule), findsOneWidget);

    // Hide WHILE selected — the Layers-drawer eye path of the P2-6
    // repro. Selection deliberately persists (the drawer row stays
    // selected); only the canvas chrome must go.
    container
        .read(documentControllerProvider.notifier)
        .execute(
          const SetLayerVisibilityCommand(layerId: 'ghost', visible: false),
        );
    await tester.pump();

    expect(
      find.byType(LayerSelectionOverlay),
      findsNothing,
      reason:
          'Frame + handles over empty space promise a transform whose '
          'commit is refused for hidden layers.',
    );
    expect(find.byType(QuickCapsule), findsNothing);
    expect(container.read(selectionControllerProvider).selectedId, 'ghost');
  });

  testWidgets('drag on a hidden-but-selected layer moves nothing and writes '
      'no history: its area reads as empty canvas and the viewport pans', (
    tester,
  ) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(container, id: 'ghost', position: const Offset(100, 100));
    container.read(selectionControllerProvider.notifier).select('ghost');
    await _pumpEditor(tester, container);
    container
        .read(documentControllerProvider.notifier)
        .execute(
          const SetLayerVisibilityCommand(layerId: 'ghost', visible: false),
        );
    await tester.pump();

    final viewportBefore = container.read(viewportControllerProvider);

    // Drag starting exactly where the ghost (and its old frame) sits.
    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(130, 130)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    final ui = container.read(interactionControllerProvider);
    expect(
      ui.session,
      isNull,
      reason: 'No transform session may ever arm on a hidden layer.',
    );
    expect(ui.groupSession, isNull);
    expect(
      container.read(viewportControllerProvider).translation,
      isNot(viewportBefore.translation),
      reason:
          'A hidden layer\'s area is pointer-ineligible (§5) — the drag '
          'falls through to the viewport pan, not a ghost transform.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final ghost = container
        .read(documentControllerProvider)
        .layerById('ghost')!;
    expect(ghost.transform.position, const Offset(100, 100));

    // Zero history from the drag: the first undo must pop the HIDE
    // command (nothing landed on top of it), the second the add.
    final docCtl = container.read(documentControllerProvider.notifier);
    docCtl.undo();
    expect(
      container.read(documentControllerProvider).layerById('ghost')!.visible,
      isTrue,
      reason: 'The drag must not push any entry above the visibility toggle.',
    );
    docCtl.undo();
    expect(
      container.read(documentControllerProvider).layerById('ghost'),
      isNull,
    );
  });

  test('every single-layer start path refuses a hidden layer — the start '
      'rule matches the commit rule (invariant 5)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(
      container,
      id: 'hid',
      position: const Offset(100, 100),
      visible: false,
    );
    final hid = container.read(documentControllerProvider).layerById('hid')!;
    final ctl = container.read(interactionControllerProvider.notifier);

    ctl.startMove(layer: hid, pointer: const Offset(130, 130));
    expect(container.read(interactionControllerProvider).session, isNull);

    ctl.startResize(
      layer: hid,
      handle: InteractionHandle.bottomRight,
      pointer: const Offset(160, 160),
    );
    expect(container.read(interactionControllerProvider).session, isNull);

    ctl.startRotate(layer: hid, pointer: const Offset(130, 90));
    expect(container.read(interactionControllerProvider).session, isNull);

    ctl.startGesture(layer: hid, focalPoint: const Offset(130, 130));
    expect(container.read(interactionControllerProvider).session, isNull);
  });

  testWidgets('group drag with one hidden member drives and commits only '
      'the visible members — the start set equals the commit set', (
    tester,
  ) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(
      container,
      id: 'a',
      position: const Offset(380, 380),
      size: const Size(40, 40),
    );
    _addRect(
      container,
      id: 'b',
      position: const Offset(450, 380),
      size: const Size(40, 40),
    );
    _addRect(
      container,
      id: 'h',
      position: const Offset(380, 450),
      size: const Size(40, 40),
      visible: false,
    );
    container.read(selectionModeProvider.notifier).enterMulti();
    container.read(selectionControllerProvider.notifier).selectMany([
      'a',
      'b',
      'h',
    ]);
    await _pumpEditor(tester, container);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    final ui = container.read(interactionControllerProvider);
    expect(ui.groupSession, isNotNull);
    expect(
      ui.groupSession!.initials.keys.toSet(),
      {'a', 'b'},
      reason:
          'The hidden member must be excluded at gesture START, exactly '
          'as _endGroup excludes it at commit — never driven then dropped.',
    );
    expect(ui.groupLive.containsKey('h'), isFalse);
    expect(
      ui.groupSession!.initialBounds,
      const Rect.fromLTRB(380, 380, 490, 420),
      reason: 'The frame must describe only the members the drag drives.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final doc = container.read(documentControllerProvider);
    expect(
      doc.layerById('a')!.transform.position,
      isNot(const Offset(380, 380)),
    );
    expect(
      doc.layerById('b')!.transform.position,
      isNot(const Offset(450, 380)),
    );
    expect(
      doc.layerById('h')!.transform.position,
      const Offset(380, 450),
      reason: 'The hidden member must not move — visibly or in the doc.',
    );

    // ONE composite entry for the whole gesture, containing exactly
    // the two visible members: the first undo restores both, the
    // second pops the AddLayerCommand for 'h' — proving no other
    // entry (hidden-member or otherwise) sits in between.
    final docCtl = container.read(documentControllerProvider.notifier);
    docCtl.undo();
    final undone = container.read(documentControllerProvider);
    expect(undone.layerById('a')!.transform.position, const Offset(380, 380));
    expect(undone.layerById('b')!.transform.position, const Offset(450, 380));
    expect(undone.layerById('h')!.transform.position, const Offset(380, 450));
    docCtl.undo();
    expect(container.read(documentControllerProvider).layerById('h'), isNull);
  });

  testWidgets('a group whose members are ALL hidden draws no group chrome '
      'and its old quad pans the viewport', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    _addRect(
      container,
      id: 'a',
      position: const Offset(380, 380),
      size: const Size(40, 40),
      visible: false,
    );
    _addRect(
      container,
      id: 'b',
      position: const Offset(450, 380),
      size: const Size(40, 40),
      visible: false,
    );
    container.read(selectionModeProvider.notifier).enterMulti();
    container.read(selectionControllerProvider.notifier).selectMany(['a', 'b']);
    await _pumpEditor(tester, container);

    expect(
      find.byType(GroupSelectionOverlay),
      findsNothing,
      reason:
          'Nothing the chrome could drive is visible — rendering a '
          'frame would be present-but-inert chrome (§10.3).',
    );

    final viewportBefore = container.read(viewportControllerProvider);
    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    expect(container.read(interactionControllerProvider).groupSession, isNull);
    expect(
      container.read(viewportControllerProvider).translation,
      isNot(viewportBefore.translation),
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final doc = container.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position, const Offset(380, 380));
    expect(doc.layerById('b')!.transform.position, const Offset(450, 380));
  });

  testWidgets('a visible layer underneath a hidden selection stays row-5 '
      'draggable: the absent overlay reserves no chrome quad', (tester) async {
    final container = _setup(tester);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    // Same rect on purpose: before the quad release, the hidden
    // selection's chrome quad blanket-declined select-and-move here
    // even though no overlay was left to claim the pointer.
    _addRect(
      container,
      id: 'ghost',
      position: const Offset(100, 100),
      visible: false,
    );
    _addRect(container, id: 'under', position: const Offset(100, 100));
    container.read(selectionControllerProvider.notifier).select('ghost');
    await _pumpEditor(tester, container);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(130, 130)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    expect(
      container.read(selectionControllerProvider).selectedId,
      'under',
      reason: 'Row 5 must claim the visible layer under the hidden selection.',
    );
    expect(
      container.read(interactionControllerProvider).session?.layerId,
      'under',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final doc = container.read(documentControllerProvider);
    expect(
      doc.layerById('under')!.transform.position,
      isNot(const Offset(100, 100)),
    );
    expect(doc.layerById('ghost')!.transform.position, const Offset(100, 100));
  });
}
