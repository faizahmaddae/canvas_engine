// Shadow precision panel pieces (Phase 2A commit 4): extracted
// verbatim from the text_mode_toolbar part-file library
// (text_decoration_panels.dart). Rename-only promotions — every
// symbol here is consumed by the library's sheet bodies.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../l10n/app_localizations.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../engine/modules/text/text_layer.dart';
import '../../../../text/application/text_tool_controller.dart';
import '../../../../ui/editor_slider_row.dart';
import '../../../../ui/precision_disclosure.dart';
import '../../../widgets/controls/precision_divider.dart';
import '../../../widgets/controls/slider_row.dart';

/// "Adjust precisely" disclosure for the Shadow panel. Mirrors the
/// Background/Border treatment — single chevron, whole-row tappable,
/// no nested arrows. Hosts blur and opacity sliders inline.
class ShadowPrecisionAdvanced extends ConsumerWidget {
  const ShadowPrecisionAdvanced({super.key, required this.style});
  final TextStyleSpec style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final shadow = style.shadowColor;
    final labelStyle = flatSliderLabelStyle(context);
    final readoutStyle = flatSliderReadoutStyle(context);
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      chevronSize: 18,
      children: [
        const PrecisionDivider(),
        EditorSliderRow(
          label: context.l10n.blurLabel,
          labelWidth: 96,
          value: style.shadowBlur,
          max: 40,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setShadowBlur,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        if (shadow != null)
          EditorSliderRow(
            label: context.l10n.opacityLabel,
            labelWidth: 96,
            value: shadow.a * 100,
            max: 100,
            format: (v) => '${v.toStringAsFixed(0)}%',
            onChanged: (v) =>
                ctrl.setShadowColor(shadow.withValues(alpha: v / 100)),
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
      ],
    );
  }
}

bool shadowMatches(TextStyleSpec style, ShadowPreset p) {
  final c = style.shadowColor;
  if (c == null) return false;
  return (style.shadowBlur - p.blur).abs() < 0.5 &&
      (c.a - p.opacity).abs() < 0.02;
}

void applyShadowPreset(
  WidgetRef ref,
  ShadowPreset p, {
  required Color baseColor,
}) {
  final ctrl = ref.read(textToolControllerProvider.notifier);
  ctrl.beginStyleDrag();
  ctrl.setShadowBlur(p.blur);
  ctrl.setShadowColor(baseColor.withValues(alpha: p.opacity));
  ctrl.endStyleDrag();
}

const List<IconData> shadowPresetIcons = [
  Icons.cloud_outlined, // Soft
  Icons.crop_din_rounded, // Hard
  Icons.flare_rounded, // Glow
  Icons.vertical_align_top_rounded, // Lift
];

/// Macro preset for the Shadow sub-tool. Writes blur + opacity in
/// one shot. Color and offset stay user-controlled (those are intent,
/// not aesthetic style).
///
/// [id] is a stable internal identity used only for matching/l10n
/// lookup (see [shadowPresetLabel]) — never rendered directly.
class ShadowPreset {
  const ShadowPreset({
    required this.id,
    required this.blur,
    required this.opacity,
  });
  final String id;
  final double blur;
  final double opacity; // 0..1
}

const List<ShadowPreset> shadowPresets = [
  ShadowPreset(id: 'soft', blur: 16, opacity: 0.30),
  ShadowPreset(id: 'hard', blur: 2, opacity: 0.80),
  ShadowPreset(id: 'glow', blur: 24, opacity: 0.60),
  ShadowPreset(id: 'lift', blur: 8, opacity: 0.50),
];

String shadowPresetLabel(AppLocalizations l10n, ShadowPreset preset) {
  return switch (preset.id) {
    'soft' => l10n.softOption,
    'hard' => l10n.hardOption,
    'glow' => l10n.glowOption,
    'lift' => l10n.liftOption,
    _ => preset.id,
  };
}

/// Fixed magnitude for [PanelDirectionPad] direction taps on the
/// Shadow panel. Uses the current offset's own magnitude if the
/// user already dialled a distance, otherwise a sensible default
/// that reads as a real shadow on canvas.
double shadowDirectionMagnitude(Offset offset) {
  final m = offset.distance;
  return m < 1.0 ? 6.0 : m.clamp(2.0, 24.0);
}
