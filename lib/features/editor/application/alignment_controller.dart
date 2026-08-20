import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/commands/editor_command.dart';
import '../engine/commands/transform_commands.dart';
import '../engine/core/editor_document.dart';
import '../engine/core/editor_layer.dart';
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
///   * fewer than two eligible layers are selected for peer alignment;
///   * fewer than three eligible layers are selected for distribute;
///   * every selected layer is ineligible (nothing to commit).
///
/// Ineligible layers — locked, non-movable, or the protected base
/// photo — are silently dropped from each batch so a mixed selection
/// still works for the layers that *can* move. This matches the
/// behaviour of every group-gesture path in [InteractionController].
///
/// The UI in front of these methods must render from the SAME rule
/// they refuse by ([canMoveLayer] via [AlignmentEligibility]), never a
/// local re-derivation: the audit found the overflow-sheet rows and
/// align tiles reading a different gate than the controller, leaving
/// live-looking buttons that silently no-oped (P2-7, contract §10.3).
class AlignmentController {
  AlignmentController(this._ref);

  final Ref _ref;
  static const _engine = AlignmentEngine();

  /// THE per-layer rule for whether the alignment suite may move
  /// [layer]. Consumed by every method in this class through
  /// [AlignmentEligibility.of], and by every UI gate in front of them
  /// (the overflow-sheet Align rows, the align-panel tiles) — one
  /// rule, so the controls and the commands cannot drift apart.
  ///
  /// The base-photo clause is a backstop: the base photo IS the
  /// canvas, so aligning it to the canvas is meaningless by
  /// construction. It imports locked, but the lock is user-visible
  /// state — this keeps the rule true even for an unlocked one.
  static bool canMoveLayer(EditorDocument doc, EditorLayer layer) =>
      !layer.locked &&
      layer.capabilities.movable &&
      !doc.isProtectedBasePhoto(layer.id);

  /// Align every movable selected layer along [axis]. No-op when fewer
  /// than two movable layers are selected.
  void align(AlignAxis axis) {
    final initials = _eligibleInitials();
    if (initials.length < 2) return;
    final out = _engine.align(initials, axis);
    _commit(out, initials, label: _alignLabel(axis));
  }

  /// Align the primary selected layer to the document canvas. No-op
  /// when nothing is selected, the selected layer is ineligible
  /// ([canMoveLayer]), or the requested alignment would not move it.
  void alignToCanvas(AlignAxis axis) {
    final selection = _ref.read(selectionControllerProvider);
    final id = selection.selectedId;
    if (id == null) return;
    final doc = _ref.read(documentControllerProvider);
    final layer = doc.layerById(id);
    if (layer == null || !canMoveLayer(doc, layer)) return;
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
  /// dropping missing layers and everything [canMoveLayer] refuses.
  Map<String, LayerTransform> _eligibleInitials() {
    final selection = _ref.read(selectionControllerProvider);
    final doc = _ref.read(documentControllerProvider);
    final out = <String, LayerTransform>{};
    for (final id in selection.selectedIds) {
      final layer = doc.layerById(id);
      if (layer == null || !canMoveLayer(doc, layer)) continue;
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

/// What the align/distribute suite can currently do for a set of
/// layers — the ONE eligibility answer every align entry point
/// renders from. A control the controller will refuse must read as
/// unavailable, never sit live and silently no-op (contract §10.3);
/// deriving the gates here, from the controller's own
/// [AlignmentController.canMoveLayer], is what keeps the UI and the
/// commands in agreement (audit P2-7).
class AlignmentEligibility {
  const AlignmentEligibility({
    required this.selectedCount,
    required this.eligibleCount,
  });

  /// Count eligibility for [layers] against [doc]. Callers pass the
  /// same layer set their surface displays: the overflow sheet its
  /// open-time selection snapshot, the align panel its live panel
  /// layers.
  factory AlignmentEligibility.of(
    EditorDocument doc,
    Iterable<EditorLayer> layers,
  ) {
    var selected = 0;
    var eligible = 0;
    for (final layer in layers) {
      selected++;
      if (AlignmentController.canMoveLayer(doc, layer)) eligible++;
    }
    return AlignmentEligibility(
      selectedCount: selected,
      eligibleCount: eligible,
    );
  }

  final int selectedCount;
  final int eligibleCount;

  /// Peer alignment (multi) moves two or more eligible members —
  /// mirrors the `< 2` bail in [AlignmentController.align]. Canvas
  /// alignment (single) needs its one layer eligible
  /// ([AlignmentController.alignToCanvas]).
  bool get canAlign =>
      selectedCount > 1 ? eligibleCount >= 2 : eligibleCount >= 1;

  /// Distribute spaces three or more eligible members — mirrors the
  /// `< 3` bail in [AlignmentController.distribute].
  bool get canDistribute => eligibleCount >= 3;
}
