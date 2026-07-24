import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/context_toolbar_controller.dart';
import '../../crop/application/crop_controller.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../presentation/widgets/selected_layer_actions_sheet.dart';
import '../../toolbar/application/dock_tool_controller.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import '../application/image_tool_controller.dart';
import 'image_replace_flow.dart';

// Panel-vs-non-panel classification lives on [ImageToolSlot]. The
// strip renders [kImageStripOrder] verbatim — the same list the
// sibling-swipe walk is derived from, so the two cannot drift.

/// Bottom toolbar shown when an [ImageLayer] is the current
/// selection. Same dock grammar as the text/paint mode toolbars
/// (shared `SlotStrip` → `DockToolTile`) so the active tab gets the
/// same soft-primary tint treatment automatically.
///
/// Crop and Replace are one-shot actions: Crop opens the full-screen
/// crop surface, and Replace / Relink opens the shared image picker
/// flow. Panel-bearing tabs still expand through
/// [imageToolControllerProvider].
class ImageModeToolbar extends ConsumerWidget {
  const ImageModeToolbar({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openSlot = ref.watch(
      imageToolControllerProvider.select((s) => s.openSlot),
    );
    final contextPanel = ref.watch(contextToolbarControllerProvider);
    final slots = <ToolbarSlot>[
      for (final entry in kImageStripOrder) _chipFor(context, ref, entry),
    ];
    return SlotStrip(
      slots: slots,
      activeId: contextPanel == ContextToolPanel.opacity
          ? 'opacity'
          : openSlot?.name,
    );
  }

  /// Maps one [kImageStripOrder] entry to its rendered chip. All
  /// icons/labels/actions live here; the ORDER lives only in the
  /// shared list.
  ToolbarSlot _chipFor(
    BuildContext context,
    WidgetRef ref,
    DockStripEntry<ImageToolSlot> entry,
  ) {
    final imageCtrl = ref.read(imageToolControllerProvider.notifier);
    final contextCtrl = ref.read(contextToolbarControllerProvider.notifier);
    final l10n = context.l10n;
    final slot = entry.slot;
    if (slot == null) {
      return switch (entry.actionId) {
        'opacity' => ToolbarSlot(
          id: 'opacity',
          icon: Icons.opacity,
          label: l10n.opacityLabel,
          onTap: () {
            imageCtrl.closePanel();
            contextCtrl.toggle(ContextToolPanel.opacity);
          },
        ),
        'more' => ToolbarSlot(
          id: 'more',
          icon: Icons.more_horiz_rounded,
          label: l10n.moreActionsSemantics,
          onTap: () {
            imageCtrl.closePanel();
            contextCtrl.closePanel();
            final scaffold = Scaffold.maybeOf(context);
            showSelectedLayerActionsSheet(
              context,
              ref,
              layer,
              onOpenLayers: scaffold == null
                  ? null
                  : () => scaffold.openEndDrawer(),
            );
          },
        ),
        _ => throw StateError('Unknown image strip action: ${entry.actionId}'),
      };
    }
    return switch (slot) {
      ImageToolSlot.style => ToolbarSlot(
        id: ImageToolSlot.style.name,
        icon: Icons.auto_awesome_outlined,
        label: l10n.styleTool,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.style);
        },
      ),
      ImageToolSlot.border => ToolbarSlot(
        id: ImageToolSlot.border.name,
        icon: Icons.border_outer_rounded,
        label: l10n.borderTool,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.border);
        },
      ),
      ImageToolSlot.shadow => ToolbarSlot(
        id: ImageToolSlot.shadow.name,
        icon: Icons.layers_outlined,
        label: l10n.shadowTool,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.shadow);
        },
      ),
      ImageToolSlot.replace => ToolbarSlot(
        id: ImageToolSlot.replace.name,
        icon: Icons.swap_horiz_rounded,
        label: imageReplacementActionLabel(context, layer),
        onTap: () {
          contextCtrl.closePanel();
          replaceImageLayer(
            context,
            ref,
            layer,
            debugLabel: 'imageMode/replaceImageLayer',
          );
        },
      ),
      ImageToolSlot.crop => ToolbarSlot(
        id: ImageToolSlot.crop.name,
        icon: Icons.crop_rotate_rounded,
        label: l10n.cropImageAction,
        tier: SlotTier.tier2,
        // Crop is a full-screen mode — it does NOT toggle the
        // dock's expanded slot. Instead we open the centralised
        // [CropModeOverlay] which is the same surface launched
        // by the main toolbar's Crop button.
        onTap: () {
          EditorHaptics.tap();
          contextCtrl.closePanel();
          // Close any other open dock slot first so leaving crop
          // mode doesn't reveal a stale panel.
          imageCtrl.closePanel();
          // Crop was launched from the image sub-tools, so the
          // user clearly wants the image to remain selected after
          // Done — preserve the existing selection across the crop
          // session.
          ref
              .read(cropControllerProvider.notifier)
              .openCrop(layer.id, priorSelectionId: layer.id);
        },
      ),
      ImageToolSlot.shape => ToolbarSlot(
        id: ImageToolSlot.shape.name,
        icon: Icons.crop_square_rounded,
        label: l10n.shapeTool,
        tier: SlotTier.tier2,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.shape);
        },
      ),
      ImageToolSlot.adjust => ToolbarSlot(
        id: ImageToolSlot.adjust.name,
        icon: Icons.tune_rounded,
        label: l10n.adjustTool,
        tier: SlotTier.tier2,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.adjust);
        },
      ),
      ImageToolSlot.effects => ToolbarSlot(
        id: ImageToolSlot.effects.name,
        icon: Icons.layers_rounded,
        label: l10n.effectsTool,
        tier: SlotTier.tier2,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.effects);
        },
      ),
      ImageToolSlot.filters => ToolbarSlot(
        id: ImageToolSlot.filters.name,
        icon: Icons.auto_fix_high_outlined,
        label: l10n.filtersTool,
        tier: SlotTier.tier2,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.filters);
        },
      ),
    };
  }
}
