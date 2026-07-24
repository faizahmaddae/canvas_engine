import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/context_toolbar_controller.dart';
import '../../engine/core/editor_layer.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import 'layer_overflow_sheet.dart';

/// Bottom contextual strip for group selections.
///
/// Single-layer editing routes to the type-specific toolbars. Once
/// multiple layers are selected, the operations become group-level:
/// alignment/distribution, shared opacity, and the selected-layer
/// actions sheet for review/layer-stack follow-ups.
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
    final slots = <ToolbarSlot>[
      ToolbarSlot(
        id: 'align',
        icon: Icons.align_horizontal_left_rounded,
        label: l10n.alignAction,
        onTap: () => contextCtrl.toggle(ContextToolPanel.align),
      ),
      ToolbarSlot(
        id: 'opacity',
        icon: Icons.opacity,
        label: l10n.opacityLabel,
        onTap: () => contextCtrl.toggle(ContextToolPanel.opacity),
      ),
      ToolbarSlot(
        id: 'layers',
        icon: Icons.layers_outlined,
        label: l10n.layersTooltip,
        enabled: onOpenLayers != null,
        onTap: () {
          contextCtrl.closePanel();
          onOpenLayers?.call();
        },
      ),
      ToolbarSlot(
        id: 'more',
        icon: Icons.more_horiz_rounded,
        label: l10n.moreActionsSemantics,
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
