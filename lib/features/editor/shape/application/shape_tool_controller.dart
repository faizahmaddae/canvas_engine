import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/shape_commands.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../toolbar/application/dock_tool_controller.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';

/// Every chip in `ShapeModeToolbar` that drives the shape dock.
///
/// `isPanel: false` means the chip participates in the strip but
/// does not open a dock panel:
///   * [replace] — one-shot picker action.
///
/// Rendered strip order lives in [kShapeStripOrder]; sibling-swipe
/// walks [kShapePanelSlotOrder], derived from that same list.
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

/// Single source of truth for the Shape strip: every chip, in
/// rendered left→right order. `ShapeModeToolbar` builds its chips
/// by iterating THIS list, and [kShapePanelSlotOrder] is derived
/// from it — a change to one cannot drift the other.
///
/// The two action entries are strip-only chips outside
/// [ShapeToolSlot]: `'opacity'` opens a `ContextToolPanel` (a
/// different host, so it stays out of the swipe walk) and `'more'`
/// opens the selected-layer actions sheet.
const List<DockStripEntry<ShapeToolSlot>> kShapeStripOrder =
    <DockStripEntry<ShapeToolSlot>>[
      DockStripEntry.slot(ShapeToolSlot.style),
      DockStripEntry.slot(ShapeToolSlot.border),
      DockStripEntry.slot(ShapeToolSlot.shadow),
      DockStripEntry.action('opacity'),
      DockStripEntry.action('more'),
      DockStripEntry.slot(ShapeToolSlot.replace),
    ];

/// Display order of every Shape dock slot (action chips excluded)
/// — the [kShapeStripOrder] projection.
final List<ShapeToolSlot> kShapeStripSlotOrder = List.unmodifiable(
  kShapeStripOrder.map((e) => e.slot).whereType<ShapeToolSlot>(),
);

/// Panel-bearing slots in RENDERED order — drives sibling-swipe.
/// Derived from [kShapeStripOrder]. Pinned against the pumped
/// toolbar by `test/editor/widget/slot_order_consistency_test.dart`.
final List<ShapeToolSlot> kShapePanelSlotOrder = List.unmodifiable(
  kShapeStripOrder
      .map((e) => e.slot)
      .whereType<ShapeToolSlot>()
      .where((s) => s.isPanel),
);

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
/// the shape-only resize-mode bridge used by the floating toolbar.
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
