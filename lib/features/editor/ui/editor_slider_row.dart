import 'package:flutter/material.dart';

import '../../../core/utils/haptics.dart';

/// Haptic feedback profile for [EditorSliderRow]. Kept as a caller
/// parameter (not baked in) so unifying the widget never silently
/// changes an existing surface's feel — see
/// docs/phase4-ui-foundation-plan-2026-07.md §3.1.
enum EditorSliderHaptics {
  /// No haptics. Matches the shape/image/border/mask-edit sliders.
  none,

  /// One tick on drag-start, one on drag-end. No profile in the
  /// matrix uses this today; reserved for a future call site.
  startEnd,

  /// One tick on drag-start, a light tick roughly every 1/20th of
  /// the slider's span while dragging, one on drag-end. Matches the
  /// text-panel sliders' feel exactly.
  startTickEnd,
}

/// Canonical "label + Slider + formatted value" row.
///
/// Unifies the row-grammar slider copies found across the editor
/// (shape/image shadow `_LabeledSlider` — byte-identical pair —, the
/// image-adjust variant, shape-style's no-label opacity/radius
/// sliders, image-border's precision slider, the mask-edit feather
/// row, and the text-panel `_FlatSliderRow`). See the Phase 4 plan's
/// slider variant matrix for the full inventory this widget must
/// satisfy.
///
/// Deliberately NOT covered: `color_picker_sheet`'s label-above
/// wrapper around a custom gradient track (not a [Slider]), and the
/// export sheet's JPG-quality header-above-slider layout (a
/// different structural grammar — its migration composes a bespoke
/// header with `EditorSliderRow(label: null, ...)` below it).
///
/// ## Commit semantics
///
/// This widget never dispatches commands. The four commit strategies
/// observed in the matrix (live command-stream per tick, a
/// `beginStyleDrag`/`endStyleDrag` window around the whole drag, a
/// local draft committed only on drag-end, and a live-overlay
/// preview committed on drag-end) all express through [onChanged] +
/// the optional [onDragStart]/[onDragEnd] hooks — the caller decides
/// what "commit" means for its surface.
///
/// ## Accessibility
///
/// Every row wraps in `Semantics(label: ...)` with the underlying
/// [Slider.semanticFormatterCallback] set to [format] — this is a
/// deliberate behaviour addition (Phase 4 plan D2): before this
/// widget, only 2 of ~20 slider-family controls in the app exposed
/// anything to a screen reader.
class EditorSliderRow extends StatefulWidget {
  const EditorSliderRow({
    super.key,
    this.label,
    this.labelWidth = 56,
    required this.value,
    this.min = 0,
    required this.max,
    this.divisions,
    this.enabled = true,
    required this.format,
    this.readoutWidth = 44,
    required this.onChanged,
    this.onDragStart,
    this.onDragEnd,
    this.haptics = EditorSliderHaptics.none,
    this.semanticLabel,
  });

  /// Label rendered in a fixed-width leading column. `null` omits
  /// the column entirely (the shape-style opacity/radius sliders
  /// have no label — just slider + inline readout).
  final String? label;

  /// Width of the label column. The shape/image shadow pair uses
  /// 56; the image-adjust panel uses 80 (longer knob names).
  final double labelWidth;

  final double value;
  final double min;
  final double max;

  /// Discrete stop count. Only the export sheet's JPG-quality slider
  /// uses this today (30 stops between 0.7 and 1.0).
  final int? divisions;

  /// When false, the slider is rendered disabled (`onChanged: null`).
  final bool enabled;

  /// Formats [value] for the trailing readout AND the accessibility
  /// announcement (`Slider.semanticFormatterCallback`).
  final String Function(double) format;

  final double readoutWidth;

  final ValueChanged<double> onChanged;

  /// Fires once when a drag gesture begins. Callers use this for
  /// `beginStyleDrag()`-style transaction windows; independent of
  /// [haptics].
  final VoidCallback? onDragStart;

  /// Fires once when a drag gesture ends — including when the
  /// gesture is cancelled (system back gesture, sheet dismissed
  /// mid-drag, arena loss), which `Slider.onChangeEnd` does NOT
  /// cover on its own. Mirrors the `Listener(onPointerCancel: ...)`
  /// pattern every existing drag-window slider already relies on.
  final VoidCallback? onDragEnd;

  final EditorSliderHaptics haptics;

  /// Accessibility label. Defaults to [label]; surfaces with no
  /// visible label (shape-style's opacity/radius sliders) MUST pass
  /// this explicitly or the row is unreachable by name for screen
  /// reader users.
  final String? semanticLabel;

  @override
  State<EditorSliderRow> createState() => _EditorSliderRowState();
}

class _EditorSliderRowState extends State<EditorSliderRow> {
  bool _dragInFlight = false;
  double? _lastTickValue;

  void _onChangeStart(double v) {
    _dragInFlight = true;
    _lastTickValue = v;
    if (widget.haptics != EditorSliderHaptics.none) {
      EditorHaptics.toggle();
    }
    widget.onDragStart?.call();
  }

  void _onChanged(double v) {
    widget.onChanged(v);
    if (widget.haptics == EditorSliderHaptics.startTickEnd) {
      _maybeTick(v);
    }
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
    if (widget.haptics != EditorSliderHaptics.none) {
      EditorHaptics.confirm();
    }
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = widget.value.clamp(widget.min, widget.max);
    final label = widget.label;

    final slider = Listener(
      onPointerCancel: (_) => _endDrag(),
      child: Slider(
        value: clamped,
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        // A stepped slider (divisions != null) shows the Material
        // drag tooltip with the formatted value — matches the JPG-
        // quality slider's existing '$pct%' tooltip exactly.
        // Continuous sliders never showed a tooltip; unchanged.
        label: widget.divisions != null ? widget.format(clamped) : null,
        semanticFormatterCallback: widget.format,
        onChangeStart: widget.enabled ? _onChangeStart : null,
        onChanged: widget.enabled ? _onChanged : null,
        onChangeEnd: widget.enabled ? (_) => _endDrag() : null,
      ),
    );

    return Semantics(
      label: widget.semanticLabel ?? label,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: Row(
          children: [
            if (label != null)
              SizedBox(
                width: widget.labelWidth,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(child: slider),
            SizedBox(
              width: widget.readoutWidth,
              child: Text(
                widget.format(widget.value),
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
      ),
    );
  }
}
