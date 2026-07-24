import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/interaction_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: when the user puts down two fingers to pinch a selected
/// layer (without moving the first finger first — i.e. the natural pinch
/// gesture), the controller's first multi-touch update must rebase the
/// session so the layer does NOT jump sideways by half the inter-finger
/// distance.
///
/// Before the fix, the rebase guard `_lastPointerCount != 0 && ...` made
/// the controller skip the first rebase when the session went straight
/// from 0 pointers (just-started) to 2 pointers (no intermediate single-
/// finger update). The engine then anchored the gesture using the first
/// finger's landing position as `focal0` while receiving the midpoint as
/// the new focal — producing a translate of `(P2 - P1) / 2` on the very
/// first multi-touch frame.
void main() {
  test('pinch starting with two fingers (no prior single-finger update) '
      'does not jump the layer on the first multi-touch frame', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const layerSize = Size(100, 100);
    const layerPosition = Offset(150, 150);
    const layerCenter = Offset(200, 200); // 150 + 100/2

    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    final layer = ShapeLayer(
      id: 'shape',
      transform: const LayerTransform(position: layerPosition, size: layerSize),
      kind: ShapeKind.rectangle,
    );
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));

    final controller = container.read(interactionControllerProvider.notifier);

    // First finger lands ON the layer's left edge.
    const p1 = Offset(160, 200);
    controller.startGesture(layer: layer, focalPoint: p1);

    // Second finger lands ON the layer's right edge — WITHOUT any
    // intermediate single-finger update. Recognizer would emit:
    // pointerCount=2, scale=1.0, rotation=0, focal=midpoint(p1, p2).
    const midpoint = Offset(200, 200);
    controller.updateGesture(
      focalPoint: midpoint,
      scale: 1.0,
      rotation: 0.0,
      pointerCount: 2,
    );

    final live = container.read(interactionControllerProvider).liveTransform;
    expect(live, isNotNull);

    // The layer must not have moved. Before the fix the centre would
    // have shifted by (p2 - p1) / 2 = (40, 0).
    expect(
      live!.center.dx,
      closeTo(layerCenter.dx, 0.001),
      reason:
          'Layer centre X must not jump when the second finger '
          'lands. Expected ${layerCenter.dx}, got ${live.center.dx}. '
          'A horizontal jump indicates the first multi-touch update '
          'is using a stale focal0 (the first finger position) '
          'instead of the midpoint.',
    );
    expect(live.center.dy, closeTo(layerCenter.dy, 0.001));
    expect(live.size.width, closeTo(layerSize.width, 0.001));
    expect(live.size.height, closeTo(layerSize.height, 0.001));
  });
}
