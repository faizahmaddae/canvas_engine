import 'package:flutter/material.dart';

import '../../../../../core/utils/haptics.dart';
import 'preset_chip.dart';

/// Canonical "presets-first, slider-secondary" control for any
/// numeric sub-tool. Layout, weights, spacing and selection logic
/// are fixed here so every numeric tool feels identical.
///
/// Drag is preview-only against a *local* in-flight value; the
/// canonical commit (and any undo entry) only fires on drag-end.
/// Preset chips commit immediately. Tap-on-preset-while-dragging
/// is impossible because the slider owns the gesture arena during
/// drag.
class PresetSliderControl extends StatefulWidget {
  const PresetSliderControl({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    required this.presets,
    required this.formatValue,
    this.label = 'Presets',
    this.fineTuneLabel = '',
    this.presetEpsilon = 0.01,
    this.leading,
    this.presetLabels,
  }) : assert(
          presetLabels == null || presetLabels.length == presets.length,
          'presetLabels must be 1:1 with presets',
        );

  /// Committed value (read from controller).
  final double value;
  final double min;
  final double max;

  /// Final commit handler. Fires on chip tap and on slider
  /// drag-end (once per drag, not per tick).
  final ValueChanged<double> onCommit;

  /// Curated values surfaced as chips above the slider.
  final List<double> presets;

  /// Render the live numeric readout / chip labels.
  final String Function(double) formatValue;

  /// Section label rendered above the chip row. Pass an empty
  /// string to hide.
  final String label;

  /// Optional caption above the slider. Default empty (the divider
  /// alone signals demotion).
  final String fineTuneLabel;

  final double presetEpsilon;

  /// Optional leading widget rendered to the left of the slider.
  final Widget? leading;

  /// Optional human-friendly chip labels (e.g. 'Thin', 'Medium').
  /// When provided, chips display these instead of numeric
  /// formatted values; the live readout still uses [formatValue].
  final List<String>? presetLabels;

  @override
  State<PresetSliderControl> createState() => _PresetSliderControlState();
}

class _PresetSliderControlState extends State<PresetSliderControl> {
  /// In-flight drag value. `null` when not dragging — the slider
  /// renders [PresetSliderControl.value] in that case.
  double? _dragValue;

  double get _liveValue =>
      (_dragValue ?? widget.value).clamp(widget.min, widget.max);

  void _onChangeStart(double v) {
    // Soft haptic on engage so the user knows the slider has
    // captured the touch — same affordance level the rest of
    // the editor's controls give on activation.
    EditorHaptics.toggle();
    setState(() => _dragValue = v);
  }

  void _onChanged(double v) {
    setState(() => _dragValue = v);
  }

  void _onChangeEnd(double v) {
    // No-op if a cancel handler already finished the drag.
    if (_dragValue == null) return;
    final committed = v.clamp(widget.min, widget.max);
    setState(() => _dragValue = null);
    // Mid-weight "committed" haptic on release — distinguishes
    // a real edit from the lighter engage tick.
    EditorHaptics.confirm();
    widget.onCommit(committed);
  }

  /// Cancel-safe end. Flutter's [Slider] does NOT call
  /// `onChangeEnd` when the gesture is canceled (system back
  /// gesture, sheet dismissed mid-drag, gesture-arena loss). The
  /// outer [Listener] funnels those pointer-cancel events here so
  /// the in-flight value is committed at its last known position.
  void _onPointerCancel() {
    final v = _dragValue;
    if (v == null) return;
    final committed = v.clamp(widget.min, widget.max);
    setState(() => _dragValue = null);
    widget.onCommit(committed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = _liveValue;
    final onPreset =
        widget.presets.any((p) => (live - p).abs() < widget.presetEpsilon);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header: section label + live readout ──────────────
        if (widget.label.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Text(
                widget.formatValue(live),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: onPreset ? scheme.primary : scheme.onSurface,
                  letterSpacing: -0.4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        // ── Preset row ────────────────────────────────────────
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: widget.presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final p = widget.presets[i];
              final chipLabel = widget.presetLabels != null
                  ? widget.presetLabels![i]
                  : widget.formatValue(p);
              return PresetChip(
                label: chipLabel,
                selected: (live - p).abs() < widget.presetEpsilon,
                onTap: () {
                  // Chip = instant commit. No drag preview.
                  widget.onCommit(p);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 10),
        if (widget.fineTuneLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              widget.fineTuneLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                letterSpacing: 0.3,
              ),
            ),
          ),
        Row(
          children: [
            SizedBox(
              width: 32,
              child: Center(child: widget.leading ?? const SizedBox.shrink()),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  activeTrackColor: scheme.primary.withValues(alpha: 0.85),
                  inactiveTrackColor:
                      scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                // [Listener] catches pointer-cancel events the
                // [Slider] swallows (no `onChangeEnd` fires on
                // gesture-arena loss / system back gesture / sheet
                // dismissed mid-drag).
                child: Listener(
                  onPointerCancel: (_) => _onPointerCancel(),
                  child: Slider(
                    min: widget.min,
                    max: widget.max,
                    value: live,
                    onChangeStart: _onChangeStart,
                    onChanged: _onChanged,
                    onChangeEnd: _onChangeEnd,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ],
    );
  }
}


