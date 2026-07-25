import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/context_toolbar_controller.dart';
import '../../application/mask_edit_controller.dart';
import '../../crop/application/crop_controller.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../presentation/widgets/layer_overflow_sheet.dart';
import '../../toolbar/application/dock_tool_controller.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import '../application/image_tool_controller.dart';
import 'image_replace_flow.dart';
import '../../../../app/theme/app_icons.dart';

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
          icon: AppIcons.opacity,
          label: l10n.opacityLabel,
          onTap: () {
            imageCtrl.closePanel();
            contextCtrl.toggle(ContextToolPanel.opacity);
          },
        ),
        'more' => ToolbarSlot(
          id: 'more',
          icon: AppIcons.moreActions,
          label: l10n.moreLabel,
          semanticLabel: l10n.moreActionsSemantics,
          onTap: () {
            imageCtrl.closePanel();
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
        _ => throw StateError('Unknown image strip action: ${entry.actionId}'),
      };
    }
    return switch (slot) {
      ImageToolSlot.look => ToolbarSlot(
        id: ImageToolSlot.look.name,
        icon: AppIcons.lookTool,
        label: l10n.lookTool,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.look);
        },
      ),
      ImageToolSlot.border => ToolbarSlot(
        id: ImageToolSlot.border.name,
        icon: AppIcons.borderTool,
        label: l10n.borderTool,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.border);
        },
      ),
      ImageToolSlot.shadow => ToolbarSlot(
        id: ImageToolSlot.shadow.name,
        icon: AppIcons.shadowTool,
        label: l10n.shadowTool,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.shadow);
        },
      ),
      ImageToolSlot.replace => ToolbarSlot(
        id: ImageToolSlot.replace.name,
        icon: AppIcons.replace,
        label: imageReplacementTileLabel(context, layer),
        semanticLabel: imageReplacementActionLabel(context, layer),
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
        icon: AppIcons.cropTool,
        label: l10n.cropTool,
        semanticLabel: l10n.cropImageAction,
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
        icon: AppIcons.squareShape,
        label: l10n.shapeTool,
        tier: SlotTier.tier2,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.shape);
        },
      ),
      // Selective masking used to be a tonal button at the bottom of
      // the Effects panel — three taps deep, and invisible unless you
      // already knew the panel existed. It is the layer's second
      // spatial edit (crop being the first), so it earns a strip tile.
      // Capability guard: a mask with nothing to mask is a lying
      // control, so the tile disables until the stack has an effect.
      ImageToolSlot.selective => ToolbarSlot(
        id: ImageToolSlot.selective.name,
        icon: AppIcons.selectiveMask,
        label: l10n.selectiveMaskLabel,
        tier: SlotTier.tier2,
        enabledBuilder: () => layer.effects.effects.isNotEmpty,
        onTap: () {
          EditorHaptics.tap();
          contextCtrl.closePanel();
          // The mode's chrome replaces the dock; leaving openSlot set
          // would re-mount a stale panel on exit.
          imageCtrl.closePanel();
          ref
              .read(maskEditControllerProvider.notifier)
              .open(layer.id, priorSelectionId: layer.id);
        },
      ),
      ImageToolSlot.effects => ToolbarSlot(
        id: ImageToolSlot.effects.name,
        icon: AppIcons.effects,
        label: l10n.effectsTool,
        tier: SlotTier.tier2,
        onTap: () {
          contextCtrl.closePanel();
          imageCtrl.toggleSlot(ImageToolSlot.effects);
        },
      ),
    };
  }
}
