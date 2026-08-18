import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/canvas_sizing.dart';
import '../../engine/interaction/layer_space_mapper.dart';
import '../../engine/modules/paint/paint_layer.dart';
import 'paint_draft.dart';
import 'paint_tool_controller.dart';

const _uuid = Uuid();

/// Application boundary for committing paint gestures.
///
/// The presentation surface owns raw pointer sequencing and a visual draft;
/// this controller is the only paint-gesture type allowed to dispatch engine
/// commands. Erasing remains whole-stroke removal: hit testing uses the
/// current oriented layer bounds until a separately designed geometry-aware
/// eraser lands.
class PaintStrokeController extends Notifier<void> {
  final List<String> _sweepErasedIds = [];

  @override
  void build() {}

  /// Finalize [draft] into one AddLayer command. [docSize] and every draft
  /// point are in canvas space.
  void commitDraft(PaintDraft draft, {required Size docSize}) {
    final layer = draft.toLayer(id: _uuid.v4(), docSize: docSize);
    if (layer == null) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
  }

  /// Commit the tap-only freestyle dot through the same draft pipeline.
  /// [canvasPoint] is in canvas space.
  void commitDot(Offset canvasPoint, {required Size docSize}) {
    final session = ref.read(paintToolControllerProvider);
    final doc = ref.read(documentControllerProvider);
    commitDraft(
      PaintDraft(
        kind: PaintKind.freestyle,
        strokeColor: session.strokeColor,
        strokeWidth: session.strokeWidth,
        fillColor: session.fillColor,
        sides: session.polygonSides,
        blurSigma: CanvasSizing.scaleDimension(session.blurRadius, doc),
        points: [canvasPoint],
      ),
      docSize: docSize,
    );
  }

  /// A discrete eraser tap is one history entry. Returns false on a miss.
  /// [canvasPoint] is in canvas space.
  bool eraseAt(Offset canvasPoint) {
    final hit = _hitPaintLayer(canvasPoint);
    if (hit == null) return false;
    ref
        .read(documentControllerProvider.notifier)
        .execute(RemoveLayerCommand(hit.id));
    _clearSelectionIfNeeded([hit.id]);
    return true;
  }

  void beginEraserSweep() {
    _sweepErasedIds.clear();
  }

  /// Stage one whole-stroke removal on LiveOverlay. Repeated hits within
  /// the same sweep are ignored and the committed document stays frozen.
  void sweepEraseAt(Offset canvasPoint) {
    final hit = _hitPaintLayer(canvasPoint, exclude: _sweepErasedIds.toSet());
    if (hit == null) return;
    _sweepErasedIds.add(hit.id);
    ref.read(liveOverlayProvider.notifier).removeLayer(hit.id);
  }

  /// Seal every staged sweep hit as exactly one undoable command.
  void commitEraserSweep() {
    final ids = List<String>.of(_sweepErasedIds);
    _sweepErasedIds.clear();
    if (ids.isEmpty) return;
    ref.read(liveOverlayProvider.notifier).clear();
    final commands = <RemoveLayerCommand>[
      for (final id in ids) RemoveLayerCommand(id),
    ];
    final EditorCommand command = commands.length == 1
        ? commands.single
        : CompositeCommand(commands, labelOverride: 'Remove layer');
    ref.read(documentControllerProvider.notifier).execute(command);
    _clearSelectionIfNeeded(ids);
  }

  PaintLayer? _hitPaintLayer(
    Offset canvasPoint, {
    Set<String> exclude = const {},
  }) {
    final doc = ref.read(documentControllerProvider);
    for (var i = doc.layers.length - 1; i >= 0; i--) {
      final layer = doc.layers[i];
      if (layer is! PaintLayer || !layer.visible || layer.locked) continue;
      if (exclude.contains(layer.id)) continue;
      if (LayerSpaceMapper.containsCanvasPoint(layer.transform, canvasPoint)) {
        return layer;
      }
    }
    return null;
  }

  void _clearSelectionIfNeeded(Iterable<String> ids) {
    final selection = ref.read(selectionControllerProvider);
    if (ids.any(selection.contains)) {
      ref.read(selectionControllerProvider.notifier).clear();
    }
  }
}

final paintStrokeControllerProvider =
    NotifierProvider<PaintStrokeController, void>(PaintStrokeController.new);
