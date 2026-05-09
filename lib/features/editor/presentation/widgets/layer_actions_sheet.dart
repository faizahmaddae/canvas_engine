import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/core/editor_layer.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../text/application/text_tool_controller.dart';
import '../../text/presentation/text_resize_mode_picker.dart';
import 'layer_actions.dart';

/// Mobile-friendly contextual action sheet for a selected layer.
///
/// Opened from the `⋯` overflow pill on the floating contextual
/// toolbars (text / paint). Holds the secondary, lower-frequency
/// structural actions so the floating bar itself stays a small,
/// glanceable strip of the highest-frequency controls.
///
/// Pattern is a standard Material `showModalBottomSheet` with a drag
/// handle — the established interaction surface on this app (see
/// `text_mode_toolbar.dart`'s effect / layout sheets and
/// `paint_size_sheet.dart`). Avoids any desktop-style anchored
/// dropdown, which on mobile would either occlude the canvas or end
/// up inside the safe-area inset.
///
/// All actions delegate to [LayerActions] so undo/redo, haptics,
/// selection promotion and edge cases (empty doc after delete,
/// already-topmost reorder, etc.) live in exactly one place.
Future<void> showLayerActionsSheet(
  BuildContext context,
  WidgetRef ref,
  EditorLayer layer,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _LayerActionsSheet(layer: layer, parentRef: ref),
  );
}

class _LayerActionsSheet extends StatelessWidget {
  const _LayerActionsSheet({required this.layer, required this.parentRef});

  final EditorLayer layer;

  /// We use the parent screen's [WidgetRef] to drive providers rather
  /// than the bottom-sheet's own ref. The sheet is mounted in a root
  /// overlay [Navigator] which sits OUTSIDE the editor `ProviderScope`
  /// in some embedder configurations — reaching providers via
  /// `parentRef` guarantees we always hit the same scope the floating
  /// toolbar is reading from. Cheap and correct.
  final WidgetRef parentRef;

  @override
  Widget build(BuildContext context) {
    // Reorder availability is captured at sheet-open time. The sheet
    // is short-lived and modal — re-querying live would only matter
    // for the unusual case of an external tool reordering layers
    // while the sheet is open.
    final canForward = LayerActions.canBringForward(parentRef, layer);
    final canBackward = LayerActions.canSendBackward(parentRef, layer);
    // Only true text layers expose the resize-mode toggle. Emoji
    // stickers are stored as TextLayer but the scaleText / resizeBox
    // distinction is meaningless for a single emoji glyph.
    final textLayer =
        (layer is TextLayer && !(layer as TextLayer).isSticker)
            ? layer as TextLayer
            : null;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Duplicate'),
            onTap: () {
              Navigator.of(context).pop();
              LayerActions.duplicate(parentRef, layer);
            },
          ),
          ListTile(
            enabled: canForward,
            leading: const Icon(Icons.flip_to_front_rounded),
            title: const Text('Bring forward'),
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
            title: const Text('Send backward'),
            onTap: !canBackward
                ? null
                : () {
                    Navigator.of(context).pop();
                    LayerActions.sendBackward(parentRef, layer);
                  },
          ),
          ListTile(
            leading: Icon(layer.locked
                ? Icons.lock_open_rounded
                : Icons.lock_outline_rounded),
            title: Text(layer.locked ? 'Unlock layer' : 'Lock layer'),
            onTap: () {
              Navigator.of(context).pop();
              LayerActions.toggleLock(parentRef, layer);
            },
          ),
          // Text-only: resize behavior is a secondary, advanced option.
          // It belongs here in the overflow rather than on the always-on
          // floating toolbar — most users never change it from the
          // default.
          if (textLayer != null)
            ListTile(
              leading: Icon(textResizeModeIcon(textLayer.resizeMode)),
              title: const Text('Resize behavior'),
              subtitle: Text(textResizeModeLabel(textLayer.resizeMode)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.of(context).pop();
                final current = textLayer.resizeMode;
                final picked = await pickTextResizeMode(context, current);
                if (picked != null && picked != current) {
                  parentRef
                      .read(textToolControllerProvider.notifier)
                      .setResizeMode(picked);
                }
              },
            ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () async {
              // Show the protected-base-photo confirm (if applicable)
              // BEFORE popping this sheet, so the dialog has a valid
              // mounted context. Pop the sheet only after the user
              // has decided.
              await LayerActions.delete(context, parentRef, layer);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
