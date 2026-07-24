import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/alignment_controller.dart';
import '../../application/context_toolbar_controller.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/interaction/alignment_engine.dart';
import 'editor_tool_panel_shell.dart';
import 'layer_opacity_control.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import 'section_label.dart';

class ContextToolPanelBody extends ConsumerWidget {
  const ContextToolPanelBody({
    super.key,
    required this.panel,
    required this.layers,
  });

  final ContextToolPanel panel;
  final List<EditorLayer> layers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMulti = layers.length > 1;
    return switch (panel) {
      ContextToolPanel.align => EditorToolPanelShell(
        title: isMulti
            ? context.l10n.alignSelectedLayersTitle
            : context.l10n.alignToCanvasTitle,
        icon: Icons.align_horizontal_left_rounded,
        onClose: () =>
            ref.read(contextToolbarControllerProvider.notifier).closePanel(),
        bodyPadding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 18),
        maxHeightFraction: 0.30,
        maxHeightDp: 280,
        child: _AlignPanel(selectedCount: layers.length),
      ),
      ContextToolPanel.opacity => EditorToolPanelShell(
        title: context.l10n.opacityLabel,
        icon: Icons.opacity,
        onClose: () =>
            ref.read(contextToolbarControllerProvider.notifier).closePanel(),
        bodyPadding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 18),
        maxHeightFraction: 0.20,
        maxHeightDp: 180,
        child: isMulti
            ? MultiLayerOpacityControl(layers: layers, showLabel: false)
            : LayerOpacityControl(layer: layers.single, showLabel: false),
      ),
    };
  }
}

class _AlignPanel extends ConsumerWidget {
  const _AlignPanel({required this.selectedCount});

  final int selectedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMulti = selectedCount > 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AlignSection(
          label: context.l10n.alignHorizontalGroup,
          actions: [
            _AlignTileData(
              icon: Icons.align_horizontal_left_rounded,
              label: context.l10n.alignLeftAction,
              tooltip: context.l10n.alignLeftAction,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.left),
            ),
            _AlignTileData(
              icon: Icons.align_horizontal_center_rounded,
              label: context.l10n.alignCenterAction,
              tooltip: context.l10n.alignCenterAction,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.centerX),
            ),
            _AlignTileData(
              icon: Icons.align_horizontal_right_rounded,
              label: context.l10n.alignRightAction,
              tooltip: context.l10n.alignRightAction,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.right),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _AlignSection(
          label: context.l10n.alignVerticalGroup,
          actions: [
            _AlignTileData(
              icon: Icons.align_vertical_top_rounded,
              label: context.l10n.alignTopAction,
              tooltip: context.l10n.alignTopAction,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.top),
            ),
            _AlignTileData(
              icon: Icons.align_vertical_center_rounded,
              label: context.l10n.alignMiddleAction,
              tooltip: context.l10n.alignMiddleAction,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.centerY),
            ),
            _AlignTileData(
              icon: Icons.align_vertical_bottom_rounded,
              label: context.l10n.alignBottomAction,
              tooltip: context.l10n.alignBottomAction,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.bottom),
            ),
          ],
        ),
        if (selectedCount >= 3) ...[
          const SizedBox(height: 10),
          _AlignSection(
            label: context.l10n.distributeGroup,
            actions: [
              _AlignTileData(
                icon: Icons.space_bar_rounded,
                label: context.l10n.horizontalOption,
                tooltip: context.l10n.distributeHorizontallyAction,
                onTap: () => ref
                    .read(alignmentControllerProvider)
                    .distribute(DistributeAxis.horizontal),
              ),
              _AlignTileData(
                icon: Icons.unfold_more_rounded,
                label: context.l10n.verticalOption,
                tooltip: context.l10n.distributeVerticallyAction,
                onTap: () => ref
                    .read(alignmentControllerProvider)
                    .distribute(DistributeAxis.vertical),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _runAlign(WidgetRef ref, bool isMulti, AlignAxis axis) {
    final controller = ref.read(alignmentControllerProvider);
    if (isMulti) {
      controller.align(axis);
    } else {
      controller.alignToCanvas(axis);
    }
  }
}

class _AlignSection extends StatelessWidget {
  const _AlignSection({required this.label, required this.actions});

  final String label;
  final List<_AlignTileData> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(label),
        Row(
          children: [
            for (final action in actions) ...[
              Expanded(
                child: _AlignTile(
                  icon: action.icon,
                  label: action.label,
                  tooltip: action.tooltip,
                  onTap: action.onTap,
                ),
              ),
              if (action != actions.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _AlignTileData {
  const _AlignTileData({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
}

class _AlignTile extends StatelessWidget {
  const _AlignTile({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PresetChip.option(
        selected: false,
        icon: icon,
        label: label,
        onTap: onTap,
      ),
    );
  }
}
