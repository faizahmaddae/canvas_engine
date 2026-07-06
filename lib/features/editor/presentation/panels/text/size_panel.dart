// Size panel (Phase 2A commit 5): extracted verbatim from the
// text_mode_toolbar part-file library (text_size_panel.dart). Rename-only
// promotion of the library-dispatch entry point; everything else
// stays private.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/l10n.dart';
import '../../../application/live_overlay_controller.dart';
import '../../../engine/core/editor_document.dart';
import '../../../engine/modules/text/text_layer.dart';
import '../../../text/application/text_tool_controller.dart';
import '../../../ui/editor_slider_row.dart';
import '../../../ui/precision_disclosure.dart';
import '../../widgets/controls/panel_chip.dart';
import '../../widgets/controls/precision_divider.dart';
import '../../widgets/controls/stepper_row.dart';

/// Broad safety clamp for direct font-size mutation (stepper +
/// exact slider). Intentionally far wider than the named-preset
/// range so A+ can climb past XXL and A- can shrink below S.
///
/// Used to live as `_TextBodies._absoluteMinFontSize` — moved here
/// with the rest of the size-preset math since this panel is its
/// only caller (Phase 4 plan §5.1).
const double _absoluteMinFontSize = 4;
const double _absoluteMaxFontSize = 2000;

/// Computes the S/M/L/XL/XXL chip values for [doc] and [content].
/// Combines a canvas factor (shorter side of the doc) with a
/// length factor (longer text → smaller chips) so the preset that
/// reads as "XL" stays visually balanced against both canvas and
/// content. Output is clamped to [8, 600] px so chips remain
/// usable on any canvas without overflowing the slider/stepper
/// range.
List<({String label, double value})> _canvasAwareSizePresets(
  EditorDocument doc,
  String content,
) {
  final base = math.min(doc.width, doc.height);
  final lengthFactor = _lengthFactor(content);
  double p(double f) =>
      (base * f * lengthFactor).clamp(8.0, 600.0).toDouble();
  return [
    (label: 'S', value: p(0.06)),
    (label: 'M', value: p(0.10)),
    (label: 'L', value: p(0.16)),
    (label: 'XL', value: p(0.24)),
    (label: 'XXL', value: p(0.34)),
  ];
}

/// Length-aware shrink factor: short labels keep full-size
/// presets, sentence-length text is dialed back to 80 %, and
/// paragraph-length text drops to 60 % so XXL never pushes a
/// long block past the canvas edges. Whitespace is intentionally
/// included — leading/trailing spaces visually consume room too.
double _lengthFactor(String content) {
  final n = content.length;
  if (n <= 10) return 1.0;
  if (n <= 25) return 0.8;
  return 0.6;
}

/// Body for the Text Size sub-tool. Owns no local state — the
/// "sticky preset" highlight lives on `TextSession` so it survives
/// rebuilds/remounts that can otherwise drop a `StatefulWidget`'s
/// state (e.g. when the selected layer flickers null between a
/// `setFontSize` write and the resulting auto-resize, the panel
/// briefly returns `SizedBox.shrink` and any local `_selectedPreset`
/// is lost). Keying the pin by layer id ensures switching to a
/// different text layer does not inherit the previous layer's
/// highlight.
class SizeBody extends ConsumerWidget {
  const SizeBody({super.key, required this.layer});
  final TextLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final doc = ref.watch(renderedDocumentProvider);
    final pin = ref.watch(
      textToolControllerProvider.select((s) => s.selectedSizePreset),
    );
    final presets = _canvasAwareSizePresets(doc, layer.content);
    final selectedLabel = (pin != null && pin.layerId == layer.id)
        ? pin.label
        : null;

    // Tolerance scales with current size so the nearest-fallback
    // selection feels right at 12 px and at 200 px alike. Only
    // applies when no sticky pin is active.
    final tolerance = math.max(1.0, style.fontSize * 0.03);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Match the Layout panel rhythm: no all-caps section
        // labels (the stepper IS the value, the chip row IS the
        // presets — both self-explanatory). The disclosure below
        // gives precise access without a header.
        const SizedBox(height: 6),
        SizeStepperRow(
          value: style.fontSize,
          min: _absoluteMinFontSize,
          max: _absoluteMaxFontSize,
          onChange: ctrl.setFontSize,
        ),
        const SizedBox(height: 12),
        WordChipRow(
          options: presets,
          current: style.fontSize,
          selectedLabel: selectedLabel,
          tolerance: tolerance,
          onPick: (value) {
            // Look the tapped value back up to recover its label;
            // identical instance equality holds because the chip
            // hands back the exact double from the same `presets`
            // list this build computed.
            final hit = presets.firstWhere(
              (p) => p.value == value,
              orElse: () => (label: '', value: value),
            );
            if (hit.label.isEmpty) {
              ctrl.setFontSize(value);
            } else {
              ctrl.setFontSizeFromPreset(
                size: value,
                presetLabel: hit.label,
                layerId: layer.id,
              );
            }
          },
        ),
        const SizedBox(height: 6),
        _SizePrecisionAdvanced(
          value: style.fontSize,
          min: _absoluteMinFontSize,
          max: _absoluteMaxFontSize,
          onChange: ctrl.setFontSize,
        ),
      ],
    );
  }
}

/// Flattened "Adjust precisely" disclosure used by the Size body:
/// one arrow, one tap to reveal value + px-presets + fine-tune
/// slider — no nested expand, no second arrow.
///
/// Style writes still route through the same controller setter
/// the dock uses (`setFontSize`), so undo coalescing, the
/// scale-aware translation in `_translateFontSizeForVisualScale`,
/// and the box auto-fit behaviour are all preserved verbatim.
class _SizePrecisionAdvanced extends ConsumerWidget {
  const _SizePrecisionAdvanced({
    required this.value,
    required this.min,
    required this.max,
    required this.onChange,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChange;

  static const List<double> _pxPresets = [12, 16, 24, 32, 48, 64, 96];

  String _format(double v) => '${v.toStringAsFixed(0)}px';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final clampedValue = value.clamp(min, max).toDouble();
    return PrecisionDisclosure(
      titleClosed: context.l10n.adjustPrecisely,
      titleOpen: context.l10n.hidePreciseControls,
      headerValue: _format(clampedValue),
      chevronSize: 18,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const PrecisionDivider(),
              const SizedBox(height: 8),
              // px presets reuse the Layout chip so the two
              // panels share one visual vocabulary.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _pxPresets)
                    LayoutPresetChip(
                      label: _format(p),
                      selected: (p - clampedValue).abs() < 0.001,
                      onTap: () => onChange(p.clamp(min, max).toDouble()),
                    ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: EditorSliderRow(
                  value: clampedValue,
                  min: min,
                  max: max,
                  showReadout: false,
                  format: _format,
                  onChanged: onChange,
                  onDragStart: ctrl.beginStyleDrag,
                  onDragEnd: ctrl.endStyleDrag,
                  haptics: EditorSliderHaptics.startTickEnd,
                  semanticLabel: context.l10n.sizeTool,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

