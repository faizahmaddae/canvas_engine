import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/shape_commands.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../toolbar/application/dock_tool_controller.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';

/// The Shape Studio's panel-bearing slots (shape studio doc §5).
///
/// Since the bench replaced the strip, ONLY panel-bearing slots
/// remain: Replace is the bench's specimen chip, opacity is the fact
/// cluster's percentage zone, and More is an aspect-track action —
/// none of them are dock panels.
enum ShapeToolSlot {
  style,
  border,
  shadow;

  /// Safe lookup by enum name; returns `null` for unknown / legacy
  /// strings.
  static ShapeToolSlot? tryByName(String? name) {
    if (name == null) return null;
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Display order of the Shape dock panels — the bench renders its
/// aspect track from this order and sibling-swipe walks it, so the
/// two cannot drift. Pinned against the pumped bench by
/// `test/editor/widget/slot_order_consistency_test.dart`.
const List<ShapeToolSlot> kShapePanelSlotOrder = <ShapeToolSlot>[
  ShapeToolSlot.style,
  ShapeToolSlot.border,
  ShapeToolSlot.shadow,
];

/// Slots intentionally skipped during sibling-swipe. Empty today.
const Set<ShapeToolSlot> kShapeSlotsExcludedFromSwipe = <ShapeToolSlot>{};

/// Shared prev/next walker for the Shape dock.
final SiblingSwipeStrategy<ShapeToolSlot> kShapeSwipeStrategy =
    SiblingSwipeStrategy<ShapeToolSlot>(
      order: kShapePanelSlotOrder,
      excluded: kShapeSlotsExcludedFromSwipe,
    );

/// In-dock state for the Shape sub-tool — see [DockToolSession].
typedef ShapeToolSession = DockToolSession<ShapeToolSlot>;

/// Shape dock controller — the generic [DockToolController] plus
/// the shape-only resize-mode bridge used by the floating toolbar
/// and the bench's size zone.
class ShapeToolController extends DockToolController<ShapeToolSlot> {
  ShapeToolController() : super(swipe: kShapeSwipeStrategy);

  /// Switch the resize behaviour of the currently-selected shape
  /// layer. Mirrors `PaintToolController.setResizeMode` so the
  /// floating-toolbar toggle is the same affordance the user
  /// already learned in Paint. No-op when nothing shape-y is
  /// selected or the mode is already the requested one. Single
  /// undoable history entry.
  void setResizeMode(ShapeResizeMode mode) {
    final layer = selectedShapeLayer();
    if (layer == null) return;
    if (layer.effectiveResizeMode == mode && layer.resizeMode == mode) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetShapeResizeModeCommand(layerId: layer.id, mode: mode));
  }

  /// Read the currently-selected shape layer (if any). Used by the
  /// floating toolbar to render against the selected layer's mode
  /// instead of any session default.
  ShapeLayer? selectedShapeLayer() {
    final selection = ref.read(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer = ref
        .read(documentControllerProvider)
        .layerById(selection.selectedId!);
    return layer is ShapeLayer ? layer : null;
  }
}

final shapeToolControllerProvider =
    NotifierProvider<ShapeToolController, ShapeToolSession>(
      ShapeToolController.new,
    );
