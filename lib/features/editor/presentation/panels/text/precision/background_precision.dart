// Background precision panel pieces (Phase 2A commit 4): extracted
// verbatim from the text_mode_toolbar part-file library
// (text_decoration_panels.dart). Rename-only promotions — every
// symbol here is consumed by the library's sheet bodies.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../l10n/l10n.dart';
import '../../../../engine/modules/text/text_layer.dart';
import '../../../../text/application/text_tool_controller.dart';
import '../../../../ui/editor_slider_row.dart';
import '../../../../ui/precision_disclosure.dart';
import '../../../widgets/controls/precision_divider.dart';
import '../../../widgets/controls/slider_row.dart';

/// "Adjust precisely" disclosure for the Background panel. Same
/// flat header treatment as `_SizePrecisionAdvanced` and the
/// Layout cards: whole row is tappable, single chevron, no nested
/// arrows. Hosts four [EditorSliderRow]s when expanded.
class BackgroundPrecisionAdvanced extends ConsumerWidget {
  const BackgroundPrecisionAdvanced({super.key, required this.style});
  final TextStyleSpec style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final bg = style.backgroundColor;
    final labelStyle = flatSliderLabelStyle(context);
    final readoutStyle = flatSliderReadoutStyle(context);
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      chevronSize: 18,
      children: [
        const PrecisionDivider(),
        EditorSliderRow(
          label: context.l10n.roundnessLabel,
          labelWidth: 96,
          // backgroundRadius is a percent (0..1) of the box's
          // shorter side; UI drives 0..100 directly.
          value: (style.backgroundRadius * 100).clamp(0.0, 100.0),
          max: 100,
          format: (v) => '${v.toStringAsFixed(0)}%',
          onChanged: (v) => ctrl.setBackgroundRadius(v / 100),
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        EditorSliderRow(
          label: context.l10n.verticalPaddingLabel,
          labelWidth: 96,
          value: style.backgroundPaddingY,
          max: 64,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setBackgroundPaddingY,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        EditorSliderRow(
          label: context.l10n.horizontalPaddingLabel,
          labelWidth: 96,
          value: style.backgroundPaddingX,
          max: 64,
          format: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: ctrl.setBackgroundPaddingX,
          onDragStart: ctrl.beginStyleDrag,
          onDragEnd: ctrl.endStyleDrag,
          haptics: EditorSliderHaptics.startTickEnd,
          labelStyle: labelStyle,
          readoutStyle: readoutStyle,
        ),
        if (bg != null)
          EditorSliderRow(
            label: context.l10n.opacityLabel,
            labelWidth: 96,
            value: bg.a * 100,
            max: 100,
            format: (v) => '${v.toStringAsFixed(0)}%',
            onChanged: (v) =>
                ctrl.setBackgroundColor(bg.withValues(alpha: v / 100)),
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

/// Background preset matcher (extracted from the Phase-A widget so
/// the new tile-row code path can re-use the same tolerance rules).
bool bgMatches(TextStyleSpec style, BgPreset p) {
  // Radius is a percent (0..1) now — "Pill" matches anything at
  // (or essentially at) full roundness.
  final pillish = p.id == 'pill' && style.backgroundRadius >= 0.99;
  final radiusEq = pillish || (style.backgroundRadius - p.radius).abs() < 0.02;
  return radiusEq &&
      (style.backgroundPaddingX - p.padX).abs() < 0.5 &&
      (style.backgroundPaddingY - p.padY).abs() < 0.5;
}

void applyBgPreset(WidgetRef ref, BgPreset p) {
  final ctrl = ref.read(textToolControllerProvider.notifier);
  ctrl.beginStyleDrag();
  final r = p.id == 'pill' ? 1.0 : p.radius;
  ctrl.setBackgroundRadius(r);
  ctrl.setBackgroundPaddingX(p.padX);
  ctrl.setBackgroundPaddingY(p.padY);
  ctrl.endStyleDrag();
}

// ─────────────────────────────────────────────────────────────────────
// Compact sheet building blocks
// ─────────────────────────────────────────────────────────────────────
//
// All five category sheets are built from these primitives. The goal
// is uniformity and density: every row is ~44 px tall (vs ~64 px for
// a `ListTile`), so a 4-row sheet fits in ~190 px instead of ~320 px,
// leaving the canvas visible while the user adjusts values.

//
// Macro preset records used by the new tile-row sub-tools. Each
// preset is applied via the controller's [beginStyleDrag] /
// [endStyleDrag] coalescing window so the whole macro lands as a
// single undo entry.

/// Macro preset for the Background sub-tool. Each preset writes
/// radius + padding X + padding Y in one shot. Color and opacity
/// stay user-controlled.
///
/// [id] is a stable internal identity, never displayed — display
/// text is always looked up separately via l10n at the call site
/// (see `backgroundPresets` consumers). Matching/apply logic keys
/// off [id], not a display string, so renaming a preset's shown
/// name can never silently break the "Pill" special-case below.
class BgPreset {
  const BgPreset({
    required this.id,
    required this.radius,
    required this.padX,
    required this.padY,
  });
  final String id;
  final double radius;
  final double padX;
  final double padY;
}

const List<BgPreset> backgroundPresets = [
  BgPreset(id: 'none', radius: 0, padX: 0, padY: 0),
  BgPreset(id: 'pill', radius: 1, padX: 24, padY: 8),
  BgPreset(id: 'card', radius: 0.3, padX: 16, padY: 12),
  BgPreset(id: 'tag', radius: 0.5, padX: 8, padY: 4),
];
