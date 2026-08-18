import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../app/theme/app_icons.dart';
import '../../ui/precision_disclosure.dart';

/// Shared Paint Size UI rendered in BOTH the inline dock panel and
/// the floating-toolbar modal sheet. One source of truth so a
/// "Thick" stroke means the same thing in both surfaces and any
/// future tweak lands once.
///
/// The widget is intentionally source-agnostic: it takes the
/// current [value] and [color] explicitly and streams ticks through
/// [onChange] with [onChangeEnd] marking the end of a gesture. The
/// caller decides whether those values come from the session
/// defaults or from a selected `PaintLayer`, and what "preview" vs
/// "commit" means (contract §2: the paint hosts stage previews on
/// the live overlay and commit ONE command per drag). Preset tiles
/// fire `onChange(value)` immediately followed by `onChangeEnd()`,
/// so a tap is a single discrete commit (§3); the precision
/// slider's [onChangeEnd] also fires on pointer-cancel so an
/// interrupted drag still commits what the user saw (§7).
///
/// Layout (tb8 — the Size panel was the weakest body in the dock):
/// the preview card carries its OWN px readout, so preview and
/// value read as one component instead of a hero floating above an
/// unrelated number; the four weights are an equal-width reflowing
/// grid rather than a horizontal scroller of organically sized
/// pills (a scroller hid "Heavy" off-screen at Persian text
/// scales); and the precision slider hides behind the shared
/// compact disclosure instead of a hand-rolled 44dp title row. The
/// panel's own "Stroke width" title is gone — the dock/sheet header
/// already says Size, and the body repeating it cost a whole line
/// for zero information.
class PaintSizeBody extends StatelessWidget {
  const PaintSizeBody({
    super.key,
    required this.value,
    required this.color,
    required this.onChange,
    this.onChangeEnd,
  });

  final double value;
  final Color color;
  final ValueChanged<double> onChange;
  final VoidCallback? onChangeEnd;

  /// Key on the readout badge inside the preview card — the one
  /// place the current width is spelled out.
  static const readoutKey = ValueKey('paint-size-readout');

  /// Key on the weight grid, so a test can measure the row without
  /// depending on how many columns it reflowed into.
  static const presetGridKey = ValueKey('paint-size-presets');

  // Same four plain-language stroke weights the inline and modal
  // surfaces both surface. Numeric chip-grids are gone — the
  // precision slider covers anything in between.
  static const List<double> _presets = [3, 8, 18, 36];
  static const double _epsilon = 0.01;

  static const double _min = 1;
  static const double _max = 80;

  String _presetLabel(BuildContext context, int index) {
    return switch (index) {
      0 => context.l10n.thinOption,
      1 => context.l10n.mediumOption,
      2 => context.l10n.thickOption,
      3 => context.l10n.heavyOption,
      _ => '',
    };
  }

  /// Index of the preset the current width sits on, or `null` when
  /// the user is between weights (a slider drag, or a width restored
  /// from an older document). `null` is what the "Custom" status
  /// exists to explain — an unlit preset row with no reason given
  /// reads as a broken control.
  int? _activePreset() {
    for (var i = 0; i < _presets.length; i++) {
      if ((value - _presets[i]).abs() < _epsilon) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activePreset();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 2),
        _StrokePreviewCard(
          value: value,
          color: color,
          statusLabel: active == null
              ? context.l10n.customLabel
              : _presetLabel(context, active),
          isCustom: active == null,
        ),
        const SizedBox(height: 10),
        _WeightGrid(
          key: presetGridKey,
          count: _presets.length,
          activeIndex: active,
          labelOf: (i) => _presetLabel(context, i),
          strokeOf: (i) => _presets[i],
          maxStroke: _presets.last,
          // Tile tap = one discrete commit: preview the value and
          // seal it in the same tap (§3). Option tiles keep
          // caller-owned haptics (PresetChip class doc).
          onPick: (i) {
            EditorHaptics.snap();
            onChange(_presets[i]);
            onChangeEnd?.call();
          },
        ),
        const SizedBox(height: 2),
        PrecisionDisclosure(
          compact: true,
          titleClosed: context.l10n.adjustPrecisely,
          titleOpen: context.l10n.hidePreciseControls,
          children: [
            _PaintSizeSlider(
              value: value,
              min: _min,
              max: _max,
              onChange: onChange,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      ],
    );
  }
}

/// The live stroke preview and its px readout as ONE component: the
/// badge sits inside the card's leading corner so the eye never has
/// to pair a picture with a number parked elsewhere in the panel.
class _StrokePreviewCard extends StatelessWidget {
  const _StrokePreviewCard({
    required this.value,
    required this.color,
    required this.statusLabel,
    required this.isCustom,
  });

  final double value;
  final Color color;

  /// Preset name, or the localized "Custom" when the width sits
  /// between weights. Spoken either way; only painted when custom.
  final String statusLabel;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final readout = EditorValueFormat.of(context).px(value.round());
    return Stack(
      children: [
        StrokeHero(width: value, color: color),
        PositionedDirectional(
          top: 6,
          start: 8,
          child: Semantics(
            container: true,
            label: '$readout · $statusLabel',
            child: ExcludeSemantics(
              child: Container(
                key: PaintSizeBody.readoutKey,
                padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 8, 3),
                decoration: BoxDecoration(
                  color: tokens.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tokens.borderStrong),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      readout,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                        letterSpacing: 0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (isCustom) ...[
                      const SizedBox(width: 5),
                      Text(
                        '· $statusLabel',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tokens.textSecondary,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Four equal-width weight tiles that REFLOW instead of scrolling.
///
/// The old row was a horizontal `ListView` of content-sized pills:
/// under Persian at large text scales "خیلی ضخیم" pushed the last
/// weight past the panel edge with nothing but a scroll affordance
/// to hint it existed. Columns are derived from the width the tile
/// labels actually need, so the row degrades to 3-2-1 columns
/// rather than off-screen.
class _WeightGrid extends StatelessWidget {
  const _WeightGrid({
    super.key,
    required this.count,
    required this.activeIndex,
    required this.labelOf,
    required this.strokeOf,
    required this.maxStroke,
    required this.onPick,
  });

  final int count;
  final int? activeIndex;
  final String Function(int) labelOf;
  final double Function(int) strokeOf;
  final double maxStroke;
  final ValueChanged<int> onPick;

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        // An 11sp tile label needs ~64dp of tile to stay whole over
        // two lines; every point of text scaling above that needs
        // proportionally more room before a column stops fitting.
        final scaled = MediaQuery.textScalerOf(context).scale(11);
        final minTile = 64.0 + (scaled - 11) * 2.2;
        var columns = count;
        while (columns > 1 &&
            (maxWidth - _gap * (columns - 1)) / columns < minTile) {
          columns--;
        }
        final tileWidth = (maxWidth - _gap * (columns - 1)) / columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (var i = 0; i < count; i++)
              PresetChip.option(
                label: labelOf(i),
                width: tileWidth,
                // Persian weight names are two words; one line would
                // ellipsize them into each other at any text scale
                // above 1.0.
                maxLabelLines: 2,
                selected: i == activeIndex,
                preview: _WeightGlyph(
                  stroke: strokeOf(i),
                  maxStroke: maxStroke,
                  selected: i == activeIndex,
                ),
                onTap: () => onPick(i),
              ),
          ],
        );
      },
    );
  }
}

/// Tile glyph: a bar drawn at the weight's relative thickness, with
/// a tick added when chosen. The tick is the non-colour selection
/// cue — fill and border alone leave the state invisible to anyone
/// who cannot separate the accent from the panel.
class _WeightGlyph extends StatelessWidget {
  const _WeightGlyph({
    required this.stroke,
    required this.maxStroke,
    required this.selected,
  });

  final double stroke;
  final double maxStroke;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected) ...[
          const Icon(AppIcons.confirm, size: 12),
          const SizedBox(width: 4),
        ],
        SizedBox(
          width: 22,
          height: 12,
          child: Builder(
            builder: (context) => CustomPaint(
              painter: _StrokeHeroPainter(
                // The glyph is a RELATIVE cue, not a measurement:
                // 36px drawn true-size would be taller than the tile.
                width: (stroke / maxStroke * 10).clamp(2.0, 10.0),
                // PresetChip paints the tile's foreground colour into
                // the glyph slot's IconTheme — selected/resting/
                // disabled all resolve there, so the bar never needs a
                // colour of its own.
                color:
                    IconTheme.of(context).color ??
                    AppTokens.of(context).textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Single horizontal brush stroke painted live in the user's
/// current colour and stroke width. Bigger and more honest than a
/// tiny "leading dot" — instant proof of what the next stroke will
/// look like before any commit.
///
/// 56dp tall (was 72): the panel needs the height for controls more
/// than the preview needs the air, and the stroke is clamped to the
/// card's inner height so an 80px width stays inside its own border
/// instead of painting over it.
///
/// The dash-pattern preview died with `PaintSession.dashPattern`
/// (tb2 3/16): nothing had written that field since its setter was
/// retired in tb1 6b, so the hero always rendered solid anyway —
/// actual dashing comes from the stroke's `PaintKind`.
class StrokeHero extends StatelessWidget {
  const StrokeHero({super.key, required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: CustomPaint(
        painter: _StrokeHeroPainter(width: width, color: color),
      ),
    );
  }
}

class _StrokeHeroPainter extends CustomPainter {
  _StrokeHeroPainter({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0 || size.width <= 0) return;
    final paint = Paint()
      ..color = color
      // Clamped to the box that actually exists: a round cap exactly
      // as thick as the inner height still lands inside the border,
      // and it keeps the line centred at every width.
      ..strokeWidth = width.clamp(1.0, size.height).toDouble()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _StrokeHeroPainter old) =>
      old.width != width || old.color != color;
}

/// The precision slider, inside a bounded secondary surface so the
/// expanded state reads as a drawer belonging to the Fine-tune row
/// rather than a control floating on the panel.
///
/// Ticks stream through `onChange` (the host stages them as overlay
/// previews per contract §2) and the drag seals through
/// `onChangeEnd` — fired on release AND on pointer-cancel
/// (`Listener.onPointerCancel`), so an interrupted drag still
/// commits the last previewed value (§7).
class _PaintSizeSlider extends StatefulWidget {
  const _PaintSizeSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChange,
    this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChange;
  final VoidCallback? onChangeEnd;

  @override
  State<_PaintSizeSlider> createState() => _PaintSizeSliderState();
}

class _PaintSizeSliderState extends State<_PaintSizeSlider> {
  bool _dragInFlight = false;
  double? _lastTickValue;

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
    widget.onChangeEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final clampedValue = widget.value.clamp(widget.min, widget.max).toDouble();
    final format = EditorValueFormat.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(2, 2, 2, 4),
      padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 6, 0),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: Listener(
          onPointerCancel: (_) => _endDrag(),
          child: Slider(
            value: clampedValue,
            min: widget.min,
            max: widget.max,
            // The spoken value has to match the badge, digits and
            // all — the readout itself is outside this subtree.
            semanticFormatterCallback: (v) => format.px(v.round()),
            onChangeStart: (v) {
              _dragInFlight = true;
              _lastTickValue = v;
              EditorHaptics.toggle();
            },
            onChanged: (v) {
              widget.onChange(v.clamp(widget.min, widget.max).toDouble());
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
    );
  }
}
