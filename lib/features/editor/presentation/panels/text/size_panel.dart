// Size panel — compact redesign (2026-07): one control row (tappable
// value chip → exact-px keypad dialog, slider, −/＋ nudge pair) plus
// the S/M/L/XL/XXL preset chips. The value chip is the panel's ONLY
// px readout (the header chip and the «تنظیم دقیق» disclosure are
// gone); precise entry moved from the disclosure's fine-tune slider
// to the keypad dialog, which covers the same absolute 4..2000 range.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../l10n/l10n.dart';
import '../../../application/live_overlay_controller.dart';
import '../../../engine/core/editor_document.dart';
import '../../../engine/modules/text/text_layer.dart';
import '../../../text/application/text_tool_controller.dart';
import '../../../ui/editor_slider_row.dart';
import '../../widgets/controls/connected_track.dart';
import '../../../../../core/utils/editor_value_format.dart';
import '../../../../../app/theme/app_icons.dart';

/// Broad safety clamp for direct font-size mutation (nudge + exact
/// keypad entry). Intentionally far wider than the named-preset
/// range so ＋ can climb past XXL and − can shrink below S.
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
  double p(double f) => (base * f * lengthFactor).clamp(8.0, 600.0).toDouble();
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

/// Practical range for the main size slider. The absolute clamps
/// (4..2000) stay on the exact-size keypad; the slider spans the
/// canvas-aware useful band so a thumb pixel maps to a meaningful
/// step.
const double _sliderMin = 8;

double _sliderMax(List<({String label, double value})> presets) {
  var maxPreset = 0.0;
  for (final p in presets) {
    if (p.value > maxPreset) maxPreset = p.value;
  }
  return maxPreset <= 0 ? 200 : (maxPreset * 2).clamp(64, _absoluteMaxFontSize);
}

/// Perceptual nudge shared with the old stepper: ±10% of the current
/// value (rounded), floored at 1px, clamped to the absolute range.
///
/// `live: true` — repeat-firing the −/＋ pair is the sanctioned use
/// of history-window coalescing (contract §3, tb2 6/16): a burst of
/// nudges collapses to one undo entry, and the merge chain breaks
/// as soon as a different (non-live) control writes.
void _bump(TextToolController ctrl, double value, int dir) {
  final s = (value * 0.1).roundToDouble();
  final step = s < 1 ? 1 : s;
  final next = (value + dir * step)
      .clamp(_absoluteMinFontSize, _absoluteMaxFontSize)
      .toDouble();
  if ((next - value).abs() < 0.01) return;
  EditorHaptics.tap();
  ctrl.setFontSize(next, live: true);
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
        const SizedBox(height: 6),
        // The whole size story in one row: the tappable value chip
        // IS the precise entry point (keypad dialog, absolute
        // 4..2000), the slider covers the practical canvas-aware
        // band, and the −/＋ pair keeps the perceptual ±10% nudge.
        Row(
          children: [
            _SizeValueChip(
              // VISUAL px (tb2 12/16): after a corner drag the
              // FittedBox magnifies the raw fontSize — the readout
              // must show what the user sees, or a +10% nudge jumps
              // the number 2× when the write path normalizes.
              // Writes stay raw; the keypad prefills the same
              // visual number the chip shows so typing it back is
              // a no-op (setFontSize's translation reads input in
              // the identical space).
              value: ctrl.visualFontSizeOf(layer),
              onTap: () =>
                  _promptExactSize(context, ctrl, ctrl.visualFontSizeOf(layer)),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: EditorSliderRow(
                value: style.fontSize.clamp(_sliderMin, _sliderMax(presets)),
                min: _sliderMin,
                max: _sliderMax(presets),
                format: (v) => EditorValueFormat.of(context).px(v.round()),
                showReadout: false,
                onChanged: ctrl.setFontSize,
                onDragStart: ctrl.beginStyleDrag,
                onDragEnd: ctrl.endStyleDrag,
                haptics: EditorSliderHaptics.startTickEnd,
                semanticLabel: context.l10n.sizeTool,
              ),
            ),
            _NudgeButton(
              icon: AppIcons.decrement,
              semanticLabel: context.l10n.sizeDecreaseAction,
              onTap: () => _bump(ctrl, style.fontSize, -1),
            ),
            const SizedBox(width: 4),
            _NudgeButton(
              icon: AppIcons.add,
              semanticLabel: context.l10n.sizeIncreaseAction,
              onTap: () => _bump(ctrl, style.fontSize, 1),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // The named sizes as ONE five-segment instrument (the studio
        // track grammar) instead of five loose chips. Selection is
        // nearest-match: exactly one segment highlights — the sticky
        // pin wins, else the closest preset within [tolerance].
        SizedBox(
          height: 44,
          child: ConnectedTrack(
            segments: [
              for (final p in presets)
                TrackSegmentSpec(
                  semanticLabel: p.label,
                  active:
                      p.label ==
                      (selectedLabel ??
                          _nearestLabel(presets, style.fontSize, tolerance)),
                  // Haptic fires in the track segment (kit convention).
                  onTap: () => ctrl.setFontSizeFromPreset(
                    size: p.value,
                    presetLabel: p.label,
                    layerId: layer.id,
                  ),
                  child: _TrackLabel(
                    text: p.label,
                    active:
                        p.label ==
                        (selectedLabel ??
                            _nearestLabel(presets, style.fontSize, tolerance)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Nearest preset label to [current], or null when the closest one
  /// is further than [tolerance] (manual edits far from any preset
  /// clear the selection entirely).
  static String? _nearestLabel(
    List<({String label, double value})> presets,
    double current,
    double tolerance,
  ) {
    String? best;
    double bestDelta = double.infinity;
    for (final p in presets) {
      final delta = (current - p.value).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = p.label;
      }
    }
    return bestDelta <= tolerance ? best : null;
  }
}

/// Segment label on the shared 12.5px track type.
class _TrackLabel extends StatelessWidget {
  const _TrackLabel({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: active ? tokens.accentText : tokens.textPrimary,
        letterSpacing: 0.1,
      ),
    );
  }
}

/// Numeric-keypad prompt for an exact pixel size. Commits through
/// the same `setFontSize` path as every other size control, so the
/// scale-aware translation and box auto-fit behaviour hold.
Future<void> _promptExactSize(
  BuildContext context,
  TextToolController ctrl,
  double current,
) async {
  EditorHaptics.tap();
  final picked = await showDialog<double>(
    context: context,
    builder: (_) => _ExactSizeDialog(initial: current),
  );
  if (picked == null) return;
  final clamped = picked
      .clamp(_absoluteMinFontSize, _absoluteMaxFontSize)
      .toDouble();
  if ((clamped - current).abs() < 0.01) return;
  EditorHaptics.confirm();
  ctrl.setFontSize(clamped);
}

/// Owns the text controller so it outlives the dialog route's exit
/// animation (disposing it right after `showDialog` returns races
/// the still-mounted TextField).
class _ExactSizeDialog extends StatefulWidget {
  const _ExactSizeDialog({required this.initial});

  final double initial;

  @override
  State<_ExactSizeDialog> createState() => _ExactSizeDialogState();
}

class _ExactSizeDialogState extends State<_ExactSizeDialog> {
  TextEditingController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs an inherited `Localizations`, so not `initState`. The pill
    // that opens this dialog reads «۹۶px»; the box behind it used to
    // open prefilled with a Latin `96`.
    _controller ??= TextEditingController(
      text: EditorValueFormat.of(context).digits(widget.initial.round()),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _submit() {
    // A Persian keyboard types ۱۲۰; `double.tryParse` reads that as
    // null, so the dialog silently discarded what the user typed.
    Navigator.of(context).pop(
      double.tryParse(
        EditorValueFormat.toAsciiDigits(_controller!.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.exactSizeTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        inputFormatters: [EditorValueFormat.localeDigitsOnly],
        textAlign: TextAlign.center,
        decoration: const InputDecoration(suffixText: 'px'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.applyAction)),
      ],
    );
  }
}

/// The panel's single live px readout — a tappable pill that opens
/// the exact-size keypad. Same pill grammar as the header value
/// chips it replaces (tabular figures, muted fill).
class _SizeValueChip extends StatelessWidget {
  const _SizeValueChip({required this.value, required this.onTap});

  final double value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // The bordered value-instrument look the bench's type cluster
    // established — the chip reads as a readout you can open, not
    // another muted lozenge.
    return Semantics(
      button: true,
      label: context.l10n.exactSizeTitle,
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 58),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
            ),
            child: Text(
              EditorValueFormat.of(context).px(value.round()),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact −/＋ nudge button beside the size slider. Same visual
/// vocabulary as the old stepper buttons (accent-tint fill) at a
/// tighter footprint so the single control row stays light.
class _NudgeButton extends StatelessWidget {
  const _NudgeButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: tokens.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(child: Icon(icon, size: 18, color: tokens.accent)),
          ),
        ),
      ),
    );
  }
}
