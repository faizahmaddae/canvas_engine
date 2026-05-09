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

/// Regression: "select a single object and scale it — on release it
/// immediately resets back to the original size." Root cause identical
/// to the group variant: the single-layer pinch path rebases
/// `session.initialTransform` to the current live transform on
/// pointer-count transitions (2→1 at release), so the `end()` diff
/// against `initialTransform` always matched and skipped the commit.

ProviderContainer _setup(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpEditorWithLayer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container
      .read(documentControllerProvider.notifier)
      .newDocument(width: 800, height: 800);
  container.read(documentControllerProvider.notifier).execute(
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
  container.read(selectionControllerProvider.notifier).select('a');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'single-layer two-finger pinch commits the scaled transform '
    'to the document on release (no revert)',
    (tester) async {
      final container = _setup(tester);
      await _pumpEditorWithLayer(tester, container);

      final before =
          container.read(documentControllerProvider).layerById('a')!.transform;

      final vp = container.read(viewportControllerProvider);
      Offset toScreen(Offset c) => c * vp.scale + vp.translation;
      final centre = toScreen(const Offset(400, 400));
      final p1 = centre + const Offset(-60, 0);
      final p2 = centre + const Offset(60, 0);

      final f1 = await tester.startGesture(p1, pointer: 51);
      await tester.pump();
      final f2 = await tester.startGesture(p2, pointer: 52);
      await tester.pump();

      await f1.moveBy(const Offset(-60, 0));
      await f2.moveBy(const Offset(60, 0));
      await tester.pump();
      await f1.moveBy(const Offset(-60, 0));
      await f2.moveBy(const Offset(60, 0));
      await tester.pump();

      final live =
          container.read(interactionControllerProvider).liveTransform!;
      expect(live.size.width, greaterThan(before.size.width));

      await f1.up();
      await f2.up();
      await tester.pump();
      await tester.pump();

      final after =
          container.read(documentControllerProvider).layerById('a')!.transform;
      expect(
        after.size.width,
        greaterThan(before.size.width),
        reason: 'Single-layer pinch must retain its scaled size after '
            'release.',
      );
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
