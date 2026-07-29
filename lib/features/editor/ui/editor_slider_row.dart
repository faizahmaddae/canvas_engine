import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
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
/// The name is merged onto the SLIDER's own semantics node, and the
/// visible label/readout `Text`s are excluded from the tree. Both
/// halves matter: a `Semantics` wrapper around the whole row produces
/// a node ABOVE the slider's, so the SeekBar a screen reader focuses
/// and adjusts is left unnamed, and the visible label concatenates
/// onto the row node so the parameter is announced twice. The value
/// itself is carried by [Slider.semanticFormatterCallback] (set to
/// [format]), so the readout Text would be a third repetition.
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
    this.showReadout = true,
    required this.onChanged,
    this.onDragStart,
    this.onDragEnd,
    this.haptics = EditorSliderHaptics.none,
    this.semanticLabel,
    this.labelStyle,
    this.readoutStyle,
    this.origin,
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

  /// When false, omits the trailing readout column entirely. For
  /// compositions that already show the formatted value elsewhere
  /// (e.g. the export sheet's JPG-quality header, which puts the
  /// percentage above the slider) — the default readout would
  /// otherwise duplicate it.
  final bool showReadout;

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

  /// Overrides the label column's [TextStyle]. Defaults to the
  /// shape/image family's look (12px, `textSecondary`). The
  /// text-panel family uses a distinctly larger/bolder style
  /// (`bodyMedium` base, 13px, `onSurface`) — pass it explicitly
  /// there rather than letting the default silently change its feel.
  final TextStyle? labelStyle;

  /// Overrides the trailing readout's [TextStyle]. Defaults to the
  /// shape/image family's look. The text-panel family uses
  /// `labelMedium` base with tabular figures — pass it explicitly.
  final TextStyle? readoutStyle;

  /// Neutral value for a **bipolar** parameter (brightness, warmth,
  /// exposure …). When set, the filled segment runs from here to the
  /// thumb instead of from [min], and a tick marks the origin.
  ///
  /// Without it a slider whose neutral sits mid-track paints half its
  /// track filled at rest, so "untouched" and "half applied" look
  /// identical — the Look panel's five adjustment rows all showed a
  /// half-saffron track while every value was at its default. `null`
  /// (the default) keeps the plain min→thumb fill every existing
  /// unipolar row uses.
  final double? origin;

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
    final tokens = AppTokens.of(context);
    final clamped = widget.value.clamp(widget.min, widget.max);
    final label = widget.label;

    // Density pass (tb7 5/7): Material's default Slider reserves ~48dp
    // of height for a 24dp press overlay. The prototype's rows are
    // 20dp — far below a comfortable touch target — so this meets it
    // partway: the overlay shrinks to 18 and the row lands on exactly
    // the 44dp floor. Going lower would trade real usability for
    // density, which is not the trade the prototype was arguing for.
    final origin = widget.origin;
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        trackHeight: 4,
        trackShape: origin == null
            ? null
            : _OriginTrackShape(
                origin: ((origin - widget.min) / (widget.max - widget.min))
                    .clamp(0.0, 1.0),
              ),
      ),
      child: Listener(
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
      ),
    );

    // The name goes on the SLIDER's own node, and the visible Texts are
    // excluded from the tree.
    //
    // The previous form put a plain `Semantics(label:)` around the whole
    // row. That node sits ABOVE the Slider's node, so the SeekBar —
    // the node TalkBack focuses and the one that owns increase/decrease
    // — was handed no name at all and announced a bare «۰», while the
    // row node concatenated the visible label Text on top of its own
    // label and said the parameter twice: «روشنایی روشنایی ۰».
    //
    // This is the shared row behind every adjustment slider in the
    // editor (Look's five fine-tune rows, vignette, border width,
    // shadow, mask feather, text, shape, export), so fixing it here is
    // the fix — `layer_opacity_control` carries the same shape for its
    // bespoke slider and was, for one round, the only place it worked.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        children: [
          if (label != null)
            SizedBox(
              width: widget.labelWidth,
              child: ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      widget.labelStyle ??
                      TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.textSecondary,
                      ),
                ),
              ),
            ),
          Expanded(
            child: MergeSemantics(
              child: Semantics(
                label: widget.semanticLabel ?? label,
                child: slider,
              ),
            ),
          ),
          if (widget.showReadout)
            SizedBox(
              width: widget.readoutWidth,
              // Numeric readouts render LTR. A unit like `٪` or `px`
              // is a bidi-neutral / Latin run beside Persian digits
              // (class AN), so the paragraph direction decides which
              // side it lands on — and that made the SAME formatter
              // paint «٪۱۶» in the app bar and «۱۰۰٪» in the dock.
              // Pinning the direction at the widget (rather than
              // wrapping the string in LRI/PDI) also avoids the
              // font-fallback digit-drop those codepoints cause: no
              // bundled family, Vazir included, has glyphs for them.
              // Excluded: the same number is already the slider
              // node's `value`, so leaving it in the tree made the
              // row read the figure a second time.
              child: ExcludeSemantics(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    widget.format(widget.value),
                    textAlign: TextAlign.end,
                    style:
                        widget.readoutStyle ??
                        TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Track that fills from a fixed [origin] (0..1 of the track's span)
/// to the thumb, and paints a hairline tick at the origin.
///
/// Written against the parent-data the framework hands every track
/// shape, so it inherits RTL handling: [textDirection] tells us which
/// physical end `min` sits at, and the origin is mirrored with it.
class _OriginTrackShape extends RoundedRectSliderTrackShape {
  const _OriginTrackShape({required this.origin});

  /// Normalized position of the neutral value along min→max.
  final double origin;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;

    final active = sliderTheme.activeTrackColor ?? const Color(0xFF000000);
    final inactive = sliderTheme.inactiveTrackColor ?? const Color(0x33000000);
    final radius = Radius.circular(rect.height / 2);

    // Whole track in the inactive tone first; the filled span is then
    // drawn over it, so the two never disagree about the rounding.
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = inactive,
    );

    final originX = textDirection == TextDirection.rtl
        ? rect.right - origin * rect.width
        : rect.left + origin * rect.width;
    final from = math.min(originX, thumbCenter.dx);
    final to = math.max(originX, thumbCenter.dx);
    if (to - from > 0.5) {
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(from, rect.top, to, rect.bottom),
          radius,
        ),
        Paint()..color = active,
      );
    }

    // Origin tick: the "no change" landmark. Drawn last so it stays
    // legible whichever side the fill is on.
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(originX - 1, rect.top - 2, originX + 1, rect.bottom + 2),
        const Radius.circular(1),
      ),
      Paint()..color = active.withValues(alpha: 0.55),
    );
  }
}
