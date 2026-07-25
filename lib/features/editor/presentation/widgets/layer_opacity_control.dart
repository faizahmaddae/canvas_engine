import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../engine/commands/layer_state_commands.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/editor_layer.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../app/theme/app_icons.dart';

/// Shared layer-opacity slider for every selected-layer action surface.
///
/// Drag previews are staged in [liveOverlayProvider] so canvas feedback is
/// immediate without creating undo entries. The final drag value commits via
/// [SetLayerOpacityCommand], matching the layers drawer behaviour.
class LayerOpacityControl extends ConsumerStatefulWidget {
  const LayerOpacityControl({
    super.key,
    required this.layer,
    this.padding = const EdgeInsets.only(left: 36, right: 8, bottom: 4),
    this.showLabel = false,
  });

  final EditorLayer layer;
  final EdgeInsetsGeometry padding;
  final bool showLabel;

  @override
  ConsumerState<LayerOpacityControl> createState() =>
      _LayerOpacityControlState();
}

class MultiLayerOpacityControl extends ConsumerStatefulWidget {
  const MultiLayerOpacityControl({
    super.key,
    required this.layers,
    this.padding = const EdgeInsets.only(left: 36, right: 8, bottom: 4),
    this.showLabel = false,
  });

  final List<EditorLayer> layers;
  final EdgeInsetsGeometry padding;
  final bool showLabel;

  @override
  ConsumerState<MultiLayerOpacityControl> createState() =>
      _MultiLayerOpacityControlState();
}

class _MultiLayerOpacityControlState
    extends ConsumerState<MultiLayerOpacityControl> {
  double? _dragValue;

  @override
  void dispose() {
    if (_dragValue != null) {
      ref.read(liveOverlayProvider.notifier).clear();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.layers.map((layer) => layer.id).toList(growable: false);
    final layers = ref.watch(
      documentControllerProvider.select(
        (doc) => ids.map(doc.layerById).nonNulls.toList(growable: false),
      ),
    );
    final value = (_dragValue ?? _averageOpacity(layers)).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final f = EditorValueFormat.of(context);
    final percent = f.percent((value * 100).round());

    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
        value: value,
        min: 0,
        max: 1,
        semanticFormatterCallback: (v) => f.percent((v * 100).round()),
        onChanged: layers.isEmpty
            ? null
            : (v) {
                setState(() => _dragValue = v);
                final doc = ref.read(documentControllerProvider);
                for (final id in ids) {
                  final currentLayer = doc.layerById(id);
                  if (currentLayer == null) continue;
                  ref
                      .read(liveOverlayProvider.notifier)
                      .replaceLayer(currentLayer.withOpacity(v));
                }
              },
        onChangeEnd: layers.isEmpty
            ? null
            : (v) {
                setState(() => _dragValue = null);
                ref.read(liveOverlayProvider.notifier).clear();
                final doc = ref.read(documentControllerProvider);
                final commands = <SetLayerOpacityCommand>[
                  for (final id in ids)
                    if (doc.layerById(id) != null)
                      SetLayerOpacityCommand(layerId: id, opacity: v),
                ];
                if (commands.isEmpty) return;
                ref
                    .read(documentControllerProvider.notifier)
                    .execute(
                      commands.length == 1
                          ? commands.single
                          : CompositeCommand(
                              commands,
                              labelOverride: 'Set layer opacity',
                            ),
                    );
              },
      ),
    );

    return Padding(
      padding: widget.padding,
      child: Semantics(
        label: context.l10n.opacityLabel,
        child: widget.showLabel
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(AppIcons.opacity, size: 20, color: theme.hintColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.opacityLabel,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(percent, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  slider,
                ],
              )
            : Row(
                children: [
                  Icon(AppIcons.opacity, size: 16, color: theme.hintColor),
                  const SizedBox(width: 8),
                  Expanded(child: slider),
                  SizedBox(
                    width: 36,
                    child: Text(
                      percent,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  double _averageOpacity(List<EditorLayer> layers) {
    if (layers.isEmpty) return 1;
    final total = layers.fold<double>(0, (sum, layer) => sum + layer.opacity);
    return total / layers.length;
  }
}

class _LayerOpacityControlState extends ConsumerState<LayerOpacityControl> {
  double? _dragValue;

  @override
  void dispose() {
    if (_dragValue != null) {
      ref.read(liveOverlayProvider.notifier).clear();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layer = ref.watch(
      documentControllerProvider.select(
        (doc) => doc.layerById(widget.layer.id) ?? widget.layer,
      ),
    );
    final value = (_dragValue ?? layer.opacity).clamp(0.0, 1.0);
    final f = EditorValueFormat.of(context);
    final percent = f.percent((value * 100).round());

    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
        value: value,
        min: 0,
        max: 1,
        semanticFormatterCallback: (v) => f.percent((v * 100).round()),
        onChanged: (v) {
          setState(() => _dragValue = v);
          final doc = ref.read(documentControllerProvider);
          final currentLayer = doc.layerById(widget.layer.id);
          if (currentLayer == null) return;
          ref
              .read(liveOverlayProvider.notifier)
              .replaceLayer(currentLayer.withOpacity(v));
        },
        onChangeEnd: (v) {
          setState(() => _dragValue = null);
          ref.read(liveOverlayProvider.notifier).clear();
          ref
              .read(documentControllerProvider.notifier)
              .execute(
                SetLayerOpacityCommand(layerId: widget.layer.id, opacity: v),
              );
        },
      ),
    );

    return Padding(
      padding: widget.padding,
      child: Semantics(
        label: context.l10n.opacityLabel,
        child: widget.showLabel
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(AppIcons.opacity, size: 20, color: theme.hintColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.opacityLabel,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(percent, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  slider,
                ],
              )
            : Row(
                children: [
                  Icon(AppIcons.opacity, size: 16, color: theme.hintColor),
                  const SizedBox(width: 8),
                  Expanded(child: slider),
                  SizedBox(
                    width: 36,
                    child: Text(
                      percent,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
