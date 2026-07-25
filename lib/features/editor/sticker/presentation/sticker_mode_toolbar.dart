import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../toolbar/application/dock_tool_controller.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import '../../presentation/widgets/layer_overflow_sheet.dart';
import '../application/sticker_tool_controller.dart';
import '../../../../app/theme/app_icons.dart';

// Barrel re-exports so callers (e.g. EditorScreen) can keep
// importing `sticker_mode_toolbar.dart` and pick up every sticker
// surface (toolbar + shell + 3 bodies) from one place.
export 'sticker_panel_shell.dart';
export 'sticker_replace_body.dart';
export 'sticker_size_body.dart';
export 'sticker_style_body.dart';

/// Bottom toolbar shown when an emoji-sticker [TextLayer] is the
/// current selection. Three tabs (Phase 1):
///
///  * **Style** — disabled until real sticker effects ship; kept in
///    the strip so the dock grammar stays stable across modes.
///  * **Size** — quick S / M / L / XL preset resize.
///  * **Replace** — re-open the emoji picker, swap the glyph in
///    place (preserves transform + id + history).
///
/// The Text sub-tools (Font / Layout / Background) are intentionally
/// absent — none of them apply to a single emoji glyph.
///
/// `centerWhenFits` keeps the 3 tabs visually balanced on the strip
/// rather than pinned to the leading edge.
class StickerModeToolbar extends ConsumerWidget {
  const StickerModeToolbar({super.key, required this.layer});

  final TextLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openSlot = ref.watch(
      stickerToolControllerProvider.select((s) => s.openSlot),
    );
    final slots = <ToolbarSlot>[
      for (final entry in kStickerStripOrder) _chipFor(context, ref, entry),
    ];
    return SlotStrip(
      slots: slots,
      activeId: openSlot?.name,
      centerWhenFits: true,
    );
  }

  /// Maps one [kStickerStripOrder] entry to its rendered chip. All
  /// icons/labels/actions live here; the ORDER lives only in the
  /// shared list.
  ToolbarSlot _chipFor(
    BuildContext context,
    WidgetRef ref,
    DockStripEntry<StickerToolSlot> entry,
  ) {
    final ctrl = ref.read(stickerToolControllerProvider.notifier);
    final l10n = context.l10n;
    final slot = entry.slot;
    if (slot == null) {
      return switch (entry.actionId) {
        'more' => ToolbarSlot(
          id: 'more',
          icon: AppIcons.moreActions,
          label: l10n.moreLabel,
          semanticLabel: l10n.moreActionsSemantics,
          onTap: () {
            // Same shape as every other mode's More: close this
            // mode's panel first so the sheet never stacks on one.
            ctrl.closePanel();
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
        _ => throw StateError(
          'Unknown sticker strip action: ${entry.actionId}',
        ),
      };
    }
    return switch (slot) {
      StickerToolSlot.style => ToolbarSlot(
        id: StickerToolSlot.style.name,
        icon: AppIcons.lookTool,
        label: l10n.styleTool,
        onTap: () => ctrl.toggleSlot(StickerToolSlot.style),
      ),
      StickerToolSlot.size => ToolbarSlot(
        id: StickerToolSlot.size.name,
        icon: AppIcons.sizeTool,
        label: l10n.sizeTool,
        onTap: () => ctrl.toggleSlot(StickerToolSlot.size),
      ),
      StickerToolSlot.replace => ToolbarSlot(
        id: StickerToolSlot.replace.name,
        icon: AppIcons.replace,
        label: l10n.replaceTool,
        onTap: () => ctrl.toggleSlot(StickerToolSlot.replace),
      ),
    };
  }
}
