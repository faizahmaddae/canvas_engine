import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../toolbar/domain/toolbar_slot.dart';
import '../../toolbar/presentation/slot_strip.dart';
import '../application/sticker_tool_controller.dart';

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
    final ctrl = ref.read(stickerToolControllerProvider.notifier);
    final l10n = context.l10n;
    final slots = <ToolbarSlot>[
      ToolbarSlot(
        id: StickerToolSlot.style.name,
        icon: Icons.auto_awesome_outlined,
        label: l10n.styleTool,
        onTap: () => ctrl.toggleSlot(StickerToolSlot.style),
      ),
      ToolbarSlot(
        id: StickerToolSlot.size.name,
        icon: Icons.photo_size_select_large_rounded,
        label: l10n.sizeTool,
        onTap: () => ctrl.toggleSlot(StickerToolSlot.size),
      ),
      ToolbarSlot(
        id: StickerToolSlot.replace.name,
        icon: Icons.swap_horiz_rounded,
        label: l10n.replaceTool,
        onTap: () => ctrl.toggleSlot(StickerToolSlot.replace),
      ),
    ];
    return SlotStrip(
      slots: slots,
      activeId: openSlot?.name,
      centerWhenFits: true,
    );
  }
}
