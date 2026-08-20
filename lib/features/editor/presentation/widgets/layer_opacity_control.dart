import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../engine/commands/layer_state_commands.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/core/editor_layer.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../app/theme/app_icons.dart';

/// Shared layer-opacity slider for every selected-layer action surface.
///
/// Drag previews are staged in [liveOverlayProvider] so canvas feedback is
/// immediate without creating undo entries. The final drag value commits via
/// [SetLayerOpacityCommand], matching the layers drawer behaviour.
///
/// Lock rule ([EditorLayer.locked]): opacity is part of the layer's
/// frozen content, so both controls gate on [canEdit] — the single
/// slider renders disabled for a locked layer, and the multi variant
/// drops locked members from its average, its preview and its commit
/// (same silent-drop grammar as batch align). Gating INSIDE the
/// shared control makes every mounting point — the opacity context
/// panel and the layers drawer row — obey at once (ux-audit P3-1:
/// this slider used to stay live for layers the canvas refused to
/// touch).
class LayerOpacityControl extends ConsumerStatefulWidget {
  const LayerOpacityControl({
    super.key,
    required this.layer,
    this.padding = const EdgeInsetsDirectional.only(
      start: 36,
      end: 8,
      bottom: 4,
    ),
    this.showLabel = false,
  });

  /// THE per-layer rule for whether opacity may change — consumed by
  /// both slider variants here and by the overflow sheet's Opacity
  /// row, so the entry point and the write cannot drift.
  ///
  /// The protected base photo is the rule's one carve-out: it imports
  /// `locked` purely as structural pinning against canvas gestures,
  /// and fading it toward the canvas background is the Image strip's
  /// deliberate, chrome-named offer (tb15, pinned by
  /// context_panel_target_test) — refusing it here would resurrect
  /// that strip's شفافیت dead-end.
  static bool canEdit(EditorDocument doc, EditorLayer layer) =>
      !layer.locked || doc.isProtectedBasePhoto(layer.id);

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
    this.padding = const EdgeInsetsDirectional.only(
      start: 36,
      end: 8,
      bottom: 4,
    ),
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
    // Whole-document watch: the old `.select` produced a fresh List
    // every evaluation, so it never suppressed a rebuild anyway, and
    // the eligibility gate below needs the document for the
    // base-photo clause of [LayerOpacityControl.canEdit].
    final doc = ref.watch(documentControllerProvider);
    final layers = ids.map(doc.layerById).nonNulls.toList(growable: false);
    // Locked members are excluded from the average, the live preview
    // AND the commit — a mixed selection edits only the layers whose
    // content can change, and the readout must describe exactly the
    // set the drag will write (never a silently-skipped member's
    // value). All-ineligible → the slider renders disabled, showing
    // the group's actual average.
    final eligible = [
      for (final layer in layers)
        if (LayerOpacityControl.canEdit(doc, layer)) layer,
    ];
    final value =
        (_dragValue ?? _averageOpacity(eligible.isEmpty ? layers : eligible))
            .clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final f = EditorValueFormat.of(context);
    final percent = f.percent((value * 100).round());

    final opacityLabel = context.l10n.opacityLabel;
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      // MergeSemantics: a plain Semantics wrapper sits ABOVE the
      // Slider's own node, so the SeekBar — the node TalkBack focuses
      // and the one that owns increase/decrease — kept announcing a
      // bare «۱۰۰٪». Merging puts the name on that node. The ancestor
      // label that used to wrap the whole row is gone; with both in
      // place the parameter was spoken twice.
      child: MergeSemantics(
        child: Semantics(
          label: opacityLabel,
          child: Slider(
            value: value,
            min: 0,
            max: 1,
            semanticFormatterCallback: (v) => f.percent((v * 100).round()),
            // Both callbacks re-read the document and re-apply
            // [LayerOpacityControl.canEdit] at write time, so a lock
            // flipped mid-gesture (undo, another surface) is honoured
            // by the very next preview frame and by the commit.
            onChanged: eligible.isEmpty
                ? null
                : (v) {
                    setState(() => _dragValue = v);
                    final doc = ref.read(documentControllerProvider);
                    for (final id in ids) {
                      final currentLayer = doc.layerById(id);
                      if (currentLayer == null ||
                          !LayerOpacityControl.canEdit(doc, currentLayer)) {
                        continue;
                      }
                      ref
                          .read(liveOverlayProvider.notifier)
                          .replaceLayer(currentLayer.withOpacity(v));
                    }
                  },
            onChangeEnd: eligible.isEmpty
                ? null
                : (v) {
                    setState(() => _dragValue = null);
                    ref.read(liveOverlayProvider.notifier).clear();
                    final doc = ref.read(documentControllerProvider);
                    final commands = <SetLayerOpacityCommand>[
                      for (final id in ids)
                        if (doc.layerById(id) case final layer?
                            when LayerOpacityControl.canEdit(doc, layer))
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
        ),
      ),
    );

    return Padding(
      padding: widget.padding,
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
                    // Excluded: the slider node already carries this
                    // number as its `value`, so leaving it in the tree
                    // adds a focus stop that announces a bare figure.
                    ExcludeSemantics(
                      child: Text(percent, style: theme.textTheme.bodySmall),
                    ),
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
                  child: ExcludeSemantics(
                    child: Text(
                      percent,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
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
    // Live-document eligibility ([LayerOpacityControl.canEdit]) so a
    // lock flipped while the slider is on screen (undo, the drawer's
    // lock toggle) disables it in place. A layer missing from the
    // document keeps the slider enabled — that transient state
    // (mid-delete teardown) predates this gate and commits nothing.
    final canEdit = ref.watch(
      documentControllerProvider.select((doc) {
        final live = doc.layerById(widget.layer.id);
        return live == null || LayerOpacityControl.canEdit(doc, live);
      }),
    );
    final value = (_dragValue ?? layer.opacity).clamp(0.0, 1.0);
    final f = EditorValueFormat.of(context);
    final percent = f.percent((value * 100).round());

    final opacityLabel = context.l10n.opacityLabel;
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      // MergeSemantics: a plain Semantics wrapper sits ABOVE the
      // Slider's own node, so the SeekBar — the node TalkBack focuses
      // and the one that owns increase/decrease — kept announcing a
      // bare «۱۰۰٪». Merging puts the name on that node. The ancestor
      // label that used to wrap the whole row is gone; with both in
      // place the parameter was spoken twice.
      child: MergeSemantics(
        child: Semantics(
          label: opacityLabel,
          child: Slider(
            value: value,
            min: 0,
            max: 1,
            semanticFormatterCallback: (v) => f.percent((v * 100).round()),
            onChanged: !canEdit
                ? null
                : (v) {
                    setState(() => _dragValue = v);
                    final doc = ref.read(documentControllerProvider);
                    final currentLayer = doc.layerById(widget.layer.id);
                    if (currentLayer == null) return;
                    ref
                        .read(liveOverlayProvider.notifier)
                        .replaceLayer(currentLayer.withOpacity(v));
                  },
            onChangeEnd: !canEdit
                ? null
                : (v) {
                    setState(() => _dragValue = null);
                    ref.read(liveOverlayProvider.notifier).clear();
                    ref
                        .read(documentControllerProvider.notifier)
                        .execute(
                          SetLayerOpacityCommand(
                            layerId: widget.layer.id,
                            opacity: v,
                          ),
                        );
                  },
          ),
        ),
      ),
    );

    return Padding(
      padding: widget.padding,
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
                    // Excluded: the slider node already carries this
                    // number as its `value`, so leaving it in the tree
                    // adds a focus stop that announces a bare figure.
                    ExcludeSemantics(
                      child: Text(percent, style: theme.textTheme.bodySmall),
                    ),
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
                  child: ExcludeSemantics(
                    child: Text(
                      percent,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
