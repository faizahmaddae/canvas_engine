import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/context_toolbar_controller.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/widgets/layer_overflow_sheet.dart';
import '../../toolbar/application/dock_tool_controller.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import '../application/shape_tool_controller.dart';
import '../../../../app/theme/app_icons.dart';

// Panel-vs-non-panel classification lives on [ShapeToolSlot]. The
// strip renders [kShapeStripOrder] verbatim — the same list the
// sibling-swipe walk is derived from, so the two cannot drift.

/// Bottom toolbar shown when a [ShapeLayer] is the current
/// selection. Mirrors [ImageModeToolbar]: shared `SlotStrip` →
/// `DockToolTile` grammar so the active tab gets the same primary
/// tint treatment.
///
/// Tabs:
///   * **Color** — fill colour, opacity, corner radius, presets.
///   * **Border** — outline colour + thickness.
///   * **Shadow** — preset row + compact colour + Adjust precisely
///     (direction pad / blur / opacity).
///   * **Replace** — secondary one-shot action behind the main tools.
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
    final contextPanel = ref.watch(contextToolbarControllerProvider);
    final slots = <ToolbarSlot>[
      for (final entry in kShapeStripOrder) _chipFor(context, ref, entry),
    ];
    return SlotStrip(
      slots: slots,
      activeId: contextPanel == ContextToolPanel.opacity
          ? 'opacity'
          : openSlot?.name,
    );
  }

  /// Maps one [kShapeStripOrder] entry to its rendered chip. All
  /// icons/labels/actions live here; the ORDER lives only in the
  /// shared list.
  ToolbarSlot _chipFor(
    BuildContext context,
    WidgetRef ref,
    DockStripEntry<ShapeToolSlot> entry,
  ) {
    final ctrl = ref.read(shapeToolControllerProvider.notifier);
    final contextCtrl = ref.read(contextToolbarControllerProvider.notifier);
    final l10n = context.l10n;
    final slot = entry.slot;
    if (slot == null) {
      return switch (entry.actionId) {
        'opacity' => ToolbarSlot(
          id: 'opacity',
          icon: AppIcons.opacity,
          label: l10n.opacityLabel,
          onTap: () {
            ctrl.closePanel();
            contextCtrl.toggle(ContextToolPanel.opacity);
          },
        ),
        'more' => ToolbarSlot(
          id: 'more',
          icon: AppIcons.moreActions,
          label: l10n.moreActionsSemantics,
          onTap: () {
            ctrl.closePanel();
            contextCtrl.closePanel();
            final scaffold = Scaffold.maybeOf(context);
            showLayerOverflowSheet(
              context,
              ref,
              layer: layer,
              onOpenLayers: scaffold == null
                  ? null
                  : () => scaffold.openEndDrawer(),
            );
          },
        ),
        _ => throw StateError('Unknown shape strip action: ${entry.actionId}'),
      };
    }
    return switch (slot) {
      ShapeToolSlot.style => ToolbarSlot(
        id: ShapeToolSlot.style.name,
        icon: AppIcons.colorTool,
        label: l10n.colorLabel,
        onTap: () {
          contextCtrl.closePanel();
          ctrl.toggleSlot(ShapeToolSlot.style);
        },
      ),
      ShapeToolSlot.border => ToolbarSlot(
        id: ShapeToolSlot.border.name,
        icon: AppIcons.borderTool,
        label: l10n.borderTool,
        onTap: () {
          contextCtrl.closePanel();
          ctrl.toggleSlot(ShapeToolSlot.border);
        },
      ),
      ShapeToolSlot.shadow => ToolbarSlot(
        id: ShapeToolSlot.shadow.name,
        icon: AppIcons.shadowTool,
        label: l10n.shadowTool,
        onTap: () {
          contextCtrl.closePanel();
          ctrl.toggleSlot(ShapeToolSlot.shadow);
        },
      ),
      // Replace is a one-shot secondary action (opens the picker)
      // rather than an inline panel. Keeping it after the divider
      // preserves access without crowding the core styling tabs.
      ShapeToolSlot.replace => ToolbarSlot(
        id: ShapeToolSlot.replace.name,
        icon: AppIcons.replace,
        label: l10n.replaceTool,
        tier: SlotTier.tier2,
        onTap: () {
          contextCtrl.closePanel();
          onReplaceTap();
        },
      ),
    };
  }
}
