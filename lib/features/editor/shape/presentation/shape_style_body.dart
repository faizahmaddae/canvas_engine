import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/shape_commands.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/widgets/section_label.dart';
import '../../ui/editor_slider_row.dart';
import 'shape_panel_shell.dart';

/// Expanded panel body for the Shape sub-tool's "Style" tab.
///
/// Sections:
///   * **Fill colour** — palette + custom picker, committed via
///     [SetShapeFillCommand].
///   * **Fill opacity** — 0..1 slider.
///   * **Corner radius** — slider + Sharp / Rounded / Pill quick
///     presets. Hidden / disabled for circles (which always render
///     as a perfect ellipse and ignore radius at paint time).
class ShapeStyleBody extends ConsumerStatefulWidget {
  const ShapeStyleBody({super.key, required this.layer});

  final ShapeLayer layer;

  @override
  ConsumerState<ShapeStyleBody> createState() => _ShapeStyleBodyState();
}

class _ShapeStyleBodyState extends ConsumerState<ShapeStyleBody> {
  // ─── Contract §2 slider preview channel (tb2 3/16) ──────────────
  //
  // The pending command is the exact command release will execute;
  // each tick APPLIES it to the committed doc and stages the result
  // on the overlay, so preview == commit by construction — which
  // also means an opacity-only drag inherits SetShapeFillCommand's
  // `_targetFill` semantics and can never clear a gradient fill.
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

  void _commitFill({Color? c, double? opacity, bool live = false}) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          SetShapeFillCommand(
            layerId: widget.layer.id,
            color: c,
            opacity: opacity,
            live: live,
          ),
        );
  }

  void _commitRadius(double r) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetShapeRadiusCommand(layerId: widget.layer.id, radius: r));
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final supportsRadius =
        layer.kind == ShapeKind.rectangle ||
        layer.kind == ShapeKind.roundedRectangle;
    final isStroked = isStrokedShapeKind(layer.kind);
    final shorterSide = layer.transform.size.shortestSide;
    // Radius is capped at half the shorter side so the rectangle
    // can become a perfect pill but never invert into nonsense.
    final maxRadius = (shorterSide / 2).clamp(0.0, 9999.0);

    return ShapePanelShell(
      title: context.l10n.styleTool,
      icon: Icons.palette_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stroked kinds (line / arrow) have no fill body — the
          // fillColor field doubles as the stroke colour, so the
          // section reads as "Color" rather than "Fill".
          SectionLabel(
            isStroked ? context.l10n.colorLabel : context.l10n.fillLabel,
          ),
          // The shared two-level picker, embedded. Drags stream
          // live (transient) commits; settled changes commit for
          // real so each pick is one undo step. Recents and alpha
          // policy live inside the picker.
          ColorPickerBody(
            initial: layer.fillColor,
            title: isStroked
                ? context.l10n.colorLabel
                : context.l10n.fillColorTitle,
            onChanged: (c) => _commitFill(c: c, live: true),
            onCommitted: (c) => _commitFill(c: c),
          ),
          const SizedBox(height: 14),
          SectionLabel(context.l10n.opacityLabel),
          EditorSliderRow(
            value: layer.fillOpacity,
            max: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => _previewSlider(
              SetShapeFillCommand(layerId: layer.id, opacity: v),
            ),
            onDragEnd: _commitSlider,
            semanticLabel: context.l10n.opacityLabel,
          ),
          if (supportsRadius) ...[
            const SizedBox(height: 14),
            SectionLabel(context.l10n.cornerRadiusLabel),
            _RadiusPresets(
              current: layer.cornerRadius,
              max: maxRadius,
              onPick: (r) {
                EditorHaptics.toggle();
                _commitRadius(r);
              },
            ),
            const SizedBox(height: 6),
            EditorSliderRow(
              value: layer.cornerRadius.clamp(0.0, maxRadius),
              max: maxRadius == 0 ? 1 : maxRadius,
              format: (v) => '${v.round()}',
              onChanged: (v) => _previewSlider(
                SetShapeRadiusCommand(layerId: layer.id, radius: v),
              ),
              onDragEnd: _commitSlider,
              semanticLabel: context.l10n.cornerRadiusLabel,
            ),
          ],
          // Trailing breathing room so the last control (radius
          // slider for rectangles, opacity slider otherwise)
          // never reads as flush against the panel's bottom edge.
          // The shell adds 12dp + safe-area below; this is the
          // visual gutter inside the scroll region.
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Three quick-set chips: Sharp (0), Rounded (~16), Pill (= maxRadius).
class _RadiusPresets extends StatelessWidget {
  const _RadiusPresets({
    required this.current,
    required this.max,
    required this.onPick,
  });

  final double current;
  final double max;
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    const rounded = 16.0;
    final pill = max;
    _Key activeKey;
    if (current <= 0.5) {
      activeKey = _Key.sharp;
    } else if ((current - pill).abs() < 0.5) {
      activeKey = _Key.pill;
    } else if ((current - rounded).abs() < 0.5) {
      activeKey = _Key.rounded;
    } else {
      activeKey = _Key.custom;
    }
    final entries = <(_Key, double, String)>[
      (_Key.sharp, 0, context.l10n.sharpOption),
      (_Key.rounded, rounded.clamp(0.0, pill), context.l10n.roundedOption),
      (_Key.pill, pill, context.l10n.pillOption),
    ];
    return Row(
      children: [
        for (final entry in entries) ...[
          Expanded(
            child: _Chip(
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

enum _Key { sharp, rounded, pill, custom }

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // Unified `DockToolTile`-aligned chip grammar (2026-05):
    // single bg channel, no glow, no heavy surface fill on rest.
    // Selected = accent @ 12%, unselected = transparent so the
    // chip row reads as a clean inline control.
    final bg = selected
        ? tokens.accent.withValues(alpha: 0.12)
        : tokens.textPrimary.withValues(alpha: 0.04);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? tokens.accent : tokens.textSecondary,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
