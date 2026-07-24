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
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_adjust_body.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_border_body.dart';
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
      await pumpBody(tester, container, ImageAdjustBody(layer: layer));

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

  testWidgets('adjust preset chips stay discrete non-live entries', (
    tester,
  ) async {
    final layer = makeImageLayer();
    final container = makeContainer(layer);
    await pumpBody(tester, container, ImageAdjustBody(layer: layer));

    final versionBefore = container.read(documentCommitVersionProvider);
    await tester.tap(find.text('Pop'));
    await tester.pump();
    await tester.tap(find.text('Soft'));
    await tester.pump();

    expect(
      container.read(documentCommitVersionProvider),
      versionBefore + 2,
      reason: 'two discrete taps are two history entries (§3)',
    );
    expect(committedLayer(container).adjustments.brightness, 8);
    container.read(documentControllerProvider.notifier).undo();
    expect(committedLayer(container).adjustments.brightness, 5);
    container.read(documentControllerProvider.notifier).undo();
    expect(committedLayer(container).adjustments.brightness, 0);
  });
}
