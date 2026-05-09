import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/shape_commands.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';

/// Every chip in `ShapeModeToolbar`, in left→right strip order.
///
/// `isPanel: false` means the chip participates in the strip but
/// does not open a dock panel:
///   * [replace] — one-shot picker action.
enum ShapeToolSlot {
  style,
  border,
  shadow,
  replace(isPanel: false);

  const ShapeToolSlot({this.isPanel = true});

  /// Whether tapping this chip opens an inline dock panel.
  final bool isPanel;

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

/// Display order of every Shape chip — including non-panel ones.
const List<ShapeToolSlot> kShapeStripSlotOrder = ShapeToolSlot.values;

/// Panel-bearing slots only — drives sibling-swipe. Verified
/// against `ShapeToolSlot.values.where((s) => s.isPanel)` by the
/// drift test in `slot_order_consistency_test.dart`.
const List<ShapeToolSlot> kShapePanelSlotOrder = <ShapeToolSlot>[
  ShapeToolSlot.style,
  ShapeToolSlot.border,
  ShapeToolSlot.shadow,
];

/// Slots intentionally skipped during sibling-swipe. Empty today.
const Set<ShapeToolSlot> kShapeSlotsExcludedFromSwipe = <ShapeToolSlot>{};

/// Shared prev/next walker for the Shape dock.
const SiblingSwipeStrategy<ShapeToolSlot> kShapeSwipeStrategy =
    SiblingSwipeStrategy<ShapeToolSlot>(
  order: kShapePanelSlotOrder,
  excluded: kShapeSlotsExcludedFromSwipe,
);

/// Snapshot of the in-dock state for the Shape sub-tool. Mirrors
/// [ImageToolSession]: only tracks which sub-tab (Style / Border /
/// Shadow) is currently expanded above the strip — the selected
/// `ShapeLayer` is owned by the document/selection controllers.
@immutable
class ShapeToolSession {
  const ShapeToolSession({this.openSlot});

  static const ShapeToolSession initial = ShapeToolSession();

  /// Currently expanded panel, or `null` when only the chip strip
  /// is visible.
  final ShapeToolSlot? openSlot;

  ShapeToolSession copyWith({
    ShapeToolSlot? openSlot,
    bool clearOpenSlot = false,
  }) {
    return ShapeToolSession(
      openSlot: clearOpenSlot ? null : (openSlot ?? this.openSlot),
    );
  }
}

class ShapeToolController extends Notifier<ShapeToolSession> {
  @override
  ShapeToolSession build() => ShapeToolSession.initial;

  /// Toggle [slot] — if it's already open, close it; otherwise
  /// switch to it. Mirrors the image-tool sheet toggle.
  void toggleSlot(ShapeToolSlot slot) {
    if (state.openSlot == slot) {
      state = state.copyWith(clearOpenSlot: true);
    } else {
      state = state.copyWith(openSlot: slot);
    }
  }

  void closePanel() {
    if (state.openSlot == null) return;
    state = state.copyWith(clearOpenSlot: true);
  }

  /// Open the slot before the current one in
  /// [kShapePanelSlotOrder]. Wraps. No-op when no slot is open.
  void openPrevSlot() {
    final next = kShapeSwipeStrategy.prev(state.openSlot);
    if (next != null) state = state.copyWith(openSlot: next);
  }

  /// Open the slot after the current one in
  /// [kShapePanelSlotOrder]. Wraps. No-op when no slot is open.
  void openNextSlot() {
    final next = kShapeSwipeStrategy.next(state.openSlot);
    if (next != null) state = state.copyWith(openSlot: next);
  }

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
    ref.read(documentControllerProvider.notifier).execute(
          SetShapeResizeModeCommand(layerId: layer.id, mode: mode),
        );
  }

  /// Read the currently-selected shape layer (if any). Used by the
  /// floating toolbar to render against the selected layer's mode
  /// instead of any session default.
  ShapeLayer? selectedShapeLayer() {
    final selection = ref.read(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer =
        ref.read(documentControllerProvider).layerById(selection.selectedId!);
    return layer is ShapeLayer ? layer : null;
  }
}

final shapeToolControllerProvider =
    NotifierProvider<ShapeToolController, ShapeToolSession>(
  ShapeToolController.new,
);
