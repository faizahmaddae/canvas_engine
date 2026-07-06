// More sheet for the text tool (Step 1 of the text-tool redesign:
// the one text bar's «بیشتر» destination). Moved verbatim out of
// the deleted text_floating_toolbar.dart — the floating pill is
// gone; this sheet keeps every one of its actions reachable.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../l10n/l10n.dart';
import '../../../application/context_toolbar_controller.dart';
import '../../../engine/modules/text/text_layer.dart';
import '../../../text/application/text_tool_controller.dart';
import '../../../text/presentation/text_direction_mode_picker.dart';
import '../../../text/presentation/text_edit_flow.dart';
import '../../../text/presentation/text_resize_mode_picker.dart';
import '../../widgets/layer_actions.dart';

/// Text-specific overflow sheet opened by the text bar's «بیشتر»
/// tile. Combines:
///   * Edit text — opens the inline keyboard editor with live preview.
///   * Bold / Italic / Underline — relocated from the standalone Bold
///     pill that used to live on the floating bar.
///   * Standard layer ops (duplicate, reorder, lock, resize behavior,
///     delete) — kept here so every text action is reachable in ≤ 2
///     taps without crowding the floating bar.
Future<void> showTextMoreSheet(
  BuildContext context,
  WidgetRef ref,
  TextLayer layer,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _TextMoreSheet(layer: layer, parentRef: ref),
  );
}

class _TextMoreSheet extends StatelessWidget {
  const _TextMoreSheet({required this.layer, required this.parentRef});

  final TextLayer layer;
  // We use the parent screen's [WidgetRef] for the same reason
  // [_LayerActionsSheet] does — the modal sheet is mounted in a root
  // [Navigator] which sits OUTSIDE the editor `ProviderScope` in some
  // embedder configurations.
  final WidgetRef parentRef;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = AppTokens.of(context);
    final canForward = LayerActions.canBringForward(parentRef, layer);
    final canBackward = LayerActions.canSendBackward(parentRef, layer);
    final style = layer.style;
    final l10n = context.l10n;

    return SafeArea(
      // The action list (Edit · B/I/U · Duplicate · Reorder · Lock ·
      // Resize · Delete) is too tall to fit in the default modal
      // sheet height on shorter devices. Wrap in a scroll view so
      // the bottom rows stay reachable instead of overflowing.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(l10n.editTextAction),
              onTap: () async {
                Navigator.of(context).pop();
                await showEditTextLayerFlow(context, parentRef, layer);
              },
            ),
            ListTile(
              leading: const Icon(Icons.align_horizontal_left_rounded),
              title: Text(l10n.alignAction),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).pop();
                parentRef
                    .read(contextToolbarControllerProvider.notifier)
                    .open(ContextToolPanel.align);
              },
            ),
            ListTile(
              leading: const Icon(Icons.opacity),
              title: Text(l10n.opacityLabel),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).pop();
                parentRef
                    .read(contextToolbarControllerProvider.notifier)
                    .open(ContextToolPanel.opacity);
              },
            ),
            const Divider(height: 1),
            // B / I / U toggles — closing the sheet on each tap would
            // be jarring, so they stay inline and the user can flip
            // multiple flags before dismissing.
            ListTile(
              leading: Icon(
                Icons.format_bold_rounded,
                color: style.isBold ? tokens.accent : null,
              ),
              title: Text(l10n.boldAction),
              trailing: style.isBold
                  ? Icon(Icons.check_rounded, color: tokens.accent)
                  : null,
              onTap: () => parentRef
                  .read(textToolControllerProvider.notifier)
                  .setBold(!style.isBold),
            ),
            ListTile(
              leading: Icon(
                Icons.format_italic_rounded,
                color: style.italic ? tokens.accent : null,
              ),
              title: Text(l10n.italicAction),
              trailing: style.italic
                  ? Icon(Icons.check_rounded, color: tokens.accent)
                  : null,
              onTap: () => parentRef
                  .read(textToolControllerProvider.notifier)
                  .setItalic(!style.italic),
            ),
            ListTile(
              leading: Icon(
                Icons.format_underline_rounded,
                color: style.underline ? tokens.accent : null,
              ),
              title: Text(l10n.underlineAction),
              trailing: style.underline
                  ? Icon(Icons.check_rounded, color: tokens.accent)
                  : null,
              onTap: () => parentRef
                  .read(textToolControllerProvider.notifier)
                  .setUnderline(!style.underline),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: Text(l10n.renameAction),
              onTap: () async {
                await LayerActions.rename(context, parentRef, layer);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(l10n.duplicateAction),
              onTap: () {
                Navigator.of(context).pop();
                LayerActions.duplicate(parentRef, layer);
              },
            ),
            ListTile(
              enabled: canForward,
              leading: const Icon(Icons.flip_to_front_rounded),
              title: Text(l10n.bringForwardAction),
              onTap: !canForward
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      LayerActions.bringForward(parentRef, layer);
                    },
            ),
            ListTile(
              enabled: canBackward,
              leading: const Icon(Icons.flip_to_back_rounded),
              title: Text(l10n.sendBackwardAction),
              onTap: !canBackward
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      LayerActions.sendBackward(parentRef, layer);
                    },
            ),
            ListTile(
              leading: Icon(
                layer.locked
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
              ),
              title: Text(
                layer.locked ? l10n.unlockLayerAction : l10n.lockLayerAction,
              ),
              onTap: () {
                Navigator.of(context).pop();
                LayerActions.toggleLock(parentRef, layer);
              },
            ),
            ListTile(
              leading: Icon(textResizeModeIcon(layer.resizeMode)),
              title: Text(l10n.resizeBehaviorTitle),
              subtitle: Text(
                localizedTextResizeModeLabel(context, layer.resizeMode),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.of(context).pop();
                final current = layer.resizeMode;
                final picked = await pickTextResizeMode(context, current);
                if (picked != null && picked != current) {
                  parentRef
                      .read(textToolControllerProvider.notifier)
                      .setResizeMode(picked);
                }
              },
            ),
            ListTile(
              leading: Icon(textDirectionModeIcon(layer.textDirectionMode)),
              title: Text(l10n.textDirectionTitle),
              subtitle: Text(
                localizedTextDirectionModeLabel(
                  context,
                  layer.textDirectionMode,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.of(context).pop();
                final current = layer.textDirectionMode;
                final picked = await pickTextDirectionMode(context, current);
                if (picked != null && picked != current) {
                  parentRef
                      .read(textToolControllerProvider.notifier)
                      .setTextDirectionMode(picked);
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: Text(
                l10n.deleteAction,
                style: TextStyle(color: scheme.error),
              ),
              onTap: () async {
                await LayerActions.delete(context, parentRef, layer);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

