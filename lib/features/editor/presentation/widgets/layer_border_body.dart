import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/core/canvas_sizing.dart';
import '../../engine/core/editor_layer.dart';
import '../../ui/editor_slider_row.dart';
import '../../ui/precision_disclosure.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import 'section_label.dart';
import '../../../../core/utils/editor_value_format.dart';

// Stroke width = clamp(effectiveDim × fraction, minPx, maxPx).
// Fractions are tuned so 1080-square (the most common design
// canvas) lands at ≈1 / ≈4 / ≈11 px. Shared by every layer type so
// image-borders and shape-borders scale identically.
const double _thinFraction = 0.001; // ≈ 0.1 % of canvas
const double _mediumFraction = 0.004; // ≈ 0.4 % of canvas
const double _boldFraction = 0.010; // ≈ 1.0 % of canvas

const double _thinMin = 1, _thinMax = 12;
const double _mediumMin = 3, _mediumMax = 48;
const double _boldMin = 8, _boldMax = 120;

/// Adapter closing the gap between [LayerBorderBody]'s shared UI and
/// each layer type's real behavioural divergences (Phase 4 plan
/// §4.2): shape's `strokeColor` is nullable with a `clearColor`
/// None-chip semantic, while image's `borderColor` is always set;
/// shape additionally gates the whole panel on whether the shape
/// kind is "stroked" (line/arrow — colour comes from `fillColor`,
/// not this panel); image has no such gate and adds a precision
/// slider shape's panel doesn't have.
class BorderPanelAdapter<L extends EditorLayer> {
  const BorderPanelAdapter({
    required this.command,
    required this.read,
    required this.hasColor,
    this.isStrokedKind,
    this.colorToPromote,
    this.showPrecisionSlider = false,
    required this.shell,
  });

  final EditorCommand Function({
    required String layerId,
    Color? color,
    bool clearColor,
    double? width,
    bool live,
  })
  command;

  final ({Color? color, double width}) Function(L layer) read;

  /// Whether [layer] currently has an explicit border colour set.
  /// Image layers always do; shape layers may not.
  final bool Function(L layer) hasColor;

  /// True for shape kinds whose visible "border" is really the
  /// shape's own stroke — the Colour section and the "None"
  /// thickness chip are hidden and no colour is promoted on a
  /// thickness pick. `null` (image's default) means "never".
  final bool Function(L layer)? isStrokedKind;

  /// Colour to promote when a non-"None" thickness chip is tapped.
  /// `null` (image's default) means thickness chips never touch
  /// colour — only the Colour section's own picks do.
  final Color? Function(L layer)? colorToPromote;

  /// Image's border panel additionally exposes a precision slider
  /// under an "Adjust precisely" disclosure; shape's does not.
  final bool showPrecisionSlider;

  /// Wraps [child] in the per-tool `Shape`/`ImagePanelShell`.
  final Widget Function({required Widget child}) shell;
}

/// Shared "Border" sub-tool panel body for any layer type with a
/// [BorderPanelAdapter]. Unifies `ShapeBorderBody`/`ImageBorderBody`
/// (Phase 4 plan §4.2) behind explicit adapter hooks rather than a
/// straight merge, since the two panels have real behavioural
/// divergences (see [BorderPanelAdapter]'s doc).
///
/// The precision width slider AND the colour picker follow the
/// interaction contract's §2 preview channel: ticks stage an
/// overlay preview, release/settle commits ONE non-live command
/// (structurally one undo entry per interaction). Chips stay
/// discrete non-live commands (§3).
class LayerBorderBody<L extends EditorLayer> extends ConsumerStatefulWidget {
  const LayerBorderBody({
    super.key,
    required this.layer,
    required this.adapter,
  });

  final L layer;
  final BorderPanelAdapter<L> adapter;

  @override
  ConsumerState<LayerBorderBody<L>> createState() => _LayerBorderBodyState<L>();
}

class _LayerBorderBodyState<L extends EditorLayer>
    extends ConsumerState<LayerBorderBody<L>> {
  bool _isStroked(L layer) =>
      widget.adapter.isStrokedKind?.call(layer) ?? false;

  // ─── Contract §2 slider preview channel ─────────────────────────
  //
  // The pending command is the exact command release will execute;
  // each tick APPLIES it to the committed doc and stages the result
  // on the overlay, so preview == commit by construction.
  // `EditorSliderRow.onDragEnd` also fires on pointer-cancel, so an
  // interrupted drag still commits the last previewed value (§7).
  EditorCommand? _pendingSliderCommand;

  void _previewSlider(EditorCommand cmd) {
    _pendingSliderCommand = cmd;
    final doc = ref.read(documentControllerProvider);
    final preview = cmd.apply(doc).layerById(widget.layer.id);
    if (preview != null) {
      ref.read(liveOverlayProvider.notifier).replaceLayer(preview);
    }
  }

  void _commitSlider() {
    final cmd = _pendingSliderCommand;
    _pendingSliderCommand = null;
    if (cmd == null) return;
    // Clear-then-execute in one synchronous run — no flash-back
    // frame (same pattern as text's commitLiveEdit).
    ref.read(liveOverlayProvider.notifier).clear();
    ref.read(documentControllerProvider.notifier).execute(cmd);
  }

  @override
  void dispose() {
    if (_pendingSliderCommand != null) {
      ref.read(liveOverlayProvider.notifier).clear();
    }
    super.dispose();
  }

  void _commit({Color? c, bool clearColor = false, double? w}) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          widget.adapter.command(
            layerId: widget.layer.id,
            color: c,
            clearColor: clearColor,
            width: w,
          ),
        );
  }

  /// Width to bundle with a colour preview/commit: promote to
  /// [medium] when the COMMITTED layer has no visible border yet
  /// (width 0 or no colour), so the pick is immediately visible.
  /// Read from the committed doc, not the merged payload — the
  /// payload flips to "has border" after the first preview frame,
  /// but every preview command re-applies against the still-
  /// unchanged committed doc, so the promotion must persist for
  /// the whole drag.
  double? _colorCommitWidth(double medium) {
    final l = ref.read(documentControllerProvider).layerById(widget.layer.id);
    if (l is! L) return null;
    final f = widget.adapter.read(l);
    final has = f.width > 0 && widget.adapter.hasColor(l);
    return has ? null : medium;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final adapter = widget.adapter;
    final layer = widget.layer;
    final fields = adapter.read(layer);
    final width = fields.width;
    final displayColor = fields.color ?? const Color(0xFF000000);
    final hasColor = adapter.hasColor(layer);
    final stroked = _isStroked(layer);

    // Canvas-aware preset widths via the central helper. Same
    // formula on every canvas — no reference size, no per-size case.
    final doc = ref.watch(documentControllerProvider);
    final thin = CanvasSizing.proportionalStroke(
      doc,
      fraction: _thinFraction,
      minPx: _thinMin,
      maxPx: _thinMax,
    );
    final medium = CanvasSizing.proportionalStroke(
      doc,
      fraction: _mediumFraction,
      minPx: _mediumMin,
      maxPx: _mediumMax,
    );
    final bold = CanvasSizing.proportionalStroke(
      doc,
      fraction: _boldFraction,
      minPx: _boldMin,
      maxPx: _boldMax,
    );

    // Stroked kinds reuse strokeWidth for line thickness; their
    // visible colour comes from `fillColor` so the "Border colour"
    // row would be visually unhooked. Keep the panel limited to
    // thickness for these kinds — and their "None" thickness chip
    // is meaningless (the line IS the shape), so drop it too.
    final thicknessLabel = stroked
        ? context.l10n.strokeWidthLabel
        : context.l10n.thicknessLabel;

    return adapter.shell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(thicknessLabel),
          _BorderThicknessChips(
            width: width,
            hasColor: hasColor,
            allowNone: !stroked,
            onPick: (w) {
              EditorHaptics.toggle();
              if (w == 0) {
                // None — drop the colour too so re-tapping a
                // thickness later starts from a clean default.
                _commit(clearColor: true, w: 0);
              } else {
                _commit(c: adapter.colorToPromote?.call(layer), w: w);
              }
            },
            thin: thin,
            medium: medium,
            bold: bold,
          ),
          if (!stroked) ...[
            const SizedBox(height: 12),
            SectionLabel(context.l10n.colorLabel),
            // The shared two-level picker, embedded. Picking a
            // colour with no border yet promotes the width to
            // `medium` so the pick is immediately visible.
            // Contract §2 (tb2 5/16): drags stage overlay previews
            // and the settled change commits ONE undoable command.
            // Recents and alpha policy live in the picker.
            ColorPickerBody(
              initial: displayColor,
              title: context.l10n.borderColorTitle,
              onChanged: (c) => _previewSlider(
                adapter.command(
                  layerId: layer.id,
                  color: c,
                  width: _colorCommitWidth(medium),
                ),
              ),
              onCommitted: (_) => _commitSlider(),
            ),
            if (adapter.showPrecisionSlider) ...[
              const SizedBox(height: 6),
              PrecisionDisclosure(
                compact: true,
                icon: Icons.tune_rounded,
                titleClosed: context.l10n.adjustPrecisely,
                subtitle: context.l10n.widthLabel,
                chevronColorClosed: tokens.accent,
                chevronColorOpen: tokens.accent,
                children: [
                  const SizedBox(height: 4),
                  EditorSliderRow(
                    label: context.l10n.widthLabel,
                    readoutWidth: 40,
                    value: width,
                    // Slider headroom: let users dial up to 2× Bold
                    // so the precision affordance always reaches
                    // "chunkier than the last preset" without ever
                    // being smaller than the legacy 20-px ceiling.
                    max: math.max(20.0, bold * 2),
                    format: (v) =>
                        EditorValueFormat.of(context).digits(v.round()),
                    onChanged: (w) => _previewSlider(
                      adapter.command(layerId: layer.id, width: w),
                    ),
                    onDragEnd: _commitSlider,
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 4-chip thickness picker (fewer when [allowNone] is false).
/// Mirrors the Text-mode style-chip grammar (soft primary tint when
/// selected, neutral surface otherwise).
class _BorderThicknessChips extends StatelessWidget {
  const _BorderThicknessChips({
    required this.width,
    this.hasColor = true,
    this.allowNone = true,
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
    // "Medium" on a 4K canvas still matches its chip cleanly. Floor
    // at 0.25 keeps the small-canvas 1/4/10 distinction crisp.
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
            child: _BorderChip(
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

class _BorderChip extends StatelessWidget {
  const _BorderChip({
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
    return PresetChip.option(
      icon: icon,
      iconSize: iconSize,
      label: label,
      selected: selected,
      onTap: onTap,
    );
  }
}
