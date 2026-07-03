import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/core/editor_layer.dart';
import 'layer_actions.dart';

Future<void> showSelectedLayerActionsSheet(
  BuildContext context,
  WidgetRef ref,
  EditorLayer layer, {
  List<EditorLayer>? selectedLayers,
  VoidCallback? onOpenLayers,
}) {
  final layers = selectedLayers ?? <EditorLayer>[layer];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _SelectedLayerActionsSheet(
      hostContext: context,
      layer: layer,
      selectedLayers: layers,
      parentRef: ref,
      onOpenLayers: onOpenLayers,
    ),
  );
}

class _SelectedLayerActionsSheet extends StatelessWidget {
  const _SelectedLayerActionsSheet({
    required this.hostContext,
    required this.layer,
    required this.selectedLayers,
    required this.parentRef,
    this.onOpenLayers,
  });

  final BuildContext hostContext;
  final EditorLayer layer;
  final List<EditorLayer> selectedLayers;
  final WidgetRef parentRef;
  final VoidCallback? onOpenLayers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isMulti = selectedLayers.length > 1;
    final canForward =
        !isMulti && LayerActions.canBringForward(parentRef, layer);
    final canBackward =
        !isMulti && LayerActions.canSendBackward(parentRef, layer);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isMulti ? Icons.checklist_rounded : Icons.tune_rounded,
              ),
              title: Text(
                isMulti
                    ? l10n.multiSelectCount(selectedLayers.length)
                    : l10n.moreActionsSemantics,
              ),
            ),
            if (isMulti) ...[
              if (onOpenLayers != null)
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: Text(l10n.layersTooltip),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenLayers?.call();
                  },
                ),
              const SizedBox(height: 8),
            ],
            if (isMulti)
              const SizedBox.shrink()
            else ...[
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline_rounded),
                title: Text(l10n.renameAction),
                onTap: () async {
                  Navigator.of(context).pop();
                  if (!hostContext.mounted) return;
                  await LayerActions.rename(hostContext, parentRef, layer);
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
              const Divider(height: 1),
              if (onOpenLayers != null)
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: Text(l10n.layersTooltip),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenLayers?.call();
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
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.error,
                ),
                title: Text(
                  l10n.deleteAction,
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  if (!hostContext.mounted) return;
                  await LayerActions.delete(hostContext, parentRef, layer);
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
