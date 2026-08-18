// Pins the interaction contract's §2 preview channel + §3 gesture
// fencing for the image-cluster slider migration (tb2 2/16,
// docs/editor-interaction-contract-2026-07.md):
//
//   * while a slider drags, the COMMITTED document must not change
//     (commit version frozen; the preview lives on liveOverlay);
//   * release commits exactly ONE non-live command — one history
//     entry per drag, structurally (a second drag is a second
//     entry; a single undo restores the full pre-drag value);
//   * pointer-CANCEL commits the last previewed value too (§7 —
//     app pause cancels touches; what the user saw must persist);
//   * preset chips remain discrete non-live commands: two taps are
//     two undo entries.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/background_fill.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_look_body.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_border_body.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/paint/presentation/bodies/paint_size_entry.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_gesture_surface.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_size_body.dart';
import 'package:canvas_engine/features/editor/shape/presentation/shape_style_body.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/widgets/preset_slider_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ImageLayer makeImageLayer() {
    return ImageLayer(
      id: 'img1',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(200, 200),
      ),
      source: const ImageSource.asset('stub.png'),
    );
  }

  ProviderContainer makeContainer(ImageLayer layer) {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pumpBody(
    WidgetTester tester,
    ProviderContainer container,
    Widget body,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: body)),
        ),
      ),
    );
  }

  ImageLayer committedLayer(ProviderContainer c) =>
      c.read(documentControllerProvider).layerById('img1') as ImageLayer;

  testWidgets(
    'adjust-brightness drag: committed doc frozen mid-drag, one entry '
    'per drag, undo restores pre-drag value',
    (tester) async {
      final layer = makeImageLayer();
      final container = makeContainer(layer);
      await pumpBody(tester, container, ImageLookBody(layer: layer));

      await tester.tap(find.text('Adjust precisely'));
      await tester.pumpAndSettle();

      final versionBefore = container.read(documentCommitVersionProvider);
      final slider = find.byType(Slider).first; // brightness

      // Drag 1 — stream several ticks, verifying the committed doc
      // never moves while the overlay carries the preview.
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(
        container.read(documentCommitVersionProvider),
        versionBefore,
        reason: 'no committed writes while the slider streams (§2)',
      );
      expect(
        container.read(liveOverlayProvider).replacements.containsKey('img1'),
        isTrue,
        reason: 'preview must be staged on the live overlay',
      );
      expect(
        committedLayer(container).adjustments.brightness,
        0,
        reason: 'committed brightness untouched mid-drag',
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(container.read(documentCommitVersionProvider), versionBefore);

      await gesture.up();
      await tester.pump();

      expect(
        container.read(documentCommitVersionProvider),
        versionBefore + 1,
        reason: 'release commits exactly one command',
      );
      expect(
        container.read(liveOverlayProvider).isEmpty,
        isTrue,
        reason: 'overlay cleared on commit (clear-then-execute)',
      );
      final afterFirstDrag = committedLayer(container).adjustments.brightness;
      expect(afterFirstDrag, greaterThan(0));

      // Drag 2 — a separate gesture is a separate entry (structural
      // fencing; live:false commands never merge).
      final gesture2 = await tester.startGesture(tester.getCenter(slider));
      await gesture2.moveBy(const Offset(-40, 0));
      await tester.pump();
      await gesture2.up();
      await tester.pump();
      expect(
        container.read(documentCommitVersionProvider),
        versionBefore + 2,
        reason: 'second drag is its own history entry',
      );

      // One undo per drag, restoring each pre-drag value in turn.
      container.read(documentControllerProvider.notifier).undo();
      expect(committedLayer(container).adjustments.brightness, afterFirstDrag);
      container.read(documentControllerProvider.notifier).undo();
      expect(committedLayer(container).adjustments.brightness, 0);
    },
  );

  testWidgets('border-width drag commits once on release; pointer-cancel still '
      'commits the last previewed value', (tester) async {
    final layer = makeImageLayer();
    final container = makeContainer(layer);
    await pumpBody(tester, container, ImageBorderBody(layer: layer));

    // The colour grid above this disclosure is tall and its run gap is
    // now derived from the available width, so its height is not a
    // constant the test can assume. Scroll the header into view before
    // tapping it rather than trusting it to land on-screen.
    await tester.ensureVisible(find.text('Adjust precisely'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust precisely'));
    await tester.pumpAndSettle();

    final versionBefore = container.read(documentCommitVersionProvider);
    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    // The colour section above the disclosure is tall — bring the
    // slider on-screen so the gesture actually lands on it.
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();

    // Full drag → one entry.
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    expect(container.read(documentCommitVersionProvider), versionBefore);
    expect(
      committedLayer(container).borderWidth,
      0,
      reason: 'committed width untouched mid-drag',
    );
    await gesture.up();
    await tester.pump();
    expect(container.read(documentCommitVersionProvider), versionBefore + 1);
    final afterDrag = committedLayer(container).borderWidth;
    expect(afterDrag, greaterThan(0));

    // Cancelled drag → the last previewed value still commits
    // (§7: what the user saw must persist through interruption).
    final gesture2 = await tester.startGesture(tester.getCenter(slider));
    await gesture2.moveBy(const Offset(60, 0));
    await tester.pump();
    final previewed =
        (container.read(liveOverlayProvider).replacements['img1'] as ImageLayer)
            .borderWidth;
    await gesture2.cancel();
    await tester.pump();
    expect(
      container.read(documentCommitVersionProvider),
      versionBefore + 2,
      reason: 'pointer-cancel commits, never discards',
    );
    expect(committedLayer(container).borderWidth, previewed);
    expect(container.read(liveOverlayProvider).isEmpty, isTrue);

    // Undo unwinds one drag at a time.
    container.read(documentControllerProvider.notifier).undo();
    expect(committedLayer(container).borderWidth, afterDrag);
    container.read(documentControllerProvider.notifier).undo();
    expect(committedLayer(container).borderWidth, 0);
  });

  // tb4 1/14: the Adjust preset chips died with the Look merge. The
  // preset row is the FILTER row now — same §3 obligation, so the
  // pin moves rather than disappearing.
  testWidgets('look preset taps stay discrete non-live entries', (
    tester,
  ) async {
    final layer = makeImageLayer();
    final container = makeContainer(layer);
    await pumpBody(tester, container, ImageLookBody(layer: layer));
    // The chips decode the layer's (missing) file for their previews.
    tester.takeException();

    final versionBefore = container.read(documentCommitVersionProvider);
    await tester.tap(find.text('Warm'));
    await tester.pump();
    await tester.tap(find.text('Mono'));
    await tester.pump();

    expect(
      container.read(documentCommitVersionProvider),
      versionBefore + 2,
      reason: 'two discrete taps are two history entries (§3)',
    );
    expect(committedLayer(container).filterPreset, ImageFilterPreset.mono);
    container.read(documentControllerProvider.notifier).undo();
    expect(committedLayer(container).filterPreset, ImageFilterPreset.warm);
    container.read(documentControllerProvider.notifier).undo();
    expect(committedLayer(container).filterPreset, ImageFilterPreset.none);
  });

  testWidgets('the fine-tune sliders never reset the preset row', (
    tester,
  ) async {
    final layer = makeImageLayer();
    final container = makeContainer(layer);
    await pumpBody(tester, container, ImageLookBody(layer: layer));
    tester.takeException();

    await tester.tap(find.text('Mono'));
    await tester.pump();
    await tester.tap(find.text('Adjust precisely'));
    await tester.pumpAndSettle();

    final slider = find.byType(Slider).first; // brightness
    await tester.drag(slider, const Offset(60, 0));
    await tester.pump();

    final after = committedLayer(container);
    expect(
      after.filterPreset,
      ImageFilterPreset.mono,
      reason:
          'the two channels compose; fine-tuning never clears the '
          'chosen preset',
    );
    expect(after.adjustments.brightness, isNot(0));
  });

  // ─── tb2 3/16 additions ───────────────────────────────────────────

  testWidgets('shape fill-opacity drag on a GRADIENT fill previews and commits '
      'without clearing the gradient', (tester) async {
    const gradient = LinearGradientBackground(
      startColor: Color(0xFFFF0000),
      endColor: Color(0xFF0000FF),
    );
    final layer = ShapeLayer(
      id: 'shape1',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(200, 200),
      ),
      kind: ShapeKind.rectangle,
      fill: gradient,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    await pumpBody(tester, container, ShapeStyleBody(layer: layer));

    ShapeLayer committed() =>
        container.read(documentControllerProvider).layerById('shape1')
            as ShapeLayer;

    final versionBefore = container.read(documentCommitVersionProvider);
    // Keyed, not positional: on a gradient fill the Solid|Gradient
    // section renders its own angle slider above this row (tb4 2/14).
    final slider = find.descendant(
      of: find.byKey(const ValueKey('shape-fill-opacity')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(container.read(documentCommitVersionProvider), versionBefore);
    final staged =
        container.read(liveOverlayProvider).replacements['shape1']
            as ShapeLayer;
    expect(
      staged.fill,
      gradient,
      reason: 'overlay preview must keep the gradient descriptor',
    );
    expect(staged.fillOpacity, lessThan(1));
    expect(committed().fillOpacity, 1);

    await gesture.up();
    await tester.pump();
    expect(container.read(documentCommitVersionProvider), versionBefore + 1);
    expect(committed().fillOpacity, lessThan(1));
    expect(
      committed().fill,
      gradient,
      reason:
          'an opacity-only commit must not clear the gradient '
          '(SetShapeFillCommand._targetFill semantics)',
    );
  });

  testWidgets('paint width drag: overlay preview + one commit when a layer is '
      'selected; session-only when nothing is selected', (tester) async {
    final layer = PaintLayer(
      id: 'p1',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(200, 100),
      ),
      kind: PaintKind.line,
      normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    container.read(selectionControllerProvider.notifier).select('p1');
    await pumpBody(
      tester,
      container,
      PaintSizeEntryBody(view: container.read(paintStyleViewProvider)),
    );

    PaintLayer committed() =>
        container.read(documentControllerProvider).layerById('p1')
            as PaintLayer;

    await tester.tap(find.text('Adjust precisely'));
    await tester.pumpAndSettle();

    final versionBefore = container.read(documentCommitVersionProvider);
    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(container.read(documentCommitVersionProvider), versionBefore);
    final staged =
        container.read(liveOverlayProvider).replacements['p1'] as PaintLayer;
    expect(committed().strokeWidth, 6, reason: 'committed frozen mid-drag');

    await gesture.up();
    await tester.pump();
    expect(container.read(documentCommitVersionProvider), versionBefore + 1);
    expect(committed().strokeWidth, staged.strokeWidth);
    expect(container.read(liveOverlayProvider).isEmpty, isTrue);
    expect(
      container.read(paintToolControllerProvider).strokeWidth,
      6,
      reason: 'restyling a layer must not reconfigure the next stroke',
    );

    // No selection → session-only: zero document writes.
    container.read(selectionControllerProvider.notifier).clear();
    await tester.pump();
    final versionAfterFirst = container.read(documentCommitVersionProvider);
    final gesture2 = await tester.startGesture(tester.getCenter(slider));
    await gesture2.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture2.up();
    await tester.pump();
    expect(
      container.read(documentCommitVersionProvider),
      versionAfterFirst,
      reason: 'unselected drags never touch the document',
    );
    expect(
      container.read(paintToolControllerProvider).strokeWidth,
      isNot(staged.strokeWidth),
      reason: 'session default still updates',
    );
  });

  // The other half of §2: the dock is a CONSUMER of the preview. A
  // host that reads the style view once (a snapshot) renders a Size
  // panel whose slider thumb and stroke hero stay parked at the
  // pre-gesture width while the canvas underneath already moved. Wire
  // the body the way the real dock does — reactively — and pin that
  // both follow the staged value before any commit.
  testWidgets('paint Size tracks the STAGED width live: slider thumb and '
      'stroke hero move before the commit', (tester) async {
    final layer = PaintLayer(
      id: 'p1',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(200, 100),
      ),
      kind: PaintKind.line,
      normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    container.read(selectionControllerProvider.notifier).select('p1');

    // Deliberately NOT `container.read(paintStyleViewProvider)` — the
    // snapshot is exactly the bug this test exists to catch.
    await pumpBody(
      tester,
      container,
      Consumer(
        builder: (context, ref, _) =>
            PaintSizeEntryBody(view: ref.watch(paintStyleViewProvider)),
      ),
    );

    PaintLayer committed() =>
        container.read(documentControllerProvider).layerById('p1')
            as PaintLayer;
    double stagedWidth() =>
        (container.read(liveOverlayProvider).replacements['p1'] as PaintLayer)
            .strokeWidth;

    await tester.tap(find.text('Adjust precisely'));
    await tester.pumpAndSettle();

    final versionBefore = container.read(documentCommitVersionProvider);
    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    expect(tester.widget<Slider>(slider).value, 6);
    expect(tester.widget<StrokeHero>(find.byType(StrokeHero)).width, 6);

    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();

    final staged = stagedWidth();
    expect(staged, greaterThan(6), reason: 'the drag must have moved');
    expect(
      tester.widget<Slider>(slider).value,
      closeTo(staged, 0.001),
      reason: 'the thumb reads the staged layer, not the committed one',
    );
    expect(
      tester.widget<StrokeHero>(find.byType(StrokeHero)).width,
      closeTo(staged, 0.001),
      reason: 'the hero previews the width the canvas is already drawing',
    );
    expect(committed().strokeWidth, 6, reason: 'committed frozen mid-drag');
    expect(container.read(documentCommitVersionProvider), versionBefore);

    // A second tick keeps tracking — one frozen frame would be enough
    // to make the panel feel dead.
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final staged2 = stagedWidth();
    expect(staged2, greaterThan(staged));
    expect(tester.widget<Slider>(slider).value, closeTo(staged2, 0.001));
    expect(container.read(documentCommitVersionProvider), versionBefore);

    await gesture.up();
    await tester.pump();
    expect(container.read(documentCommitVersionProvider), versionBefore + 1);
    expect(committed().strokeWidth, closeTo(staged2, 0.001));
    expect(container.read(liveOverlayProvider).isEmpty, isTrue);
    expect(
      tester.widget<Slider>(slider).value,
      closeTo(staged2, 0.001),
      reason: 'no flash-back frame between overlay clear and commit',
    );
  });

  testWidgets('PresetSliderControl commits once per drag, including on '
      'pointer-cancel', (tester) async {
    final commits = <double>[];
    final previews = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PresetSliderControl(
            value: 20,
            min: 0,
            max: 100,
            presets: const [10, 50],
            formatValue: (v) => '${v.round()}',
            onPreview: previews.add,
            onCommit: commits.add,
          ),
        ),
      ),
    );

    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(previews, isNotEmpty, reason: 'live panels receive drag ticks');
    expect(commits, isEmpty, reason: 'drag is preview-only until release');
    await gesture.up();
    await tester.pump();
    expect(commits.length, 1, reason: 'exactly one commit per drag');

    final gesture2 = await tester.startGesture(tester.getCenter(slider));
    await gesture2.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture2.cancel();
    await tester.pump();
    expect(
      commits.length,
      2,
      reason: 'pointer-cancel still commits the in-flight value (§7)',
    );
  });

  testWidgets(
    'eraser sweep over 3 strokes stages removals live and commits ONE '
    'undo entry restoring all three',
    (tester) async {
      PaintLayer stroke(String id, double x) => PaintLayer(
        id: id,
        transform: LayerTransform(
          position: Offset(x, 100),
          size: const Size(100, 100),
        ),
        kind: PaintKind.line,
        normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final docCtrl = container.read(documentControllerProvider.notifier);
      docCtrl.newDocument(width: 800, height: 800);
      docCtrl.execute(AddLayerCommand(stroke('a', 100)));
      docCtrl.execute(AddLayerCommand(stroke('b', 250)));
      docCtrl.execute(AddLayerCommand(stroke('c', 450)));
      container
          .read(paintToolControllerProvider.notifier)
          .selectTool(PaintToolType.eraser);

      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 800,
                child: Stack(
                  children: [PaintGestureSurface(docSize: Size(800, 800))],
                ),
              ),
            ),
          ),
        ),
      );

      int paintLayerCount() => container
          .read(documentControllerProvider)
          .layers
          .whereType<PaintLayer>()
          .length;

      final versionBefore = container.read(documentCommitVersionProvider);
      final gesture = await tester.startGesture(const Offset(150, 150));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(50, 0));
        await tester.pump();
      }
      // Mid-sweep: all three hits staged on the overlay, committed
      // document untouched.
      expect(container.read(documentCommitVersionProvider), versionBefore);
      expect(paintLayerCount(), 3, reason: 'committed doc frozen mid-sweep');
      expect(
        container.read(liveOverlayProvider).removals,
        {'a', 'b', 'c'},
        reason: 'sweep hits stage on the overlay removals channel',
      );

      await gesture.up();
      await tester.pump();
      expect(
        container.read(documentCommitVersionProvider),
        versionBefore + 1,
        reason: 'whole sweep commits as ONE history entry (§3)',
      );
      expect(paintLayerCount(), 0);
      expect(container.read(liveOverlayProvider).isEmpty, isTrue);

      container.read(documentControllerProvider.notifier).undo();
      expect(
        paintLayerCount(),
        3,
        reason: 'a single undo restores every stroke the sweep took',
      );
    },
  );
}
