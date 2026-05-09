import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/layer_state_commands.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/modules/text/text_layer.dart';
import 'layer_actions.dart';
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
    final total = doc.layers.length;

    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(
          children: [
            _PanelHeader(count: total),
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
                          isSelected: selection.selectedId == layer.id,
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
  const _PanelHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.layers_outlined, size: 20),
          const SizedBox(width: 8),
          Text(
            'Layers',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          Text(
            '$count',
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
          'No layers yet.\nAdd text, image or shape to begin.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).hintColor,
              ),
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
    required this.total,
  });

  final EditorLayer layer;
  final int displayIndex;
  final int modelIndex;
  final bool isSelected;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final doc = ref.watch(documentControllerProvider);
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
    final protected = doc.isProtectedBasePhoto(layer.id);
    final canDelete = layer.capabilities.deletable && !protected;
    final bg = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : Colors.transparent;

    return Material(
      color: bg,
      child: InkWell(
        onTap: () {
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
              ReorderableDragStartListener(
                index: displayIndex,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator,
                      size: 18, color: Colors.grey),
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
                        color:
                            layer.visible ? null : theme.disabledColor,
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
              _IconAction(
                icon: layer.locked ? Icons.lock : Icons.lock_open,
                tooltip: layer.locked ? 'Unlock' : 'Lock',
                highlighted: layer.locked,
                onTap: () {
                  ref.read(documentControllerProvider.notifier).execute(
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
                tooltip: layer.visible ? 'Hide' : 'Show',
                highlighted: !layer.visible,
                onTap: () {
                  ref.read(documentControllerProvider.notifier).execute(
                        SetLayerVisibilityCommand(
                          layerId: layer.id,
                          visible: !layer.visible,
                        ),
                      );
                },
              ),
              _IconAction(
                icon: Icons.delete_outline,
                tooltip: protected ? 'Protected base photo' : 'Delete',
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
              if (isSelected)
                _OpacitySlider(layer: layer),
            ],
          ),
        ),
      ),
    );
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
            ? Theme.of(context).colorScheme.primary
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

/// Compact per-layer opacity slider rendered under the selected
/// layer's row. Drag previews use [DocumentController.liveReplace] so
/// the canvas updates at 60fps without bumping the commit version
/// (no autosave thrash, no undo entries). The final value is
/// committed via [SetLayerOpacityCommand] on `onChangeEnd` so undo /
/// redo and the dirty-state badge see exactly one entry per gesture.
class _OpacitySlider extends ConsumerStatefulWidget {
  const _OpacitySlider({required this.layer});
  final EditorLayer layer;

  @override
  ConsumerState<_OpacitySlider> createState() => _OpacitySliderState();
}

class _OpacitySliderState extends ConsumerState<_OpacitySlider> {
  // Local copy of the slider's in-flight value. Null when no drag is
  // in progress so the displayed value tracks the layer's current
  // opacity (which may have changed via undo / redo / a different
  // surface).
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = (_dragValue ?? widget.layer.opacity).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(left: 36, right: 8, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.opacity, size: 16, color: theme.hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14,
                ),
              ),
              child: Slider(
                value: value,
                min: 0,
                max: 1,
                onChanged: (v) {
                  setState(() => _dragValue = v);
                  // Live preview: replace the layer in-place
                  // without going through history.
                  final doc = ref.read(documentControllerProvider);
                  final layer = doc.layerById(widget.layer.id);
                  if (layer == null) return;
                  ref
                      .read(documentControllerProvider.notifier)
                      .liveReplace(doc.replaceLayer(layer.withOpacity(v)));
                },
                onChangeEnd: (v) {
                  setState(() => _dragValue = null);
                  ref.read(documentControllerProvider.notifier).execute(
                        SetLayerOpacityCommand(
                          layerId: widget.layer.id,
                          opacity: v,
                        ),
                      );
                },
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
