import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/layer_state_commands.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/modules/text/text_layer.dart';
import 'layer_actions.dart';
import 'layer_opacity_control.dart';
import 'layer_thumbnail.dart';

/// Right-side drawer listing every layer in the document, topmost first.
///
/// Selection, reorder, visibility, lock and delete all route through the
/// existing command system so undo/redo continues to work. This widget
/// holds no layer management logic of its own — it reads state and
/// dispatches commands.
class LayersPanel extends ConsumerWidget {
  const LayersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(documentControllerProvider);
    final selection = ref.watch(selectionControllerProvider);
    final multiMode = ref.watch(selectionModeProvider) == SelectionMode.multi;
    final total = doc.layers.length;

    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(
          children: [
            _PanelHeader(count: total, selectionCount: selection.count),
            const Divider(height: 1),
            Expanded(
              child: total == 0
                  ? const _EmptyState()
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: total,
                      itemBuilder: (context, displayIndex) {
                        // Top of list == top of z-order (last in layers).
                        final modelIndex = total - 1 - displayIndex;
                        final layer = doc.layers[modelIndex];
                        return _LayerTile(
                          key: ValueKey(layer.id),
                          layer: layer,
                          displayIndex: displayIndex,
                          modelIndex: modelIndex,
                          // Multi mode renders MEMBERSHIP, not just the
                          // primary — every checked row is in the group
                          // (tb3 5/7: the drawer can extend a
                          // multi-selection, not only replace it).
                          isSelected: multiMode
                              ? selection.contains(layer.id)
                              : selection.selectedId == layer.id,
                          isPrimary: selection.selectedId == layer.id,
                          multiMode: multiMode,
                          total: total,
                        );
                      },
                      onReorder: (oldDisplay, newDisplay) {
                        // Convert reversed display indices back to model
                        // indices for the engine.
                        var adjusted = newDisplay;
                        if (newDisplay > oldDisplay) adjusted -= 1;
                        final from = total - 1 - oldDisplay;
                        final to = total - 1 - adjusted;
                        if (from == to) return;
                        // Mirror the engine's base-photo pin
                        // (EditorDocument.reorderLayer): the command
                        // silently refuses moves into/below the base,
                        // which read as a broken drag. Say why instead.
                        final baseId = doc.basePhotoLayerId;
                        if (doc.projectKind == ProjectKind.photo &&
                            baseId != null) {
                          final baseIndex = doc.layers.indexWhere(
                            (l) => l.id == baseId,
                          );
                          if (baseIndex >= 0 &&
                              (from == baseIndex || to <= baseIndex)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.l10n.basePhotoPinnedToBack,
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                        }
                        ref
                            .read(documentControllerProvider.notifier)
                            .execute(ReorderLayerCommand(from: from, to: to));
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.count, required this.selectionCount});
  final int count;
  final int selectionCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                context.l10n.layersTooltip,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text('$count', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (selectionCount > 1 || count > 1) ...[
            const SizedBox(height: 4),
            Text(
              selectionCount > 1
                  ? context.l10n.multiSelectCount(selectionCount)
                  : context.l10n.longPressCanvasMultiSelectHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          context.l10n.noLayersEmpty,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
        ),
      ),
    );
  }
}

class _LayerTile extends ConsumerWidget {
  const _LayerTile({
    super.key,
    required this.layer,
    required this.displayIndex,
    required this.modelIndex,
    required this.isSelected,
    required this.isPrimary,
    required this.multiMode,
    required this.total,
  });

  final EditorLayer layer;
  final int displayIndex;
  final int modelIndex;

  /// Single mode: is this the primary selection. Multi mode: is this
  /// layer a MEMBER of the group ([SelectionState.contains]). Drives
  /// the highlight + the membership check indicator.
  final bool isSelected;

  /// Is this the PRIMARY selection. The per-layer controls that only
  /// make sense once (rename, opacity slider) stay pinned to the
  /// primary — exactly the rows that showed them before multi-mode
  /// membership rendering landed (tb3 5/7).
  final bool isPrimary;

  /// True while the editor is in multi-select mode — flips the row
  /// tap from replace-selection to toggle-membership and shows the
  /// membership check indicator.
  final bool multiMode;

  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Watch only this row's protected-base status, not the whole
    // document by value. A plain `ref.watch(documentControllerProvider)`
    // rebuilt EVERY mounted tile on any committed edit (visibility,
    // lock, transform, effect, reorder) because the document `==` folds
    // in the full layer list — 50 tiles re-running their thumbnails on a
    // single toggle. `.select` collapses that to a rebuild only when
    // this tile's own protected flag actually flips.
    // Two reasons we hide the row's delete button:
    //   1. The layer's own capability flag forbids it (e.g. a future
    //      pinned background).
    //   2. The document marks this layer as the protected base
    //      photo of a photo project. The base photo IS the
    //      project; deleting it from a row tap would feel like
    //      throwing the document away. The user can still remove
    //      it via the AppBar Delete (which routes through
    //      [LayerActions.delete] and shows a confirm dialog) --
    //      we keep the destructive action one step away from a
    //      casual mis-tap in the panel.
    final protected = ref.watch(
      documentControllerProvider.select(
        (d) => d.isProtectedBasePhoto(layer.id),
      ),
    );
    final canDelete = layer.capabilities.deletable && !protected;
    final bg = isSelected
        ? AppTokens.of(context).accent.withValues(alpha: 0.12)
        : Colors.transparent;

    // A drawer row is the ONLY place a screen-reader user can reach a
    // layer — the canvas is pixels to them. So the row has to
    // announce what the sighted user sees at a glance: which layer,
    // whether it is the current selection (or a member of the group),
    // and whether it is locked (tb5 2/9). Without this it announced
    // as an unlabelled button with a thumbnail.
    return Semantics(
      container: true,
      selected: isSelected,
      label: _rowSemanticLabel(
        context,
        layer,
        modelIndex: modelIndex,
        protected: protected,
      ),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: () {
            if (multiMode) {
              // Multi mode: the row TOGGLES membership (tb3 5/7)
              // instead of replacing the selection. Locked layers are
              // no-ops — the canvas hit-test never admits them into a
              // group either, and a group transform must not move a
              // locked layer (that includes the protected base photo).
              if (layer.locked) return;
              final selectionCtl = ref.read(
                selectionControllerProvider.notifier,
              );
              selectionCtl.toggle(layer.id);
              // Existing rule: the mode ends when membership can no
              // longer form a group (mirrors the editor's commit-tick
              // prune listener at < 2).
              if (ref.read(selectionControllerProvider).selectedIds.length <
                  2) {
                ref.read(selectionModeProvider.notifier).exitMulti();
              }
              return;
            }
            ref.read(selectionControllerProvider.notifier).select(layer.id);
            // Protected base photo: tapping the row is the user's
            // way to open the canvas-level photo tools (Style /
            // Crop / Filters / Adjust). Auto-close the drawer so the
            // selection frame + bottom Image tools become visible
            // without an extra tap. Other layers keep the panel
            // open so users can curate the stack rapidly.
            if (protected) {
              Navigator.of(context).maybePop();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // Locked layers are not drag-reorderable: the lock
                    // contract (EditorLayer.locked) protects a layer from
                    // being moved, and z-order is a move. This also pins the
                    // base photo — imported locked — to the bottom, so a
                    // drag can't bury content under it (the engine
                    // `reorderLayer` clamp is the backstop; this removes the
                    // affordance so the tile doesn't visually jump and snap
                    // back). The handle shows dimmed rather than vanishing so
                    // the row layout stays stable.
                    if (layer.locked)
                      Opacity(
                        opacity: 0.35,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      )
                    else
                      ReorderableDragStartListener(
                        index: displayIndex,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    // Membership check indicator — multi mode only, so
                    // single-mode rows stay pixel-identical. Locked
                    // layers show the dimmed off state permanently
                    // (they cannot join a group; the row tap is a
                    // no-op for them too).
                    if (multiMode)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 4),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          key: ValueKey('layers-multi-check-${layer.id}'),
                          size: 18,
                          color: isSelected
                              ? AppTokens.of(context).accent
                              : Theme.of(context).hintColor,
                        ),
                      ),
                    LayerThumbnail(layer: layer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName(layer, modelIndex),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected ? FontWeight.w600 : null,
                              color: layer.visible ? null : theme.disabledColor,
                            ),
                          ),
                          Text(
                            layer.type,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isPrimary)
                      _IconAction(
                        icon: Icons.drive_file_rename_outline_rounded,
                        tooltip: context.l10n.renameAction,
                        onTap: () => LayerActions.rename(context, ref, layer),
                      ),
                    _IconAction(
                      icon: layer.locked ? Icons.lock : Icons.lock_open,
                      tooltip: layer.locked
                          ? context.l10n.unlockAction
                          : context.l10n.lockAction,
                      highlighted: layer.locked,
                      onTap: () {
                        ref
                            .read(documentControllerProvider.notifier)
                            .execute(
                              SetLayerLockCommand(
                                layerId: layer.id,
                                locked: !layer.locked,
                              ),
                            );
                      },
                    ),
                    _IconAction(
                      icon: layer.visible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      tooltip: layer.visible
                          ? context.l10n.hideAction
                          : context.l10n.showAction,
                      highlighted: !layer.visible,
                      onTap: () {
                        ref
                            .read(documentControllerProvider.notifier)
                            .execute(
                              SetLayerVisibilityCommand(
                                layerId: layer.id,
                                visible: !layer.visible,
                              ),
                            );
                      },
                    ),
                    _IconAction(
                      icon: Icons.delete_outline,
                      tooltip: protected
                          ? context.l10n.protectedBasePhotoTooltip
                          : context.l10n.deleteAction,
                      enabled: canDelete,
                      onTap: () {
                        // Route through the shared facade so confirm /
                        // selection-promotion / project-kind flip stay
                        // in one place. Direct `RemoveLayerCommand`
                        // dispatch from here would bypass the
                        // base-photo protection in `LayerActions.delete`
                        // (the previous bug).
                        LayerActions.delete(context, ref, layer);
                      },
                    ),
                  ],
                ),
                // Opacity slider — only shown for the selected layer to
                // keep the unselected rows compact. Drag previews route
                // through `liveReplace` (no commit-version bump, no
                // autosave thrash, no undo entries); the final value is
                // committed via `execute(SetLayerOpacityCommand)` on
                // change-end so undo/redo and autosave see exactly one
                // entry per drag gesture.
                if (isPrimary) LayerOpacityControl(layer: layer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What VoiceOver reads for a row: the layer's name, then only the
  /// states that are actually true. Ordinary rows stay a bare name —
  /// appending "unlocked, visible" to every one of 200 layers would
  /// bury the signal it exists to carry.
  String _rowSemanticLabel(
    BuildContext context,
    EditorLayer layer, {
    required int modelIndex,
    required bool protected,
  }) {
    final l10n = context.l10n;
    // Same name the row shows — an unnamed layer's "#3" has to match
    // between what is read and what is seen.
    final parts = <String>[_displayName(layer, modelIndex)];
    if (protected) parts.add(l10n.basePhotoLabel);
    if (layer.locked) parts.add(l10n.lockedLabel);
    if (!layer.visible) parts.add(l10n.hiddenLabel);
    return parts.join(' · ');
  }

  String _displayName(EditorLayer layer, int modelIndex) {
    if (layer.name != null && layer.name!.isNotEmpty) return layer.name!;
    if (layer is TextLayer) {
      final t = layer.content.trim();
      if (t.isNotEmpty) return t.length > 28 ? '${t.substring(0, 28)}…' : t;
    }
    return '${layer.type[0].toUpperCase()}${layer.type.substring(1)} '
        '#${modelIndex + 1}';
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Theme.of(context).disabledColor
        : highlighted
        ? AppTokens.of(context).accent
        : null;
    return IconButton(
      tooltip: tooltip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, color: color),
    );
  }
}
