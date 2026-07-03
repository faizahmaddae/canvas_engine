import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/core/canvas_sizing.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../presentation/widgets/inline_color_body.dart';
import '../../presentation/widgets/panel_option_tile.dart';
import '../../application/recent_colors_controller.dart';
import '../../presentation/widgets/section_label.dart';
import '../../ui/editor_slider_row.dart';
import '../../ui/precision_disclosure.dart';
import 'image_panel_shell.dart';

/// Expanded panel body for the Image sub-tool's "Border" tab.
///
/// Two sections:
///   * **Color** \u2014 [InlineColorBody] swatch row, picks committed
///     immediately as a [SetImageBorderCommand]. When the layer
///     currently has no border (`width == 0`), tapping a colour
///     auto-promotes width to the medium thickness so the user
///     sees their pick land instead of nothing happening.
///   * **Thickness** \u2014 4 chips (None / Thin / Medium / Bold) +
///     a precise slider. Both write through
///     [SetImageBorderCommand] so each commit is undoable; the
///     slider coalesces into one undo entry per drag via the
///     standard "live preview → commit on end" pattern (here
///     simplified to a single command per release for Phase 1).
///
/// **Canvas-aware thickness** (2026-05). Each preset is a fixed
/// *fraction of the canvas's effective dimension* (see
/// [CanvasSizing.proportionalStroke]) clamped to a sane absolute
/// min/max so the same formula works on a 100×100 sticker, a
/// 1080×1080 social card, or a 12000×12000 poster — no per-size
/// special cases, no reference-canvas tuning. Mirrors the Shape
/// Border preset grammar so both image-borders and shape-borders
/// scale identically. Stored borderWidth remains in canvas px so
/// existing documents render byte-for-byte the same.
class ImageBorderBody extends ConsumerStatefulWidget {
  const ImageBorderBody({super.key, required this.layer});

  final ImageLayer layer;

  // Stroke width = clamp(effectiveDim × fraction, minPx, maxPx).
  // Fractions/clamps match shape_border_body.dart so both
  // surfaces feel like one tool family.
  static const double _thinFraction = 0.001; // ≈ 0.1 % of canvas
  static const double _mediumFraction = 0.004; // ≈ 0.4 % of canvas
  static const double _boldFraction = 0.010; // ≈ 1.0 % of canvas

  static const double _thinMin = 1, _thinMax = 12;
  static const double _mediumMin = 3, _mediumMax = 48;
  static const double _boldMin = 8, _boldMax = 120;

  @override
  ConsumerState<ImageBorderBody> createState() => _ImageBorderBodyState();
}

class _ImageBorderBodyState extends ConsumerState<ImageBorderBody> {
  void _commit({Color? c, double? w, bool live = false}) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          SetImageBorderCommand(
            layerId: widget.layer.id,
            color: c,
            width: w,
            live: live,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final width = layer.borderWidth;
    final color = layer.borderColor;
    final hasBorder = width > 0;
    // Canvas-aware preset widths via the central helper. Same
    // formula on every canvas — no reference size, no per-size
    // case. Mirrors shape_border_body.dart exactly.
    final doc = ref.watch(documentControllerProvider);
    final thin = CanvasSizing.proportionalStroke(
      doc,
      fraction: ImageBorderBody._thinFraction,
      minPx: ImageBorderBody._thinMin,
      maxPx: ImageBorderBody._thinMax,
    );
    final medium = CanvasSizing.proportionalStroke(
      doc,
      fraction: ImageBorderBody._mediumFraction,
      minPx: ImageBorderBody._mediumMin,
      maxPx: ImageBorderBody._mediumMax,
    );
    final bold = CanvasSizing.proportionalStroke(
      doc,
      fraction: ImageBorderBody._boldFraction,
      minPx: ImageBorderBody._boldMin,
      maxPx: ImageBorderBody._boldMax,
    );
    // Slider headroom: let users dial up to 2× Bold so the
    // precision affordance always reaches "chunkier than the
    // last preset" without ever being smaller than the legacy
    // 20-px ceiling.
    final sliderMax = math.max(20.0, bold * 2);

    return ImagePanelShell(
      title: context.l10n.borderTool,
      icon: Icons.border_outer_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thickness leads — picking a width is the primary
          // action; colour is a refinement once the border is on.
          SectionLabel(context.l10n.thicknessLabel),
          _ThicknessChips(
            width: width,
            onPick: (w) {
              EditorHaptics.toggle();
              _commit(w: w);
            },
            thin: thin,
            medium: medium,
            bold: bold,
          ),
          const SizedBox(height: 12),
          SectionLabel(context.l10n.colorLabel),
          InlineColorBody(
            current: color,
            recents: ref.watch(recentColorsControllerProvider),
            palette: InlineColorBody.defaultPalette,
            compactRecents: true,
            onPick: (picked) {
              EditorHaptics.toggle();
              // Auto-promote width so a colour pick on a no-border
              // image is visible instead of silently committing.
              _commit(c: picked, w: hasBorder ? null : medium);
            },
            onCustom: () async {
              final original = color;
              final picked = await showColorPickerSheet(
                context,
                initial: original,
                recents: ref.read(recentColorsControllerProvider),
                onLiveChange: (c) =>
                    _commit(c: c, w: hasBorder ? null : medium, live: true),
                title: context.l10n.borderColorTitle,
              );
              if (picked == null) {
                _commit(c: original);
                return;
              }
              ref
                  .read(recentColorsControllerProvider.notifier)
                  .remember(picked);
            },
          ),
          const SizedBox(height: 6),
          PrecisionDisclosure(
            icon: Icons.tune_rounded,
            titleClosed: context.l10n.adjustPrecisely,
            subtitle: context.l10n.widthLabel,
            chevronColorClosed: Theme.of(context).colorScheme.primary,
            chevronColorOpen: Theme.of(context).colorScheme.primary,
            children: [
              const SizedBox(height: 4),
              EditorSliderRow(
                label: context.l10n.widthLabel,
                readoutWidth: 40,
                value: width,
                max: sliderMax,
                format: (v) => '${v.round()}',
                onChanged: (w) => _commit(w: w, live: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 4-chip thickness picker. Mirrors the Text-mode style-chip grammar
/// (soft primary tint when selected, neutral surface otherwise).
class _ThicknessChips extends StatelessWidget {
  const _ThicknessChips({
    required this.width,
    required this.onPick,
    required this.thin,
    required this.medium,
    required this.bold,
  });

  final double width;
  final ValueChanged<double> onPick;
  final double thin;
  final double medium;
  final double bold;

  @override
  Widget build(BuildContext context) {
    final entries = <(_ChipKey, double, String, IconData, double)>[
      (_ChipKey.none, 0, context.l10n.noneOption, Icons.block_rounded, 18),
      (
        _ChipKey.thin,
        thin,
        context.l10n.thinOption,
        Icons.horizontal_rule_rounded,
        16,
      ),
      (
        _ChipKey.medium,
        medium,
        context.l10n.mediumOption,
        Icons.horizontal_rule_rounded,
        22,
      ),
      (
        _ChipKey.bold,
        bold,
        context.l10n.thickOption,
        Icons.horizontal_rule_rounded,
        30,
      ),
    ];
    _ChipKey activeKey;
    // Scale tolerance with the preset itself so picks are still
    // recognised on huge canvases where Bold can be tens of px
    // and a fixed 0.25 px window would never match.
    final tol = math.max(0.25, thin * 0.25);
    if (width <= 0) {
      activeKey = _ChipKey.none;
    } else if ((width - thin).abs() < tol) {
      activeKey = _ChipKey.thin;
    } else if ((width - medium).abs() < tol) {
      activeKey = _ChipKey.medium;
    } else if ((width - bold).abs() < tol) {
      activeKey = _ChipKey.bold;
    } else {
      // Custom slider value \u2014 don't highlight any preset chip.
      activeKey = _ChipKey.custom;
    }

    return Row(
      children: [
        for (final entry in entries) ...[
          Expanded(
            child: _Chip(
              icon: entry.$4,
              iconSize: entry.$5,
              label: entry.$3,
              selected: entry.$1 == activeKey,
              onTap: () => onPick(entry.$2),
            ),
          ),
          if (entry != entries.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

enum _ChipKey { none, thin, medium, bold, custom }

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PanelOptionTile(
      icon: icon,
      iconSize: iconSize,
      label: label,
      selected: selected,
      onTap: onTap,
    );
  }
}

