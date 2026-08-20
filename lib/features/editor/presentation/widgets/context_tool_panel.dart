import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/alignment_controller.dart';
import '../../application/context_toolbar_controller.dart';
import '../../application/document_controller.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/interaction/alignment_engine.dart';
import 'editor_tool_panel_shell.dart';
import 'layer_opacity_control.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import 'section_label.dart';
import '../../../../app/theme/app_icons.dart';

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
        icon: AppIcons.alignLeft,
        onClose: () =>
            ref.read(contextToolbarControllerProvider.notifier).closePanel(),
        bodyPadding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 18),
        maxHeightFraction: 0.30,
        maxHeightDp: 280,
        child: _AlignPanel(layers: layers),
      ),
      // Lock gating lives INSIDE the two controls (the same live-
      // document eligibility grammar as the align tiles below): the
      // single slider renders disabled for a locked layer, the multi
      // variant drops locked members from its average and its write —
      // see LayerOpacityControl.canEdit. So this panel never sits
      // live-looking over a layer the write path would refuse, from
      // ANY entry point (the mode strips' شفافیت tiles included).
      ContextToolPanel.opacity => EditorToolPanelShell(
        title: context.l10n.opacityLabel,
        icon: AppIcons.opacity,
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
  const _AlignPanel({required this.layers});

  final List<EditorLayer> layers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMulti = layers.length > 1;
    // Tiles the controller would refuse render disabled, never live
    // and silently inert (audit P2-7, contract §10.3) — from THE
    // eligibility rule the controller itself commits through. Section
    // presence stays keyed on the selection size (distribute is
    // inadmissible below three layers); enablement is keyed on how
    // many of them can actually move. Layers are re-resolved from the
    // watched document so a lock flip (e.g. an undo while the panel
    // is open) updates the gates live even if this panel's prop list
    // is a stale parent snapshot.
    final doc = ref.watch(documentControllerProvider);
    final eligibility = AlignmentEligibility.of(
      doc,
      layers.map((l) => doc.layerById(l.id)).whereType<EditorLayer>(),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AlignSection(
          label: context.l10n.alignHorizontalGroup,
          actions: [
            _AlignTileData(
              icon: AppIcons.alignLeft,
              label: context.l10n.alignLeftAction,
              tooltip: context.l10n.alignLeftAction,
              enabled: eligibility.canAlign,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.left),
            ),
            _AlignTileData(
              icon: AppIcons.alignHorizontalCenter,
              label: context.l10n.alignCenterAction,
              tooltip: context.l10n.alignCenterAction,
              enabled: eligibility.canAlign,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.centerX),
            ),
            _AlignTileData(
              icon: AppIcons.alignRight,
              label: context.l10n.alignRightAction,
              tooltip: context.l10n.alignRightAction,
              enabled: eligibility.canAlign,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.right),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _AlignSection(
          label: context.l10n.alignVerticalGroup,
          actions: [
            _AlignTileData(
              icon: AppIcons.alignTop,
              label: context.l10n.alignTopAction,
              tooltip: context.l10n.alignTopAction,
              enabled: eligibility.canAlign,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.top),
            ),
            _AlignTileData(
              icon: AppIcons.alignVerticalCenter,
              label: context.l10n.alignMiddleAction,
              tooltip: context.l10n.alignMiddleAction,
              enabled: eligibility.canAlign,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.centerY),
            ),
            _AlignTileData(
              icon: AppIcons.alignBottom,
              label: context.l10n.alignBottomAction,
              tooltip: context.l10n.alignBottomAction,
              enabled: eligibility.canAlign,
              onTap: () => _runAlign(ref, isMulti, AlignAxis.bottom),
            ),
          ],
        ),
        if (layers.length >= 3) ...[
          const SizedBox(height: 10),
          _AlignSection(
            label: context.l10n.distributeGroup,
            actions: [
              _AlignTileData(
                icon: AppIcons.distributeHorizontal,
                label: context.l10n.horizontalOption,
                tooltip: context.l10n.distributeHorizontallyAction,
                enabled: eligibility.canDistribute,
                onTap: () => ref
                    .read(alignmentControllerProvider)
                    .distribute(DistributeAxis.horizontal),
              ),
              _AlignTileData(
                icon: AppIcons.distributeVertical,
                label: context.l10n.verticalOption,
                tooltip: context.l10n.distributeVerticallyAction,
                enabled: eligibility.canDistribute,
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
                  enabled: action.enabled,
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
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
}

class _AlignTile extends StatelessWidget {
  const _AlignTile({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PresetChip.option(
        selected: false,
        enabled: enabled,
        icon: icon,
        label: label,
        onTap: onTap,
      ),
    );
  }
}
