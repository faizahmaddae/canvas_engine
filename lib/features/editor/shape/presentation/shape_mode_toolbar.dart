import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import '../application/shape_tool_controller.dart';

// Strip order and panel-vs-non-panel classification now live on
// [ShapeToolSlot]. Use `ShapeToolSlot.values` for the strip order
// and `kShapePanelSlotOrder` for the swipe-eligible subset.

/// Bottom toolbar shown when a [ShapeLayer] is the current
/// selection. Mirrors [ImageModeToolbar]: shared `SlotStrip` →
/// `DockToolTile` grammar so the active tab gets the same primary
/// tint + glow treatment.
///
/// Tabs:
///   * **Style** — fill colour, opacity, corner radius, presets.
///   * **Border** — outline colour + thickness.
///   * **Shadow** — preset row + compact colour + Adjust precisely
///     (direction pad / blur / opacity).
///   * **Replace** — opens the shape picker as a one-shot action.
class ShapeModeToolbar extends ConsumerWidget {
  const ShapeModeToolbar({
    super.key,
    required this.layer,
    required this.onReplaceTap,
  });

  final ShapeLayer layer;

  /// Invoked when the Replace slot is tapped — wired by
  /// editor_screen so the picker logic stays in one place.
  final VoidCallback onReplaceTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openSlot = ref.watch(
      shapeToolControllerProvider.select((s) => s.openSlot),
    );
    final ctrl = ref.read(shapeToolControllerProvider.notifier);
    final l10n = context.l10n;
    final slots = <ToolbarSlot>[
      ToolbarSlot(
        id: ShapeToolSlot.style.name,
        icon: Icons.palette_rounded,
        label: l10n.styleTool,
        onTap: () => ctrl.toggleSlot(ShapeToolSlot.style),
      ),
      ToolbarSlot(
        id: ShapeToolSlot.border.name,
        icon: Icons.border_outer_rounded,
        label: l10n.borderTool,
        onTap: () => ctrl.toggleSlot(ShapeToolSlot.border),
      ),
      ToolbarSlot(
        id: ShapeToolSlot.shadow.name,
        icon: Icons.blur_on_rounded,
        label: l10n.shadowTool,
        onTap: () => ctrl.toggleSlot(ShapeToolSlot.shadow),
      ),
      // Replace is a one-shot action (opens the picker) rather than
      // an inline panel — onPickReplace is wired by editor_screen via
      // a callback baked into the slot. We still expose it as a
      // toolbar slot so it visually matches the other tabs.
      ToolbarSlot(
        id: ShapeToolSlot.replace.name,
        icon: Icons.swap_horiz_rounded,
        label: l10n.replaceTool,
        onTap: onReplaceTap,
      ),
    ];
    return SlotStrip(slots: slots, activeId: openSlot?.name);
  }
}
