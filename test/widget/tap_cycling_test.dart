import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tap-cycling acceptance tests.
///
/// When multiple eligible layers overlap at the same point, repeated
/// taps at (approximately) the same screen position cycle through them
/// in z-order top → bottom. Moving the tap to a meaningfully different
/// spot resets the cycle. Hidden / locked layers are skipped.
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
        child: const MaterialApp(
          home: Scaffold(body: EditorCanvas()),
        ),
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
    container.read(documentControllerProvider.notifier).execute(
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
    // Long enough for the gesture arena and the double-tap timer to
    // resolve so the next tap is treated as a fresh sequence — see
    // overlapping_selection_test.dart for the same pattern.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('repeated taps cycle through three overlapping layers '
      'top→middle→bottom→top', (tester) async {
    final container = await buildEditor(tester);

    // Three concentric rectangles, all containing canvas point (200, 200).
    addRect(container,
        id: 'bottom',
        position: const Offset(100, 100),
        size: const Size(200, 200));
    addRect(container,
        id: 'middle',
        position: const Offset(125, 125),
        size: const Size(150, 150));
    addRect(container,
        id: 'top',
        position: const Offset(150, 150),
        size: const Size(100, 100));

    await tester.pump();
    await tester.pump();

    final spot = toScreen(container, const Offset(200, 200));

    await tap(tester, spot);
    expect(container.read(selectionControllerProvider).selectedId, 'top',
        reason: 'first tap selects topmost');

    await tap(tester, spot);
    expect(container.read(selectionControllerProvider).selectedId, 'middle',
        reason: 'second tap cycles down to middle');

    await tap(tester, spot);
    expect(container.read(selectionControllerProvider).selectedId, 'bottom',
        reason: 'third tap cycles down to bottom');

    await tap(tester, spot);
    expect(container.read(selectionControllerProvider).selectedId, 'top',
        reason: 'fourth tap wraps back to topmost');
  });

  testWidgets('moving the tap to a new spot resets the cycle to topmost',
      (tester) async {
    final container = await buildEditor(tester);
    addRect(container,
        id: 'bottom',
        position: const Offset(100, 100),
        size: const Size(200, 200));
    addRect(container,
        id: 'top',
        position: const Offset(150, 150),
        size: const Size(100, 100));
    await tester.pump();
    await tester.pump();

    final spotA = toScreen(container, const Offset(200, 200));

    await tap(tester, spotA);
    expect(container.read(selectionControllerProvider).selectedId, 'top');
    await tap(tester, spotA);
    expect(container.read(selectionControllerProvider).selectedId, 'bottom',
        reason: 'cycled to bottom');

    // New spot inside both layers but >24 px (cycle tolerance) away.
    final spotB = toScreen(container, const Offset(170, 170));
    await tap(tester, spotB);
    expect(container.read(selectionControllerProvider).selectedId, 'top',
        reason: 'moving the tap resets the cycle to topmost');
  });

  testWidgets('locked higher layer does not block cycling of unlocked layers',
      (tester) async {
    final container = await buildEditor(tester);
    addRect(container,
        id: 'bottom',
        position: const Offset(100, 100),
        size: const Size(200, 200));
    addRect(container,
        id: 'middle',
        position: const Offset(125, 125),
        size: const Size(150, 150));
    // Locked top — must be skipped entirely.
    container.read(documentControllerProvider.notifier).execute(
          AddLayerCommand(
            ShapeLayer(
              id: 'top_locked',
              transform: const LayerTransform(
                position: Offset(150, 150),
                size: Size(100, 100),
              ),
              kind: ShapeKind.rectangle,
            ).withLocked(true),
          ),
        );
    await tester.pump();
    await tester.pump();

    final spot = toScreen(container, const Offset(200, 200));

    await tap(tester, spot);
    expect(container.read(selectionControllerProvider).selectedId, 'middle',
        reason: 'locked top is skipped, middle becomes the topmost eligible');

    await tap(tester, spot);
    expect(container.read(selectionControllerProvider).selectedId, 'bottom',
        reason: 'cycle proceeds across only eligible layers');
  });

  testWidgets('single eligible layer keeps selection on every tap '
      '(no spurious clear / cycle)', (tester) async {
    final container = await buildEditor(tester);
    addRect(container,
        id: 'only',
        position: const Offset(150, 150),
        size: const Size(100, 100));
    await tester.pump();
    await tester.pump();

    final spot = toScreen(container, const Offset(200, 200));
    await tap(tester, spot);
    expect(container.read(selectionControllerProvider).selectedId, 'only');
    await tap(tester, spot);
    expect(container.read(selectionControllerProvider).selectedId, 'only',
        reason: 'with one eligible hit there is nothing to cycle to');
  });
}
