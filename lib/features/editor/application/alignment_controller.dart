import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/commands/editor_command.dart';
import '../engine/commands/transform_commands.dart';
import '../engine/core/layer_transform.dart';
import '../engine/interaction/alignment_engine.dart';
import 'document_controller.dart';
import 'selection_controller.dart';

/// Public entry point for the multi-select alignment / distribution
/// suite. Reads the current selection, runs pure-engine layout math
/// ([AlignmentEngine]), and commits the result as a single composite
/// undoable command — matching the architecture of every other
/// non-trivial mutation in this editor.
///
/// All operations are no-ops when:
///   * no layer is selected;
///   * fewer than two layers are selected for peer alignment;
///   * fewer than three layers are selected for distribute (ditto);
///   * every selected layer is locked or non-movable (nothing to commit).
///
/// Locked / non-movable layers are silently dropped from each batch so a
/// mixed selection still works for the layers that *can* move. This
/// matches the behaviour of every group-gesture path in
/// [InteractionController].
class AlignmentController {
  AlignmentController(this._ref);

  final Ref _ref;
  static const _engine = AlignmentEngine();

  /// Align every movable selected layer along [axis]. No-op when fewer
  /// than two movable layers are selected.
  void align(AlignAxis axis) {
    final initials = _eligibleInitials();
    if (initials.length < 2) return;
    final out = _engine.align(initials, axis);
    _commit(out, initials, label: _alignLabel(axis));
  }

  /// Align the primary selected layer to the document canvas. No-op
  /// when nothing is selected, the selected layer is locked/non-movable,
  /// or the requested alignment would not move it.
  void alignToCanvas(AlignAxis axis) {
    final selection = _ref.read(selectionControllerProvider);
    final id = selection.selectedId;
    if (id == null) return;
    final doc = _ref.read(documentControllerProvider);
    final layer = doc.layerById(id);
    if (layer == null || layer.locked || !layer.capabilities.movable) return;
    final target = Rect.fromLTWH(0, 0, doc.width, doc.height);
    final next = _engine.alignToRect(layer.transform, target, axis);
    _commit({id: next}, {id: layer.transform}, label: _alignLabel(axis));
  }

  /// Distribute every movable selected layer along [axis]. No-op when
  /// fewer than three movable layers are selected.
  void distribute(DistributeAxis axis) {
    final initials = _eligibleInitials();
    if (initials.length < 3) return;
    final out = _engine.distribute(initials, axis);
    _commit(out, initials, label: _distributeLabel(axis));
  }

  /// Build the {id → initial transform} map from the current selection,
  /// dropping locked / non-movable / missing layers.
  Map<String, LayerTransform> _eligibleInitials() {
    final selection = _ref.read(selectionControllerProvider);
    final doc = _ref.read(documentControllerProvider);
    final out = <String, LayerTransform>{};
    for (final id in selection.selectedIds) {
      final layer = doc.layerById(id);
      if (layer == null) continue;
      if (layer.locked) continue;
      if (!layer.capabilities.movable) continue;
      out[id] = layer.transform;
    }
    return out;
  }

  /// Commit the diff between [next] and [initials] as one composite
  /// command. Drops entries whose transform did not change so the
  /// command label reflects the actual layer count.
  void _commit(
    Map<String, LayerTransform> next,
    Map<String, LayerTransform> initials, {
    required String label,
  }) {
    final cmds = <EditorCommand>[];
    next.forEach((id, t) {
      final initial = initials[id];
      if (initial == null) return;
      if (t == initial) return;
      cmds.add(
        SetLayerTransformCommand(
          layerId: id,
          transform: t,
          labelOverride: label,
        ),
      );
    });
    if (cmds.isEmpty) return;
    final docCtl = _ref.read(documentControllerProvider.notifier);
    if (cmds.length == 1) {
      docCtl.execute(cmds.first);
    } else {
      docCtl.execute(
        CompositeCommand(cmds, labelOverride: '$label ${cmds.length} layers'),
      );
    }
  }

  String _alignLabel(AlignAxis axis) {
    switch (axis) {
      case AlignAxis.left:
        return 'Align left';
      case AlignAxis.centerX:
        return 'Align center horizontally';
      case AlignAxis.right:
        return 'Align right';
      case AlignAxis.top:
        return 'Align top';
      case AlignAxis.centerY:
        return 'Align center vertically';
      case AlignAxis.bottom:
        return 'Align bottom';
    }
  }

  String _distributeLabel(DistributeAxis axis) {
    switch (axis) {
      case DistributeAxis.horizontal:
        return 'Distribute horizontally';
      case DistributeAxis.vertical:
        return 'Distribute vertically';
    }
  }
}

final alignmentControllerProvider = Provider<AlignmentController>((ref) {
  return AlignmentController(ref);
});
