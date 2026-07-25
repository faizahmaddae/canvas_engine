import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/context_toolbar_controller.dart';
import '../../engine/core/editor_layer.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import 'layer_actions.dart';
import 'layer_overflow_sheet.dart';
import '../../../../app/theme/app_icons.dart';

/// Bottom contextual strip for group selections.
///
/// Single-layer editing routes to the type-specific toolbars. Once
/// multiple layers are selected, the operations become group-level:
/// the three batch structural actions, alignment/distribution, shared
/// opacity, and the selected-layer actions sheet for follow-ups.
///
/// **Why duplicate / lock / delete are on the strip (tb6 1/5).** The
/// approved prototype put them there — one tap each — and the first
/// implementation moved them into the overflow sheet, which quietly
/// made every batch structural action cost two taps. Multi-select
/// exists to act on several layers at once; burying the acting part
/// one level down is the regression that review caught. They stay in
/// the overflow sheet too (it is the capability-driven union every
/// mode shares), so this adds reach without removing any.
class MultiSelectModeToolbar extends ConsumerWidget {
  const MultiSelectModeToolbar({
    super.key,
    required this.layers,
    this.onOpenLayers,
  });

  final List<EditorLayer> layers;
  final VoidCallback? onOpenLayers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (layers.length < 2) return const SizedBox.shrink();
    final l10n = context.l10n;
    final primary = layers.last;
    final contextPanel = ref.watch(contextToolbarControllerProvider);
    final contextCtrl = ref.read(contextToolbarControllerProvider.notifier);
    // Same read the overflow sheet's lock row uses, so the strip tile
    // and the sheet row can never disagree about which verb to show.
    final allLocked = layers.every((l) => l.locked);
    final slots = <ToolbarSlot>[
      ToolbarSlot(
        id: 'align',
        icon: AppIcons.alignLeft,
        label: l10n.alignAction,
        onTap: () => contextCtrl.toggle(ContextToolPanel.align),
      ),
      // ── the batch structural trio, in the prototype's cluster ────
      // Delete sits LAST of the three rather than first (where the
      // prototype had it): a destructive action should not be the
      // tile a thumb lands on when reaching for duplicate.
      ToolbarSlot(
        id: 'duplicate',
        icon: AppIcons.duplicate,
        label: l10n.duplicateAction,
        onTap: () {
          contextCtrl.closePanel();
          LayerActions.duplicateMany(ref, layers, label: l10n.duplicateAction);
        },
      ),
      ToolbarSlot(
        id: 'lock',
        icon: allLocked ? AppIcons.unlock : AppIcons.lock,
        // The SHORT verb on the tile — a dock tile has room for one
        // word before it ellipsises. The history entry keeps the long
        // form, which is what the undo list has to be explicit about.
        label: allLocked ? l10n.unlockAction : l10n.lockAction,
        onTap: () {
          contextCtrl.closePanel();
          LayerActions.setLockedMany(
            ref,
            layers,
            locked: !allLocked,
            label: allLocked ? l10n.unlockLayerAction : l10n.lockLayerAction,
          );
        },
      ),
      ToolbarSlot(
        id: 'delete',
        icon: AppIcons.delete,
        label: l10n.deleteAction,
        onTap: () {
          contextCtrl.closePanel();
          // No confirm: the protected base photo is filtered out
          // inside deleteMany, and the whole batch is ONE composite,
          // so a single undo brings every layer back.
          LayerActions.deleteMany(ref, layers, label: l10n.deleteAction);
        },
      ),
      ToolbarSlot(
        id: 'opacity',
        icon: AppIcons.opacity,
        label: l10n.opacityLabel,
        onTap: () => contextCtrl.toggle(ContextToolPanel.opacity),
      ),
      ToolbarSlot(
        id: 'layers',
        icon: AppIcons.layersPanel,
        label: l10n.layersTooltip,
        enabled: onOpenLayers != null,
        onTap: () {
          contextCtrl.closePanel();
          onOpenLayers?.call();
        },
      ),
      ToolbarSlot(
        id: 'more',
        icon: AppIcons.moreActions,
        label: l10n.moreLabel,
        semanticLabel: l10n.moreActionsSemantics,
        onTap: () {
          contextCtrl.closePanel();
          showLayerOverflowSheet(
            context,
            ref,
            layer: primary,
            selectedLayers: layers,
            onOpenLayers: onOpenLayers,
          );
        },
      ),
    ];
    return SlotStrip(
      slots: slots,
      activeId: switch (contextPanel) {
        ContextToolPanel.align => 'align',
        ContextToolPanel.opacity => 'opacity',
        null => null,
      },
    );
  }
}
