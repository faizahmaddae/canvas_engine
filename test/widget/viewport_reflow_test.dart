import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_session.dart';
import 'package:canvas_engine/features/editor/application/project_viewport_store.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A tool panel opening / closing / switching reflows the on-screen canvas
// pane. We reproduce that against the real [EditorCanvas] by pumping it in a
// fixed-width [SizedBox] and changing only its HEIGHT between pumps — exactly
// the constraint change the LayoutBuilder-gated fit reacts to. The
// EditorCanvas element identity is preserved across pumps (same widget type
// + position), so its fit / user-adjusted lifecycle carries over.
//
// Assertions are on the resulting viewport transform (user-visible), not on
// internal wiring.
void main() {
  const paneWidth = 400.0;

  Future<void> pumpPane(
    WidgetTester tester,
    ProviderContainer container,
    double height,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: paneWidth,
                height: height,
                child: const EditorCanvas(),
              ),
            ),
          ),
        ),
      ),
    );
    // Let the post-frame fit / preserve callback run and apply.
    await tester.pump();
    await tester.pump();
  }

  void seedDoc(ProviderContainer c, {double w = 400, double h = 1200}) {
    // Doc taller than the pane so fit is height-bound → a pane-height change
    // moves the fit scale, which makes an accidental re-fit detectable.
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: w, height: h);
  }

  void configureView(WidgetTester tester) {
    tester.view.physicalSize = const Size(paneWidth, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('manual zoom survives a panel-open reflow (scale preserved)', (
    tester,
  ) async {
    configureView(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    seedDoc(container);
    final vc = container.read(viewportControllerProvider.notifier);

    await pumpPane(tester, container, 800);
    final fitScale = container.read(viewportControllerProvider).scale;
    expect(vc.userAdjusted, isFalse);

    // User zooms in (a +/- button or pinch — a genuine manual adjust).
    vc.zoomBy(2.0, const Offset(200, 400));
    final zoomedScale = container.read(viewportControllerProvider).scale;
    expect(zoomedScale, closeTo(fitScale * 2, 1e-9));
    expect(vc.userAdjusted, isTrue);

    // A tool panel opens → the canvas pane gets shorter.
    await pumpPane(tester, container, 500);

    final after = container.read(viewportControllerProvider).scale;
    // Zoom preserved, NOT snapped back to the (smaller) fit for the new pane.
    expect(after, closeTo(zoomedScale, 1e-6));
    expect(after, greaterThan(fitScale)); // definitively not re-fit
    expect(vc.userAdjusted, isTrue);
  });

  testWidgets('switching panels then closing keeps the manual zoom', (
    tester,
  ) async {
    configureView(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    seedDoc(container);
    final vc = container.read(viewportControllerProvider.notifier);

    await pumpPane(tester, container, 800);
    vc.zoomBy(2.0, const Offset(200, 400));
    final before = container.read(viewportControllerProvider);
    // Canvas point under the pane centre before the panel dance.
    const centre = Offset(paneWidth / 2, 800 / 2);
    final focalBefore = (centre - before.translation) / before.scale;

    await pumpPane(tester, container, 520); // open panel A
    await pumpPane(tester, container, 540); // switch to panel B
    await pumpPane(tester, container, 800); // close the panel — back to 800

    final after = container.read(viewportControllerProvider);
    expect(after.scale, closeTo(before.scale, 1e-6));
    expect(vc.userAdjusted, isTrue);
    // Returning to the ORIGINAL pane must land back on the ORIGINAL
    // translation — no focal drift accumulated across the three reflows.
    expect(after.translation.dx, closeTo(before.translation.dx, 1e-3));
    expect(after.translation.dy, closeTo(before.translation.dy, 1e-3));
    final focalAfter = (centre - after.translation) / after.scale;
    expect(focalAfter.dx, closeTo(focalBefore.dx, 1e-3));
    expect(focalAfter.dy, closeTo(focalBefore.dy, 1e-3));
  });

  testWidgets('without manual adjustment a pane reflow still re-fits', (
    tester,
  ) async {
    configureView(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    seedDoc(container);
    final vc = container.read(viewportControllerProvider.notifier);

    await pumpPane(tester, container, 800);
    final fit800 = container.read(viewportControllerProvider).scale;
    expect(vc.userAdjusted, isFalse);

    await pumpPane(tester, container, 500); // shorter pane, no user adjust
    final fit500 = container.read(viewportControllerProvider).scale;
    // Height-bound fit shrinks with the pane → genuinely re-fitted, and the
    // viewport is still not treated as user-adjusted.
    expect(fit500, lessThan(fit800));
    expect(vc.userAdjusted, isFalse);
  });

  testWidgets('a document-dimension change re-fits and clears manual adjust', (
    tester,
  ) async {
    configureView(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final doc = container.read(documentControllerProvider.notifier);
    seedDoc(container);
    final vc = container.read(viewportControllerProvider.notifier);

    await pumpPane(tester, container, 800);
    vc.zoomBy(2.0, const Offset(200, 400));
    expect(vc.userAdjusted, isTrue);

    // Load a different-sized document (identity + dimensions change).
    doc.newDocument(width: 400, height: 400);
    await tester.pump();
    await tester.pump();

    expect(
      vc.userAdjusted,
      isFalse,
      reason: 'a new document must reset the user-adjusted state',
    );
    // Re-fitted to the new, near-square document (fills the pane far more
    // than the previous height-bound 1200-tall fit).
    final s = container.read(viewportControllerProvider).scale;
    expect(s, greaterThan(0.5));
  });

  testWidgets('explicit Fit after a preserved reflow refits the current pane', (
    tester,
  ) async {
    configureView(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    seedDoc(container);
    final vc = container.read(viewportControllerProvider.notifier);

    await pumpPane(tester, container, 800);
    vc.zoomBy(2.0, const Offset(200, 400));
    await pumpPane(tester, container, 500); // panel opens, zoom preserved
    expect(vc.userAdjusted, isTrue);

    // User taps "Fit to screen" (app-bar action → refit()).
    final ok = vc.refit();
    await tester.pump();
    expect(ok, isTrue);
    expect(vc.userAdjusted, isFalse);

    // Fit must target the CURRENT 500-tall pane, not the stale 800 one.
    final refitScale = container.read(viewportControllerProvider).scale;
    final scratch = ProviderContainer();
    addTearDown(scratch.dispose);
    scratch
        .read(viewportControllerProvider.notifier)
        .fit(
          screenSize: const Size(paneWidth, 500),
          canvasSize: const Size(400, 1200),
        );
    final expected = scratch.read(viewportControllerProvider).scale;
    expect(refitScale, closeTo(expected, 1e-6));
  });

  // ---- Reopen (persistence) scenarios ------------------------------------
  // Simulate reopening a saved project by pre-seeding SharedPreferences with a
  // stored viewport entry for a projectId, then pumping a fresh EditorCanvas
  // whose session carries that projectId. _scheduleFit loads the entry and
  // decides restore-vs-fresh-fit. runAsync lets the async SharedPreferences
  // load actually resolve.

  double freshFitScale(double height) {
    final scratch = ProviderContainer();
    addTearDown(scratch.dispose);
    scratch
        .read(viewportControllerProvider.notifier)
        .fit(
          screenSize: Size(paneWidth, height),
          canvasSize: const Size(400, 1200),
        );
    return scratch.read(viewportControllerProvider).scale;
  }

  Widget canvasTree(ProviderContainer container, double height) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: paneWidth,
              height: height,
              child: const EditorCanvas(),
            ),
          ),
        ),
      ),
    );
  }

  Future<ProviderContainer> pumpReopen(
    WidgetTester tester, {
    required String projectId,
    required double height,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 400, height: 1200);
    container.read(editorSessionProvider.notifier).state = EditorSession(
      name: 'P',
      projectId: projectId,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(canvasTree(container, height));
      // Post-frame _scheduleFit awaits the async store load; give it real time.
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      await tester.pump();
    });
    return container;
  }

  Future<void> reflowTo(
    WidgetTester tester,
    ProviderContainer container,
    double height,
  ) async {
    await tester.pumpWidget(canvasTree(container, height));
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'reopening an untouched (auto-fit / legacy) saved project is not treated '
    'as adjusted and re-fits on panel open',
    (tester) async {
      configureView(tester);
      // Pre-fix 3-part legacy entry: a viewport the user never manually set.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'viewport.p-untouched': '0.34|16|100',
      });
      final container = await pumpReopen(
        tester,
        projectId: 'p-untouched',
        height: 800,
      );
      final vc = container.read(viewportControllerProvider.notifier);

      // A stored auto-fit / legacy entry is NOT a user adjustment.
      expect(
        vc.userAdjusted,
        isFalse,
        reason: 'a stored auto-fit / legacy viewport is not user-adjusted',
      );

      // Opening a tool panel (pane shrinks) must RE-FIT, not preserve.
      await reflowTo(tester, container, 500);
      final s = container.read(viewportControllerProvider).scale;
      expect(
        s,
        closeTo(freshFitScale(500), 1e-6),
        reason: 'untouched reopened project re-fits the reduced pane',
      );
    },
  );

  testWidgets(
    'reopening a manually-adjusted saved project preserves scale and focal '
    'area across a panel open',
    (tester) async {
      configureView(tester);
      // Four-field entry, adjusted=1: a genuine manual zoom the user set.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'viewport.p-manual': '1.6|20|-60|1',
      });
      final container = await pumpReopen(
        tester,
        projectId: 'p-manual',
        height: 800,
      );
      final vc = container.read(viewportControllerProvider.notifier);

      // Restored as a genuine adjustment (transform + flag).
      expect(vc.userAdjusted, isTrue);
      final restored = container.read(viewportControllerProvider);
      expect(restored.scale, closeTo(1.6, 1e-9));
      expect(restored.translation, const Offset(20, -60));

      // Canvas point under the (full) pane centre before the reflow.
      const oldCentre = Offset(paneWidth / 2, 800 / 2);
      final focalBefore = (oldCentre - restored.translation) / restored.scale;

      // Open a tool panel (pane shrinks) → preserve, not re-fit.
      await reflowTo(tester, container, 500);
      final after = container.read(viewportControllerProvider);
      expect(after.scale, closeTo(1.6, 1e-6)); // preserved, not re-fit
      expect(vc.userAdjusted, isTrue);
      // Same canvas detail now under the NEW pane centre (focal-stable).
      const newCentre = Offset(paneWidth / 2, 500 / 2);
      final focalAfter = (newCentre - after.translation) / after.scale;
      expect(focalAfter.dx, closeTo(focalBefore.dx, 1e-3));
      expect(focalAfter.dy, closeTo(focalBefore.dy, 1e-3));
      expect(after.translation.dx.isFinite, isTrue);
      expect(after.translation.dy.isFinite, isTrue);
    },
  );

  testWidgets(
    'reopening after an explicit Fit (stored adjusted=0) re-fits on panel open',
    (tester) async {
      configureView(tester);
      // The state an explicit Fit persists: a valid viewport tagged NOT
      // adjusted. Reopen must treat it as an auto-fit and re-fit the pane.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'viewport.p-fit': '0.34|16|100|0',
      });
      final container = await pumpReopen(
        tester,
        projectId: 'p-fit',
        height: 800,
      );
      expect(
        container.read(viewportControllerProvider.notifier).userAdjusted,
        isFalse,
      );
      await reflowTo(tester, container, 500);
      expect(
        container.read(viewportControllerProvider).scale,
        closeTo(freshFitScale(500), 1e-6),
      );
    },
  );

  testWidgets('the canvas persists the adjustment intent: a manual zoom stores '
      'adjusted=1, then an explicit Fit overwrites it with adjusted=0', (
    tester,
  ) async {
    configureView(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = ProjectViewportStore();
    await tester.runAsync(() async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: 400, height: 1200);
      container.read(editorSessionProvider.notifier).state =
          const EditorSession(name: 'P', projectId: 'p-rt');
      final vc = container.read(viewportControllerProvider.notifier);

      await tester.pumpWidget(canvasTree(container, 800));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();

      // Manual zoom → after the debounce, persisted as adjusted=1.
      vc.zoomBy(2.0, const Offset(200, 400));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await tester.pump();
      expect((await store.load('p-rt'))!.userAdjusted, isTrue);

      // Explicit Fit → persisted as adjusted=0, overwriting the manual
      // entry, so a later reopen re-fits (no stale manual value survives).
      vc.refit();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await tester.pump();
      expect((await store.load('p-rt'))!.userAdjusted, isFalse);
    });
  });

  // ---- Equal-transform intent-clear (F1 regression) ----------------------
  // The adjustment intent must be persisted even when explicit Fit produces
  // a viewport transform EQUAL to the current one (so the transform, on its
  // own, would not notify). Reproduced deterministically by restoring a
  // stored (T, adjusted=1) whose T is exactly the auto-fit for the pane.

  testWidgets('equal-transform Fit clears the persisted adjustment intent', (
    tester,
  ) async {
    configureView(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = ProjectViewportStore();
    await tester.runAsync(() async {
      // The exact auto-fit transform for the reopen pane (400x800 pane,
      // 400x1200 canvas). Computed via the real fit() so the reopen path
      // recomputes a bit-identical transform.
      final scratch = ProviderContainer();
      addTearDown(scratch.dispose);
      scratch
          .read(viewportControllerProvider.notifier)
          .fit(
            screenSize: const Size(paneWidth, 800),
            canvasSize: const Size(400, 1200),
          );
      final fitT = scratch.read(viewportControllerProvider);
      // Persist it as a GENUINE user adjustment whose transform == the fit.
      await store.save('p-eq', fitT, userAdjusted: true);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: 400, height: 1200);
      container.read(editorSessionProvider.notifier).state =
          const EditorSession(name: 'P', projectId: 'p-eq');
      final vc = container.read(viewportControllerProvider.notifier);

      await tester.pumpWidget(canvasTree(container, 800));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();

      // Restored as a genuine adjustment; its transform equals the fit.
      expect(vc.userAdjusted, isTrue);
      final restored = container.read(viewportControllerProvider);
      expect(restored.scale, fitT.scale);
      expect(restored.translation, fitT.translation);

      // Explicit Fit recomputes the SAME transform → an EQUAL assignment.
      final ok = vc.refit();
      expect(ok, isTrue);
      expect(vc.userAdjusted, isFalse); // cleared in memory

      // … and the cleared intent MUST be persisted even though the
      // transform did not change.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await tester.pump();
      final saved = await store.load('p-eq');
      expect(saved, isNotNull);
      expect(
        saved!.userAdjusted,
        isFalse,
        reason: 'equal-transform Fit must persist adjusted=0',
      );
    });
  });
}
