import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/shape_commands.dart';
import '../../engine/core/canvas_sizing.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/widgets/inline_color_body.dart';
import '../../presentation/widgets/panel_option_tile.dart';
import '../../application/recent_colors_controller.dart';
import '../../presentation/widgets/section_label.dart';
import 'shape_panel_shell.dart';

/// Expanded panel body for the Shape sub-tool's "Border" tab.
///
/// Mirrors the Image border panel grammar: 4 thickness chips
/// (None / Thin / Medium / Bold) + a colour swatch row, both
/// committed via [SetShapeStrokeCommand]. Picking a colour while
/// the stroke is currently `None` auto-promotes width to medium so
/// the user sees their pick land instead of nothing happening.
///
/// **Canvas-aware thickness** (2026-05). Each preset is a fixed
/// *fraction of the canvas's effective dimension* (see
/// [CanvasSizing.proportionalStroke]) clamped to a sane absolute
/// min/max so the same formula works on a 100×100 sticker, a
/// 1080×1080 social card, or a 12000×12000 poster — no per-size
/// special cases, no reference-canvas tuning. Stored strokeWidth
/// remains in canvas pixels, so the renderer is unchanged and
/// existing documents render byte-for-byte the same.
class ShapeBorderBody extends ConsumerStatefulWidget {
  const ShapeBorderBody({super.key, required this.layer});

  final ShapeLayer layer;

  // Stroke width = clamp(effectiveDim × fraction, minPx, maxPx).
  //
  // Fractions are tuned so 1080-square (the most common design
  // canvas) lands at ≈1 / ≈4 / ≈11 px — the same values that
  // already felt right there. The min/max bookends keep tiny
  // canvases legible and stop huge canvases from producing
  // bezel-thick borders.
  static const double _thinFraction = 0.001; // ≈ 0.1 % of canvas
  static const double _mediumFraction = 0.004; // ≈ 0.4 % of canvas
  static const double _boldFraction = 0.010; // ≈ 1.0 % of canvas

  static const double _thinMin = 1, _thinMax = 12;
  static const double _mediumMin = 3, _mediumMax = 48;
  static const double _boldMin = 8, _boldMax = 120;

  @override
  ConsumerState<ShapeBorderBody> createState() => _ShapeBorderBodyState();
}

class _ShapeBorderBodyState extends ConsumerState<ShapeBorderBody> {
  void _commit({
    Color? c,
    bool clearColor = false,
    double? w,
    bool live = false,
  }) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          SetShapeStrokeCommand(
            layerId: widget.layer.id,
            color: c,
            clearColor: clearColor,
            width: w,
            live: live,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final width = layer.strokeWidth;
    final color = layer.strokeColor ?? const Color(0xFF000000);
    final hasBorder = width > 0 && layer.strokeColor != null;
    // Canvas-aware preset widths via the central helper. Same
    // formula on every canvas — no reference size, no per-size
    // case. The min/max clamps keep tiny canvases legible and
    // huge canvases from producing absurd borders.
    final doc = ref.watch(documentControllerProvider);
    final thin = CanvasSizing.proportionalStroke(
      doc,
      fraction: ShapeBorderBody._thinFraction,
      minPx: ShapeBorderBody._thinMin,
      maxPx: ShapeBorderBody._thinMax,
    );
    final medium = CanvasSizing.proportionalStroke(
      doc,
      fraction: ShapeBorderBody._mediumFraction,
      minPx: ShapeBorderBody._mediumMin,
      maxPx: ShapeBorderBody._mediumMax,
    );
    final bold = CanvasSizing.proportionalStroke(
      doc,
      fraction: ShapeBorderBody._boldFraction,
      minPx: ShapeBorderBody._boldMin,
      maxPx: ShapeBorderBody._boldMax,
    );
    // Stroked kinds (line/arrow) reuse strokeWidth for line
    // thickness; their visible colour comes from `fillColor` so the
    // “Border colour” row would be visually unhooked. Keep the
    // panel limited to thickness for these kinds.
    final isStroked = isStrokedShapeKind(layer.kind);
    // For stroked kinds the “None” thickness chip is meaningless
    // (the line IS the shape) — drop it from the chip set.
    final thicknessLabel = isStroked
        ? context.l10n.strokeWidthLabel
        : context.l10n.thicknessLabel;

    return ShapePanelShell(
      title: context.l10n.borderTool,
      icon: Icons.border_outer_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(thicknessLabel),
          _ThicknessChips(
            width: width,
            hasColor: layer.strokeColor != null || isStroked,
            allowNone: !isStroked,
            onPick: (w) {
              EditorHaptics.toggle();
              if (w == 0) {
                // None — drop the colour too so re-tapping a
                // thickness later starts from a clean default.
                _commit(clearColor: true, w: 0);
              } else {
                // Promote a default colour if the user is
                // turning the border on for the first time.
                // For stroked kinds we don't need a stroke colour
                // (rendering reuses fillColor); just set width.
                _commit(
                  c: isStroked
                      ? null
                      : (layer.strokeColor ?? const Color(0xFF000000)),
                  w: w,
                );
              }
            },
            thin: thin,
            medium: medium,
            bold: bold,
          ),
          if (!isStroked) ...[
            const SizedBox(height: 12),
            SectionLabel(context.l10n.colorLabel),
            // Approved compact color UI — fed by the app-wide
            // [recentColorsControllerProvider] so customs picked
            // in any colour panel are surfaced here too.
            InlineColorBody(
              current: color,
              recents: ref.watch(recentColorsControllerProvider),
              palette: InlineColorBody.defaultPalette,
              compactRecents: true,
              onPick: (picked) {
                EditorHaptics.toggle();
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
          ],
        ],
      ),
    );
  }
}

class _ThicknessChips extends StatelessWidget {
  const _ThicknessChips({
    required this.width,
    required this.hasColor,
    required this.allowNone,
    required this.onPick,
    required this.thin,
    required this.medium,
    required this.bold,
  });

  final double width;
  final bool hasColor;
  final bool allowNone;
  final ValueChanged<double> onPick;
  final double thin;
  final double medium;
  final double bold;

  @override
  Widget build(BuildContext context) {
    final entries = <(_ChipKey, double, String, IconData, double)>[
      if (allowNone)
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
    // Tolerance scales with the canvas-aware preset values so
    // "Medium" on a 4K canvas (e.g. ~20px stored) still matches
    // its chip cleanly. Floor at 0.25 keeps the small-canvas
    // 1/4/10 distinction crisp.
    final tol = math.max(0.25, thin * 0.25);
    _ChipKey activeKey;
    if (allowNone && (width <= 0 || !hasColor)) {
      activeKey = _ChipKey.none;
    } else if ((width - thin).abs() < tol) {
      activeKey = _ChipKey.thin;
    } else if ((width - medium).abs() < tol) {
      activeKey = _ChipKey.medium;
    } else if ((width - bold).abs() < tol) {
      activeKey = _ChipKey.bold;
    } else if (!allowNone && width <= 0) {
      // Stroked kinds with width=0 fall back to the rendering
      // default (~6) which is closest to medium.
      activeKey = _ChipKey.medium;
    } else {
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
