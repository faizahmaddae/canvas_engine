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

/// Phase 1: multi-select mode acceptance tests.
///
/// Behaviours under test:
///
///   * long-press on empty canvas enters multi mode (no selection
///     change beyond a clear);
///   * long-press on a layer enters multi mode and selects that
///     layer;
///   * single-tap in multi mode toggles a layer in/out;
///   * the mode stays armed — and its exit chip visible — at ANY
///     member count (0/1/2+) until an explicit exit (ux-audit P2-5:
///     the below-2 rule is unified across canvas and drawer);
///   * tap on empty canvas in multi mode exits the mode and clears;
///   * tap-cycling is suppressed while in multi mode.
void main() {
  Future<ProviderContainer> buildEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 400, height: 400);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
      ),
    );
    return container;
  }

  void addRect(
    ProviderContainer container, {
    required String id,
    required Offset position,
    required Size size,
  }) {
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ShapeLayer(
              id: id,
              transform: LayerTransform(position: position, size: size),
              kind: ShapeKind.rectangle,
            ),
          ),
        );
  }

  Offset toScreen(ProviderContainer container, Offset canvasPoint) {
    final v = container.read(viewportControllerProvider);
    return canvasPoint * v.scale + v.translation;
  }

  Future<void> tap(WidgetTester tester, Offset screen) async {
    await tester.tapAt(screen);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<void> longPress(WidgetTester tester, Offset screen) async {
    final gesture = await tester.startGesture(screen);
    // kLongPressTimeout defaults to 500ms; pump well past it.
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('multi-select mode entry', () {
    testWidgets('long-press on empty canvas enters multi mode and clears', (
      tester,
    ) async {
      final container = await buildEditor(tester);
      addRect(
        container,
        id: 'a',
        position: const Offset(50, 50),
        size: const Size(80, 80),
      );
      await tester.pump();
      // Pre-select something so we can verify "empty long-press clears".
      container.read(selectionControllerProvider.notifier).select('a');
      await tester.pump();

      // Long-press on a part of the canvas with no layer.
      final emptySpot = toScreen(container, const Offset(300, 300));
      await longPress(tester, emptySpot);

      expect(container.read(selectionModeProvider), SelectionMode.multi);
      expect(
        container.read(selectionControllerProvider).hasSelection,
        isFalse,
        reason: 'long-press on empty enters mode AND clears selection',
      );
    });

    testWidgets('long-press on a layer enters multi mode with that layer '
        'added to the selection', (tester) async {
      final container = await buildEditor(tester);
      addRect(
        container,
        id: 'a',
        position: const Offset(50, 50),
        size: const Size(80, 80),
      );
      addRect(
        container,
        id: 'b',
        position: const Offset(200, 50),
        size: const Size(80, 80),
      );
      await tester.pump();
      // Pre-select 'a' to verify long-press preserves it (additive).
      container.read(selectionControllerProvider.notifier).select('a');
      await tester.pump();

      await longPress(tester, toScreen(container, const Offset(240, 90)));

      expect(container.read(selectionModeProvider), SelectionMode.multi);
      final sel = container.read(selectionControllerProvider);
      expect(
        sel.selectedIds,
        ['a', 'b'],
        reason:
            'long-pressed layer is added; previous selection retained; '
            'long-pressed becomes primary',
      );
    });
  });

  group('multi-select mode taps', () {
    testWidgets('tap on a layer toggles it in/out; the mode and its chip '
        'survive every count (ux-audit P2-5)', (tester) async {
      final container = await buildEditor(tester);
      addRect(
        container,
        id: 'a',
        position: const Offset(50, 50),
        size: const Size(80, 80),
      );
      addRect(
        container,
        id: 'b',
        position: const Offset(200, 50),
        size: const Size(80, 80),
      );
      await tester.pump();
      final chip = find.byKey(const ValueKey('multi-select-exit-chip'));

      // Enter multi mode via empty long-press: armed at count 0 — the
      // chip (the mode's presence signal AND exit affordance) is
      // already up.
      await longPress(tester, toScreen(container, const Offset(350, 350)));
      expect(container.read(selectionModeProvider), SelectionMode.multi);
      expect(chip, findsOneWidget);

      await tap(tester, toScreen(container, const Offset(90, 90)));
      expect(container.read(selectionControllerProvider).selectedIds, ['a']);
      expect(
        container.read(selectionModeProvider),
        SelectionMode.multi,
        reason: 'reaching count 1 on the way UP must not end the mode',
      );
      expect(chip, findsOneWidget);

      await tap(tester, toScreen(container, const Offset(240, 90)));
      expect(container.read(selectionControllerProvider).selectedIds, [
        'a',
        'b',
      ]);
      expect(chip, findsOneWidget);

      // Toggle 'a' off — dropping to 1 member keeps the mode armed
      // and the chip visible: membership edits never end the mode,
      // only an explicit exit does (unified below-2 rule).
      await tap(tester, toScreen(container, const Offset(90, 90)));
      expect(
        container.read(selectionControllerProvider).selectedIds,
        ['b'],
        reason: 'tap on a selected layer toggles it out',
      );
      expect(container.read(selectionModeProvider), SelectionMode.multi);
      expect(chip, findsOneWidget);

      // Toggle 'b' off too — even at count 0 the mode stays armed and
      // visibly so; the next tap still TOGGLES (adds) rather than
      // replacing, which is what makes group-building from zero work.
      await tap(tester, toScreen(container, const Offset(240, 90)));
      expect(container.read(selectionControllerProvider).hasSelection, isFalse);
      expect(container.read(selectionModeProvider), SelectionMode.multi);
      expect(chip, findsOneWidget);

      await tap(tester, toScreen(container, const Offset(90, 90)));
      expect(
        container.read(selectionControllerProvider).selectedIds,
        ['a'],
        reason: 'armed at count 0, a layer tap toggles IN — not select',
      );
      expect(container.read(selectionModeProvider), SelectionMode.multi);
    });

    testWidgets('tap on empty canvas exits mode AND clears selection', (
      tester,
    ) async {
      final container = await buildEditor(tester);
      addRect(
        container,
        id: 'a',
        position: const Offset(50, 50),
        size: const Size(80, 80),
      );
      await tester.pump();

      await longPress(tester, toScreen(container, const Offset(90, 90)));
      expect(container.read(selectionModeProvider), SelectionMode.multi);
      expect(container.read(selectionControllerProvider).selectedIds, ['a']);

      await tap(tester, toScreen(container, const Offset(350, 350)));
      expect(
        container.read(selectionModeProvider),
        SelectionMode.single,
        reason: 'tap on empty exits multi mode',
      );
      expect(
        container.read(selectionControllerProvider).hasSelection,
        isFalse,
        reason: 'tap on empty also clears selection',
      );
      expect(
        find.byKey(const ValueKey('multi-select-exit-chip')),
        findsNothing,
        reason: 'the chip exists exactly while the mode is armed',
      );
    });
  });

  group('cycling suppression', () {
    testWidgets(
      'while in multi mode, repeated taps at the same spot do NOT cycle',
      (tester) async {
        final container = await buildEditor(tester);
        // Two overlapping rects so single-mode cycling would otherwise fire.
        addRect(
          container,
          id: 'bottom',
          position: const Offset(100, 100),
          size: const Size(200, 200),
        );
        addRect(
          container,
          id: 'top',
          position: const Offset(150, 150),
          size: const Size(100, 100),
        );
        await tester.pump();

        // Enter multi mode, then tap the overlap point twice.
        await longPress(tester, toScreen(container, const Offset(350, 350)));
        final spot = toScreen(container, const Offset(200, 200));

        await tap(tester, spot);
        // First tap toggles 'top' in.
        expect(container.read(selectionControllerProvider).selectedIds, [
          'top',
        ]);

        await tap(tester, spot);
        // Second tap on the SAME spot toggles 'top' BACK out — it does
        // NOT cycle to 'bottom'.
        expect(
          container.read(selectionControllerProvider).hasSelection,
          isFalse,
          reason: 'cycling is suppressed in multi mode',
        );
      },
    );
  });

  group('lifecycle: cancel safety', () {
    testWidgets(
      'an in-flight interaction session is cancelled when its layer is '
      'removed from the document',
      (tester) async {
        final container = await buildEditor(tester);
        addRect(
          container,
          id: 'a',
          position: const Offset(50, 50),
          size: const Size(80, 80),
        );
        await tester.pump();

        // Manually start an interaction session so we can simulate a
        // mid-gesture removal without a full pointer choreography.
        final layer = container
            .read(documentControllerProvider)
            .layerById('a')!;
        container
            .read(interactionControllerProvider.notifier)
            .startMove(layer: layer, pointer: const Offset(90, 90));
        expect(container.read(interactionControllerProvider).isActive, isTrue);

        // Remove the layer — the controller's document subscription must
        // cancel the session.
        container
            .read(documentControllerProvider.notifier)
            .execute(const RemoveLayerCommand('a'));
        await tester.pump();

        expect(
          container.read(interactionControllerProvider).isActive,
          isFalse,
          reason: 'session cancelled when active layer is removed',
        );
        expect(
          container.read(interactionControllerProvider).liveTransform,
          isNull,
        );
      },
    );

    testWidgets('cancel is idempotent', (tester) async {
      final container = await buildEditor(tester);
      // Calling cancel from a clean state must not throw and must not
      // emit a state change.
      container.read(interactionControllerProvider.notifier)
        ..cancel()
        ..cancel()
        ..cancel();
      expect(container.read(interactionControllerProvider).isActive, isFalse);
    });
  });
}
