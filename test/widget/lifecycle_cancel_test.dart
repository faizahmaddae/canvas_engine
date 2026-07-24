import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/interaction_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the lifecycle-driven gesture cancel.
///
/// `EditorCanvas` registers a `WidgetsBindingObserver` that calls
/// `interactionControllerProvider.notifier.cancel()` whenever the
/// app lifecycle leaves `resumed` (paused / inactive / hidden /
/// detached). This test exercises the *engine contract* the widget
/// hook relies on:
///
///   1. `cancel()` is idempotent — safe to call when no gesture is
///      active (the lifecycle observer fires on every focus loss,
///      most of which happen with no active gesture).
///   2. After cancel the live session is gone and no transform
///      command was committed to the history (a half-finished
///      gesture must never enter the undo stack).
///   3. The selection is untouched — losing focus doesn't deselect.
void main() {
  ShapeLayer addRect(ProviderContainer c, {required String id}) {
    final layer = ShapeLayer(
      id: id,
      transform: const LayerTransform(
        position: Offset(100, 100),
        size: Size(120, 120),
      ),
      kind: ShapeKind.rectangle,
    );
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
    return layer;
  }

  group('lifecycle cancel — engine contract', () {
    test('cancel() is a no-op when no gesture is active', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 800, height: 800);
      // Capture initial state object identity.
      final before = c.read(interactionControllerProvider);
      c.read(interactionControllerProvider.notifier).cancel();
      final after = c.read(interactionControllerProvider);
      expect(after.isActive, isFalse);
      // No-op short-circuit: state instance must be unchanged so
      // listeners (overlay rebuilds, snap-guide painters) don't
      // churn on every focus loss.
      expect(
        identical(before, after),
        isTrue,
        reason: 'cancel() must not allocate when nothing is active',
      );
    });

    test(
      'cancel() during an active move drops the session without committing',
      () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        c
            .read(documentControllerProvider.notifier)
            .newDocument(width: 800, height: 800);
        final layer = addRect(c, id: 'r');
        // Snapshot history BEFORE the gesture.
        final docCtrl = c.read(documentControllerProvider.notifier);
        final canUndoBefore = docCtrl.canUndo; // true: AddLayerCommand
        final docBefore = c.read(documentControllerProvider);

        // Begin a move and push a few frames forward so liveTransform
        // diverges from the layer's committed transform.
        final ic = c.read(interactionControllerProvider.notifier);
        ic.startMove(layer: layer, pointer: const Offset(160, 160));
        ic.update(const Offset(220, 200));
        expect(c.read(interactionControllerProvider).isActive, isTrue);

        // Simulate the lifecycle observer firing (paused / hidden / …).
        ic.cancel();

        // Session is gone, no live transform.
        final s = c.read(interactionControllerProvider);
        expect(s.isActive, isFalse);
        expect(s.liveTransform, isNull);
        // Document is bit-identical to pre-gesture state — the move
        // never reached the history stack.
        expect(c.read(documentControllerProvider), same(docBefore));
        expect(docCtrl.canUndo, canUndoBefore);
      },
    );
  });

  group('lifecycle cancel — widget binding hook', () {
    // The InteractionController itself registers an
    // [AppLifecycleListener] in `build()`; these tests exercise that
    // wiring end-to-end through the test binding so a future refactor
    // that drops the listener (or wires it to the wrong state set)
    // fails loudly.
    //
    // [AppLifecycleListener] enforces the documented Flutter
    // transition table (e.g. you can only reach `paused` via
    // `inactive` → `hidden`), and the binding's lifecycle state
    // persists across `tester.binding.handleAppLifecycleStateChanged`
    // calls. We therefore split the four "leaving" states into
    // separate `testWidgets` cases — each gets a fresh binding and
    // walks the documented predecessor chain to reach its target.
    Future<void> runCancelOn(
      WidgetTester tester,
      String label,
      List<AppLifecycleState> chain,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: 800, height: 800);
      final layer = addRect(container, id: 'r-$label');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );

      final ic = container.read(interactionControllerProvider.notifier);
      ic.startMove(layer: layer, pointer: const Offset(160, 160));
      ic.update(const Offset(220, 200));
      expect(
        container.read(interactionControllerProvider).isActive,
        isTrue,
        reason: 'precondition for $label',
      );

      for (final s in chain) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump();

      expect(
        container.read(interactionControllerProvider).isActive,
        isFalse,
        reason: 'reaching $label must cancel the active gesture',
      );
      expect(
        container.read(interactionControllerProvider).liveTransform,
        isNull,
      );
    }

    testWidgets('inactive cancels an active gesture', (tester) async {
      await runCancelOn(tester, 'inactive', [AppLifecycleState.inactive]);
    });
    testWidgets('hidden cancels an active gesture', (tester) async {
      await runCancelOn(tester, 'hidden', [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
      ]);
    });
    testWidgets('paused cancels an active gesture', (tester) async {
      await runCancelOn(tester, 'paused', [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
    });
    testWidgets('detached cancels an active gesture', (tester) async {
      await runCancelOn(tester, 'detached', [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]);
    });

    testWidgets('resumed does NOT cancel an active gesture', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: 800, height: 800);
      final layer = addRect(container, id: 'r-resumed');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );

      final ic = container.read(interactionControllerProvider.notifier);
      ic.startMove(layer: layer, pointer: const Offset(160, 160));
      ic.update(const Offset(220, 200));
      expect(container.read(interactionControllerProvider).isActive, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Resumed is the "everything's fine" signal — the gesture must
      // survive it untouched, otherwise a foregrounded app would lose
      // the user's in-progress drag for no reason.
      expect(container.read(interactionControllerProvider).isActive, isTrue);
    });
  });
}
