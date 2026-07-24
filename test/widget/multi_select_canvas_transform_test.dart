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

/// Multi-select gesture-routing parity with single-select under the
/// interaction contract (§5 rows 4/6/7, tb3 1/7).
///
/// Spec: the group's chrome quad — its AABB plus the drawn handle
/// outset — is the transform surface:
///
///   * 1 finger drag ON the quad   → moves the whole group
///   * 2 fingers, first ON the quad → scale / rotate the group
///   * 1 finger drag OFF the quad  → pans the viewport, selection stays
///   * 2 fingers OFF the quad      → viewport pinch, group untouched
///   * pause-then-drag ON the quad → still moves (claim-on-down)
///
/// Direct handle interactions and per-layer toggling on tap are
/// covered by other test files.

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

Offset _toScreen(ProviderContainer container, Offset canvas) {
  final vp = container.read(viewportControllerProvider);
  return canvas * vp.scale + vp.translation;
}

void main() {
  // Group AABB spans canvas (380, 380) → (490, 420) in every test.

  testWidgets('one-finger drag on the group quad moves the whole group', (
    tester,
  ) async {
    final container = _setup(tester);
    await _pumpEditorWithGroup(tester, container);

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
    expect(
      ui.groupSession,
      isNotNull,
      reason: 'One-finger on-quad drag must run a GROUP session.',
    );
    expect(ui.groupLive.length, 2);
    // Both layers must have moved relative to their original
    // positions.
    expect(ui.groupLive['a']!.position, isNot(const Offset(380, 380)));
    expect(ui.groupLive['b']!.position, isNot(const Offset(450, 380)));

    final viewportAfter = container.read(viewportControllerProvider);
    expect(
      viewportAfter.translation,
      viewportBefore.translation,
      reason: 'Viewport must NOT pan while the group is being dragged.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('one-finger drag off the group quad pans the viewport and '
      'keeps the selection (contract §5 row 7)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithGroup(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);

    final gesture = await tester.startGesture(const Offset(80, 80));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();

    final ui = container.read(interactionControllerProvider);
    expect(
      ui.groupSession,
      isNull,
      reason: 'Off-quad drag must NOT start a group session.',
    );
    final viewportDuring = container.read(viewportControllerProvider);
    expect(
      viewportDuring.translation,
      isNot(viewportBefore.translation),
      reason: 'Off-quad drag must pan the viewport.',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // Selection and mode survive the pan.
    expect(container.read(selectionModeProvider), SelectionMode.multi);
    expect(
      container.read(selectionControllerProvider).selectedIds,
      unorderedEquals(['a', 'b']),
    );
    final a = container.read(documentControllerProvider).layerById('a')!;
    expect(a.transform.position, const Offset(380, 380));
  });

  testWidgets('two-finger pinch with the first finger on the group quad '
      'transforms the group (viewport stays put)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithGroup(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);
    // First finger ON the quad (inside layer a); the second finger may
    // land anywhere — pinching a small group never requires both
    // fingers inside its bounds.
    final p1 = _toScreen(container, const Offset(400, 400));
    final p2 = _toScreen(container, const Offset(650, 400));

    final f1 = await tester.startGesture(p1, pointer: 51);
    await tester.pump();
    final f2 = await tester.startGesture(p2, pointer: 52);
    await tester.pump();
    final session = container.read(interactionControllerProvider).groupSession;
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
  });

  testWidgets('two-finger pinch entirely off the group zooms the viewport '
      'and leaves the group untouched (contract §5 row 6)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithGroup(tester, container);

    final viewportBefore = container.read(viewportControllerProvider);
    final centre = _toScreen(container, const Offset(435, 400));
    final p1 = centre + const Offset(-220, 0);
    final p2 = centre + const Offset(220, 0);

    final f1 = await tester.startGesture(p1, pointer: 51);
    await tester.pump();
    final f2 = await tester.startGesture(p2, pointer: 52);
    await tester.pump();

    await f1.moveBy(const Offset(-100, 0));
    await f2.moveBy(const Offset(100, 0));
    await tester.pump();

    final ui = container.read(interactionControllerProvider);
    expect(
      ui.groupSession,
      isNull,
      reason: 'Off-quad pinch must NOT start a group session.',
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

    // Document transforms untouched; selection intact.
    final a = container.read(documentControllerProvider).layerById('a')!;
    final b = container.read(documentControllerProvider).layerById('b')!;
    expect(a.transform.size, const Size(40, 40));
    expect(b.transform.size, const Size(40, 40));
    expect(
      container.read(selectionControllerProvider).selectedIds,
      unorderedEquals(['a', 'b']),
    );
  });

  testWidgets('pause-then-drag on the group quad still moves the group '
      '(claim-on-down beats the long-press recogniser)', (tester) async {
    final container = _setup(tester);
    await _pumpEditorWithGroup(tester, container);

    final gesture = await tester.startGesture(
      _toScreen(container, const Offset(400, 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();

    final ui = container.read(interactionControllerProvider);
    expect(
      ui.groupSession,
      isNotNull,
      reason:
          'Pause-then-drag on the quad must stay a group '
          'session — long-press / tap recognisers must NOT steal '
          'the gesture.',
    );
    expect(ui.groupLive['a']!.position, isNot(const Offset(380, 380)));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  });
}
