// Shared control kit (Phase 2A §1): extracted verbatim from the
// text_mode_toolbar library (text_layout_panel.dart +
// text_decoration_panels.dart) so every tool's panels can reuse it.
// Rename-only promotion; no behaviour change.
//
// Known 2A carry-over (decoupled in 2B): [LayoutSliderCard] talks to
// the TEXT tool controller directly for drag-coalescing seams; the
// shared kit will grow begin/end-drag callbacks instead.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../text/application/text_tool_controller.dart';
import 'panel_chip.dart';

typedef LayoutPreset = ({String label, double value});

/// Label style shared by every migrated flat-row slider in the
/// Background/Border/Shadow precision disclosures — larger and
/// bolder than [EditorSliderRow]'s shape/image default, so the
/// text-panel row keeps its existing look after unifying onto the
/// shared primitive.
TextStyle? flatSliderLabelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodyMedium?.copyWith(
    color: AppTokens.of(context).textPrimary,
    fontWeight: FontWeight.w600,
    fontSize: 13,
  );
}

/// Readout style shared by the same rows — tabular figures keep the
/// digits from jittering width while dragging.
TextStyle? flatSliderReadoutStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelMedium?.copyWith(
    color: AppTokens.of(context).textSecondary,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Flat row used by the Layout panel for both Line height and
/// Letter spacing. Editor-feel (no card / shadow / border):
///   * Tap the header row anywhere to expand the inline slider.
///   * Preset chips sit directly below the header — they are the
///     primary affordance, the slider is secondary.
///   * Parent owns expand state so only one row is open at a time.
class LayoutSliderCard extends ConsumerStatefulWidget {
  const LayoutSliderCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.format,
    required this.presets,
    required this.min,
    required this.max,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onChange,
  });

  /// Leading glyph that disambiguates the row at a glance — line
  /// height vs letter spacing read identically without it.
  final IconData icon;
  final String label;
  final double value;
  final String Function(double) format;
  final List<LayoutPreset> presets;
  final double min;
  final double max;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<double> onChange;

  @override
  ConsumerState<LayoutSliderCard> createState() => _LayoutSliderCardState();
}

class _LayoutSliderCardState extends ConsumerState<LayoutSliderCard> {
  bool _dragInFlight = false;
  double? _lastTickValue;

  void _set(double v) {
    final clamped = v.clamp(widget.min, widget.max).toDouble();
    widget.onChange(clamped);
  }

  void _maybeTick(double v) {
    final span = widget.max - widget.min;
    if (span <= 0) return;
    final step = span / 20.0;
    final last = _lastTickValue;
    if (last == null || (v - last).abs() >= step) {
      _lastTickValue = v;
      EditorHaptics.snap();
    }
  }

  void _endDrag() {
    if (!_dragInFlight) return;
    _dragInFlight = false;
    _lastTickValue = null;
    ref.read(textToolControllerProvider.notifier).endStyleDrag();
  }

  int _selectedPresetIndex() {
    for (var i = 0; i < widget.presets.length; i++) {
      if ((widget.presets[i].value - widget.value).abs() < 0.001) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final muted = tokens.textSecondary;
    final clampedValue = widget.value.clamp(widget.min, widget.max).toDouble();
    final selectedIndex = _selectedPresetIndex();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Whole header row is tappable — no card, no border, no
        // shadow. Editor-feel: looks like a list row, not a setting.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              EditorHaptics.tap();
              widget.onExpandedChanged(!widget.expanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 18,
                    color: widget.expanded ? tokens.accent : muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  // Value + chevron grouped into a small pill so
                  // the trailing affordance reads as one tap target,
                  // not a stray number next to a stray arrow. Pill
                  // tints when the row is expanded for clear state.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: widget.expanded
                          ? tokens.accent.withValues(alpha: 0.1)
                          : tokens.surfaceMuted.withValues(alpha: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.format(clampedValue),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: widget.expanded ? tokens.accent : muted,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 2),
                        AnimatedRotation(
                          turns: widget.expanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: widget.expanded ? tokens.accent : muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Always-visible preset chips — primary UI.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < widget.presets.length; i++)
                LayoutPresetChip(
                  label: widget.presets[i].label,
                  selected: i == selectedIndex,
                  onTap: () => _set(widget.presets[i].value),
                ),
            ],
          ),
        ),
        // Inline secondary slider, subtle visual weight.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: widget.expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Listener(
                      onPointerCancel: (_) => _endDrag(),
                      child: Slider(
                        value: clampedValue,
                        min: widget.min,
                        max: widget.max,
                        onChangeStart: (v) {
                          _dragInFlight = true;
                          _lastTickValue = v;
                          EditorHaptics.toggle();
                          ref
                              .read(textToolControllerProvider.notifier)
                              .beginStyleDrag();
                        },
                        onChanged: (v) {
                          _set(v);
                          _maybeTick(v);
                        },
                        onChangeEnd: (_) {
                          if (!_dragInFlight) return;
                          EditorHaptics.confirm();
                          _endDrag();
                        },
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
