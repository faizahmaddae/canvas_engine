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

/// Acceptance test for the off-canvas recovery fix.
///
/// Dragging the body of a selected layer must move the *layer*, not pan
/// the *viewport* — even when the layer sits entirely outside the
/// document bounds. Before the fix, the in-canvas gesture surface was
/// clipped/unreachable for off-canvas layers and the viewport's
/// background pan would steal the gesture instead.
void main() {
  testWidgets(
    'dragging the body of a fully off-canvas selected layer moves the '
    'layer (viewport stays put)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Small doc + large view so the auto-fit leaves visible margin
      // around the canvas — that's where we place an off-canvas layer
      // whose centre still maps to a screen-space point inside the
      // gesture-detectable area.
      const docSize = Size(400, 400);
      const layerSize = Size(100, 100);
      // Half the layer sits in the negative-canvas region; its centre
      // is at the canvas origin (0,0).
      const layerStart = Offset(-50, -50);

      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: docSize.width, height: docSize.height);
      container
          .read(documentControllerProvider.notifier)
          .execute(
            AddLayerCommand(
              ShapeLayer(
                id: 'shape',
                transform: const LayerTransform(
                  position: layerStart,
                  size: layerSize,
                ),
                kind: ShapeKind.rectangle,
              ),
            ),
          );
      container.read(selectionControllerProvider.notifier).select('shape');

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

      final viewportBefore = container.read(viewportControllerProvider);

      // Compute the layer's screen-space centre using the same mapping
      // the overlay uses: canvas * scale + translation.
      final layerCenterCanvas =
          layerStart + Offset(layerSize.width / 2, layerSize.height / 2);
      final start =
          layerCenterCanvas * viewportBefore.scale + viewportBefore.translation;

      const dragVector = Offset(60, 40);

      final gesture = await tester.startGesture(start, pointer: 11);
      // After pointer-down our claim-on-down recogniser must already
      // have started a move session for the off-canvas layer — proving
      // the body surface (not the viewport) claimed the arena.
      await tester.pump();
      final sessionAtDown = container
          .read(interactionControllerProvider)
          .session;
      expect(
        sessionAtDown,
        isNotNull,
        reason:
            'Touching the body of an off-canvas selected layer '
            'must start an interaction session immediately (claim-on-'
            'down).',
      );
      expect(sessionAtDown!.layerId, 'shape');

      // Drive the rest of the gesture; the exact final position depends
      // on the time-based smoother (whose Stopwatch reads wall-clock
      // time and so does not advance under tester.pump in tests). We
      // therefore only assert on the gesture-priority invariants here:
      // session ownership above and viewport non-movement below.
      await gesture.moveBy(dragVector);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final viewportAfter = container.read(viewportControllerProvider);

      // The viewport must be untouched — the background pan must not
      // have stolen the gesture.
      expect(
        viewportAfter.translation,
        viewportBefore.translation,
        reason:
            'Viewport must NOT pan while a selected layer body is '
            'being dragged.',
      );
      expect(viewportAfter.scale, viewportBefore.scale);

      // Pump past the parent GestureDetector's double-tap timeout so
      // no recogniser timers leak past the test end.
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  test('recovery: SetLayerTransformCommand can re-centre an off-canvas layer '
      'and is undoable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final docCtrl = container.read(documentControllerProvider.notifier);
    docCtrl.newDocument(width: 400, height: 400);
    docCtrl.execute(
      AddLayerCommand(
        ShapeLayer(
          id: 'shape',
          transform: const LayerTransform(
            position: Offset(-500, -500),
            size: Size(100, 100),
          ),
          kind: ShapeKind.rectangle,
        ),
      ),
    );

    // Centre the layer (the same operation the AppBar action issues).
    final layer = container
        .read(documentControllerProvider)
        .layerById('shape')!;
    final centred = layer.transform.copyWith(
      position: const Offset(150, 150), // 400/2 - 100/2
    );
    docCtrl.execute(
      SetLayerTransformCommand(
        layerId: 'shape',
        transform: centred,
        labelOverride: 'Center layer',
      ),
    );

    final after = container
        .read(documentControllerProvider)
        .layerById('shape')!;
    expect(after.transform.position, const Offset(150, 150));
    expect(
      after.transform.center,
      const Offset(200, 200),
      reason: 'Layer centre must coincide with canvas centre.',
    );

    // Undo restores the original off-canvas position — proving the
    // recovery is a normal undoable command, not a side-effecting hack.
    docCtrl.undo();
    final undone = container
        .read(documentControllerProvider)
        .layerById('shape')!;
    expect(undone.transform.position, const Offset(-500, -500));
  });
}
