import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/text_commands.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/sticker_picker_sheet.dart';
import 'sticker_panel_shell.dart';
import '../../../../app/theme/app_icons.dart';

/// Body for the Sticker "Replace" tab. Big preview of the current
/// glyph + a single centered CTA that re-opens the emoji picker
/// and swaps the glyph in place. Preserves transform / id / style
/// so the layer stays exactly where (and how big) it was.
class StickerReplaceBody extends ConsumerWidget {
  const StickerReplaceBody({super.key, required this.layer});

  final TextLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    return StickerPanelShell(
      title: context.l10n.replaceTool,
      icon: AppIcons.replace,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header already says "Replace" — no duplicate SectionLabel.
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: tokens.border),
              ),
              alignment: Alignment.center,
              child: Text(layer.content, style: const TextStyle(fontSize: 52)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.icon(
              onPressed: () => _replace(context, ref),
              icon: const Icon(AppIcons.replace),
              label: Text(context.l10n.chooseAnotherStickerAction),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.brand,
                foregroundColor: tokens.onBrand,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _replace(BuildContext context, WidgetRef ref) async {
    EditorHaptics.tap();
    final glyph = await showStickerPickerSheet(context);
    if (glyph == null || glyph == layer.content) return;
    // Re-use UpdateTextCommand so the swap participates in the
    // standard undo stack and merges with later edits in the same
    // way text edits do. Style is preserved verbatim.
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          UpdateTextCommand(
            layerId: layer.id,
            // content-only edit (sticker glyph swap). Style preserved
            // implicitly by the apply() fallback to layer.style.
            content: glyph,
          ),
        );
  }
}
