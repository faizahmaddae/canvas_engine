import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/interaction_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/selection_state.dart';
import 'package:canvas_engine/features/editor/engine/interaction/snap_engine.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Resize-time snap: the *grabbed corner* should snap to peer/canvas
/// alignment targets, with the opposite (anchor) corner held fixed.
/// Only applies to unrotated layers.
///
/// We assert on [InteractionUiState.snapGuides] (which carries the
/// raw, pre-smoothing snap result). The smoother makes synchronous
/// inspection of [liveTransform] unreliable in unit tests because
/// dt between back-to-back calls is essentially zero.
void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    c.read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    return c;
  }

  ShapeLayer addRect(
    ProviderContainer c, {
    required String id,
    required Offset position,
    Size size = const Size(100, 100),
  }) {
    final layer = ShapeLayer(
      id: id,
      transform: LayerTransform(position: position, size: size),
      kind: ShapeKind.rectangle,
    );
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
    return layer;
  }

  group('resize-time snap', () {
    test('bottom-right resize snaps right edge to peer left edge', () {
      final c = makeContainer();
      // Peer at (200, 500) so its top=500 (no Y conflict with the
      // moving rect's bottom). Moving layer at (50,50) size 100x100.
      // Drag bottom-right to (197, 280) — right edge 3px from
      // peer.left=200, bottom edge nowhere near a peer Y target.
      addRect(c, id: 'peer', position: const Offset(200, 500));
      final mover = addRect(c, id: 'm', position: const Offset(50, 50));

      c.read(interactionControllerProvider.notifier).startResize(
            layer: mover,
            handle: InteractionHandle.bottomRight,
            pointer: const Offset(150, 150),
          );
      c
          .read(interactionControllerProvider.notifier)
          .update(const Offset(197, 280));

      final guides = c.read(interactionControllerProvider).snapGuides;
      expect(guides, hasLength(1));
      expect(guides.first.axis, SnapAxis.vertical);
      expect(guides.first.coord, 200,
          reason: 'right edge snapped to peer.left=200');
    });

    test('top-left resize snaps both moving edges independently', () {
      final c = makeContainer();
      addRect(c, id: 'pX', position: const Offset(20, 400));
      addRect(c, id: 'pY', position: const Offset(400, 30));
      final mover = addRect(c, id: 'm', position: const Offset(100, 100));

      c.read(interactionControllerProvider.notifier).startResize(
            layer: mover,
            handle: InteractionHandle.topLeft,
            pointer: const Offset(100, 100),
          );
      c
          .read(interactionControllerProvider.notifier)
          .update(const Offset(22, 33));

      final guides = c.read(interactionControllerProvider).snapGuides;
      expect(guides, hasLength(2));
      final v = guides.firstWhere((g) => g.axis == SnapAxis.vertical);
      final h = guides.firstWhere((g) => g.axis == SnapAxis.horizontal);
      expect(v.coord, 20, reason: 'left edge snapped to peer X=20');
      expect(h.coord, 30, reason: 'top edge snapped to peer Y=30');
    });

    test('aspect-locked resize picks axis with smaller correction', () {
      final c = makeContainer();
      // Peer establishing X=200 (left edge). Moving layer 100x100 at
      // (50,50). Drag bottom-right to (197, 148): X correction=3,
      // Y correction=2 (bottom→peer.bottom=150). Aspect lock should
      // pick the smaller (Y axis).
      addRect(c, id: 'p', position: const Offset(200, 50));
      final mover = ImageLayer(
        id: 'm',
        transform: const LayerTransform(
          position: Offset(50, 50),
          size: Size(100, 100),
        ),
        source: const ImageSource.asset('placeholder'),
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(mover));

      c.read(interactionControllerProvider.notifier).startResize(
            layer: mover,
            handle: InteractionHandle.bottomRight,
            pointer: const Offset(150, 150),
          );
      c
          .read(interactionControllerProvider.notifier)
          .update(const Offset(197, 148));

      final guides = c.read(interactionControllerProvider).snapGuides;
      // Exactly one guide — aspect lock allows snap on only one axis.
      expect(guides, hasLength(1));
      expect(guides.first.axis, SnapAxis.horizontal,
          reason: 'Y correction (2) was smaller, so Y axis wins');
      expect(guides.first.coord, 150);
    });

    test('rotated layer is NOT snap-adjusted (resize snap is unrotated-only)',
        () {
      final c = makeContainer();
      addRect(c, id: 'peer', position: const Offset(200, 50));
      final mover = ShapeLayer(
        id: 'm',
        transform: const LayerTransform(
          position: Offset(50, 50),
          size: Size(100, 100),
          rotation: 0.4,
        ),
        kind: ShapeKind.rectangle,
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(mover));

      c.read(interactionControllerProvider.notifier).startResize(
            layer: mover,
            handle: InteractionHandle.bottomRight,
            pointer: const Offset(150, 150),
          );
      c
          .read(interactionControllerProvider.notifier)
          .update(const Offset(197, 150));

      final guides = c.read(interactionControllerProvider).snapGuides;
      expect(guides, isEmpty,
          reason: 'rotated layers should not produce resize-time guides');
    });

    test('no snap engaged → no guides', () {
      final c = makeContainer();
      addRect(c, id: 'peer', position: const Offset(500, 50));
      final mover = addRect(c, id: 'm', position: const Offset(50, 50));

      c.read(interactionControllerProvider.notifier).startResize(
            layer: mover,
            handle: InteractionHandle.bottomRight,
            pointer: const Offset(150, 150),
          );
      c
          .read(interactionControllerProvider.notifier)
          .update(const Offset(180, 180));

      final guides = c.read(interactionControllerProvider).snapGuides;
      expect(guides, isEmpty);
    });
  });
}
