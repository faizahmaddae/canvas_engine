import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/shape_commands.dart';
import '../../engine/modules/shape/shape_layer.dart';
import '../../presentation/widgets/inline_color_body.dart';
import '../../presentation/widgets/recent_colors_controller.dart';
import '../../presentation/widgets/section_label.dart';
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

  void _commitRadius(double r, {bool live = false}) {
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          SetShapeRadiusCommand(
            layerId: widget.layer.id,
            radius: r,
            live: live,
          ),
        );
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
          // Approved compact color UI — same widget every other
          // colour-bearing panel uses. Recents are sourced from the
          // app-wide [recentColorsControllerProvider] so a custom
          // colour dialled in here surfaces in Text / Image / etc.
          InlineColorBody(
            current: layer.fillColor,
            recents: ref.watch(recentColorsControllerProvider),
            palette: InlineColorBody.defaultPalette,
            compactRecents: true,
            onPick: (picked) {
              EditorHaptics.toggle();
              _commitFill(c: picked);
            },
            onCustom: () async {
              final original = layer.fillColor;
              final picked = await showColorPickerSheet(
                context,
                initial: original,
                recents: ref.read(recentColorsControllerProvider),
                onLiveChange: (c) => _commitFill(c: c, live: true),
                title: context.l10n.fillColorTitle,
              );
              if (picked == null) {
                _commitFill(c: original);
                return;
              }
              ref
                  .read(recentColorsControllerProvider.notifier)
                  .remember(picked);
            },
          ),
          const SizedBox(height: 14),
          SectionLabel(context.l10n.opacityLabel),
          _OpacitySlider(
            value: layer.fillOpacity,
            onChange: (v) => _commitFill(opacity: v, live: true),
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
            _RadiusSlider(
              value: layer.cornerRadius.clamp(0.0, maxRadius),
              max: maxRadius == 0 ? 1 : maxRadius,
              onChange: (v) => _commitRadius(v, live: true),
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

class _OpacitySlider extends StatelessWidget {
  const _OpacitySlider({required this.value, required this.onChange});

  final double value;
  final ValueChanged<double> onChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (value.clamp(0.0, 1.0) * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: value.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              onChanged: onChange,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$pct%',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadiusSlider extends StatelessWidget {
  const _RadiusSlider({
    required this.value,
    required this.max,
    required this.onChange,
  });

  final double value;
  final double max;
  final ValueChanged<double> onChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: value.clamp(0.0, max),
              min: 0,
              max: max,
              onChanged: onChange,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${value.round()}',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
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
    final scheme = Theme.of(context).colorScheme;
    // Unified `DockToolTile`-aligned chip grammar (2026-05):
    // single bg channel, no glow, no heavy surface fill on rest.
    // Selected = primary @ 12%, unselected = transparent so the
    // chip row reads as a clean inline control.
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.onSurface.withValues(alpha: 0.04);
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
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
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
