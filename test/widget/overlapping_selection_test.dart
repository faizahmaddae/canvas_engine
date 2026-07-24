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

/// Regression: tapping a visually-higher overlapping layer must switch
/// selection directly with a single tap, even when another (lower) layer
/// is currently selected.
///
/// Before the fix, the selected layer's screen-space `_BodyDragSurface`
/// covered its entire rotated bounding rect with `HitTestBehavior.opaque`
/// + a claim-on-down gesture recogniser. Any tap landing inside that
/// rect — including taps on regions where a higher-z layer was visually
/// on top — was eaten by the body surface, so the canvas's `onTapUp`
/// never ran and selection couldn't switch without a manual deselect
/// first.
void main() {
  testWidgets('tapping a higher overlapping layer switches selection directly '
      '(no manual deselect required)', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    const docSize = Size(400, 400);

    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: docSize.width, height: docSize.height);

    // 'bottom' covers the centre of the canvas at (100..300, 100..300).
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ShapeLayer(
              id: 'bottom',
              transform: const LayerTransform(
                position: Offset(100, 100),
                size: Size(200, 200),
              ),
              kind: ShapeKind.rectangle,
            ),
          ),
        );
    // 'top' is fully inside 'bottom' at (150..250, 150..250) and added
    // AFTER, so it is visually on top.
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ShapeLayer(
              id: 'top',
              transform: const LayerTransform(
                position: Offset(150, 150),
                size: Size(100, 100),
              ),
              kind: ShapeKind.rectangle,
            ),
          ),
        );

    // Pre-select the BOTTOM layer so the body surface is rendered
    // over its full bounds — including the region where 'top' is
    // visually on top.
    container.read(selectionControllerProvider.notifier).select('bottom');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
      ),
    );
    // Two pumps: one for fit-to-screen post-frame callback, one for
    // the resulting overlay rebuild.
    await tester.pump();
    await tester.pump();

    expect(
      container.read(selectionControllerProvider).selectedId,
      'bottom',
      reason: 'Setup precondition: bottom must be selected before tap.',
    );

    // Tap the centre of 'top' (which is also the centre of 'bottom').
    // Before the fix, the bottom layer's body surface would eat this
    // tap and selection would stay on 'bottom'.
    final viewport = container.read(viewportControllerProvider);
    final topCenterCanvas = const Offset(200, 200); // 150 + 100/2
    final topCenterScreen =
        topCenterCanvas * viewport.scale + viewport.translation;

    await tester.tapAt(topCenterScreen);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      container.read(selectionControllerProvider).selectedId,
      'top',
      reason:
          'A single tap on a visually-higher overlapping layer '
          'must switch selection directly to that layer, with no '
          'forced deselect step.',
    );
  });

  testWidgets('tapping the selected layer in a region where no higher layer '
      'overlaps keeps selection (no spurious switch / clear)', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 400, height: 400);
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ShapeLayer(
              id: 'bottom',
              transform: const LayerTransform(
                position: Offset(100, 100),
                size: Size(200, 200),
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
              id: 'top',
              transform: const LayerTransform(
                position: Offset(150, 150),
                size: Size(100, 100),
              ),
              kind: ShapeKind.rectangle,
            ),
          ),
        );
    container.read(selectionControllerProvider.notifier).select('bottom');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Tap a region inside 'bottom' that 'top' does NOT cover:
    // bottom is (100..300, 100..300), top is (150..250, 150..250).
    // Point (120, 120) is inside bottom but outside top.
    final viewport = container.read(viewportControllerProvider);
    final bottomOnlyCanvas = const Offset(120, 120);
    final bottomOnlyScreen =
        bottomOnlyCanvas * viewport.scale + viewport.translation;

    await tester.tapAt(bottomOnlyScreen);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Selection must remain 'bottom' — the gate is only "switch when
    // a higher layer is at this point", not "always fall through".
    expect(container.read(selectionControllerProvider).selectedId, 'bottom');
  });

  testWidgets('a higher LOCKED overlapping layer does NOT block selecting / '
      'manipulating the lower selected layer', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 400, height: 400);
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ShapeLayer(
              id: 'bottom',
              transform: const LayerTransform(
                position: Offset(100, 100),
                size: Size(200, 200),
              ),
              kind: ShapeKind.rectangle,
            ),
          ),
        );
    // Locked higher layer — should be ignored by hit-testing and
    // therefore not interfere with bottom's selection / interaction.
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ShapeLayer(
              id: 'top',
              transform: const LayerTransform(
                position: Offset(150, 150),
                size: Size(100, 100),
              ),
              kind: ShapeKind.rectangle,
            ).withLocked(true),
          ),
        );
    container.read(selectionControllerProvider.notifier).select('bottom');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Tap the centre — locked top must be ignored, selection must
    // stay on bottom.
    final viewport = container.read(viewportControllerProvider);
    final centerScreen =
        const Offset(200, 200) * viewport.scale + viewport.translation;
    await tester.tapAt(centerScreen);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      container.read(selectionControllerProvider).selectedId,
      'bottom',
      reason:
          'A locked higher layer must NOT block selection of the '
          'lower layer.',
    );
  });
}
