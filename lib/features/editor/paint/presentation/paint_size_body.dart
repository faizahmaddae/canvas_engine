import 'package:flutter/material.dart';

import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../presentation/widgets/section_label.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';

/// Shared Paint Size UI rendered in BOTH the inline dock panel and
/// the floating-toolbar modal sheet. One source of truth so a
/// "Thick" stroke means the same thing in both surfaces and any
/// future tweak lands once.
///
/// The widget is intentionally source-agnostic: it takes the
/// current [value], [color], and [dashPattern] explicitly and
/// pushes commits through [onChange]. The caller decides whether
/// those values come from the session defaults or from a selected
/// `PaintLayer`. Undo, selected-layer mirroring, and coalescing
/// (`UpdatePaintStyleCommand.mergeWith`) all live behind
/// `setStrokeWidth` in the controller, so this widget can stay
/// purely visual.
class PaintSizeBody extends StatelessWidget {
  const PaintSizeBody({
    super.key,
    required this.value,
    required this.color,
    required this.dashPattern,
    required this.onChange,
  });

  final double value;
  final Color color;
  final List<double>? dashPattern;
  final ValueChanged<double> onChange;

  // Same four plain-language stroke weights the inline and modal
  // surfaces both surface. Numeric chip-grids are gone — the
  // precision slider covers anything in between.
  static const List<double> _presets = [3, 8, 18, 36];
  static const double _epsilon = 0.01;

  String _presetLabel(BuildContext context, int index) {
    return switch (index) {
      0 => context.l10n.thinOption,
      1 => context.l10n.mediumOption,
      2 => context.l10n.thickOption,
      3 => context.l10n.heavyOption,
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        SectionLabel(
          context.l10n.sizeTool,
          uppercase: true,
          letterSpacing: 0.8,
        ),
        StrokeHero(width: value, color: color, dashPattern: dashPattern),
        const SizedBox(height: 12),
        SectionLabel(
          context.l10n.strokeWidthLabel,
          uppercase: true,
          letterSpacing: 0.8,
        ),
        // Horizontal scroller mirrors the chip row used by every
        // other Paint preset surface (Polygon, Dash) so chips read
        // as "the same control" across the editor.
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => PresetChip(
              label: _presetLabel(context, i),
              selected: (value - _presets[i]).abs() < _epsilon,
              // Chip tap = instant commit. PresetChip emits the
              // selection haptic itself.
              onTap: () => onChange(_presets[i]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _PaintSizePrecisionAdvanced(
          value: value,
          min: 1,
          max: 80,
          onChange: onChange,
        ),
      ],
    );
  }
}


/// Single horizontal brush stroke painted live in the user's
/// current colour, dash, and stroke width. Bigger and more honest
/// than a tiny "leading dot" — instant proof of what the next
/// stroke will look like before any commit.
class StrokeHero extends StatelessWidget {
  const StrokeHero({
    super.key,
    required this.width,
    required this.color,
    required this.dashPattern,
  });

  final double width;
  final Color color;
  final List<double>? dashPattern;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: 72,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: CustomPaint(
        painter: _StrokeHeroPainter(
          width: width,
          color: color,
          dashPattern: dashPattern,
        ),
      ),
    );
  }
}

class _StrokeHeroPainter extends CustomPainter {
  _StrokeHeroPainter({
    required this.width,
    required this.color,
    required this.dashPattern,
  });

  final double width;
  final Color color;
  final List<double>? dashPattern;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width.clamp(1.0, 56.0).toDouble()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    if (dashPattern == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    var x = 0.0;
    var i = 0;
    var draw = true;
    while (x < size.width) {
      final seg = dashPattern![i % dashPattern!.length];
      final end = (x + seg).clamp(0.0, size.width).toDouble();
      if (draw) {
        canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      }
      x = end;
      draw = !draw;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _StrokeHeroPainter old) =>
      old.width != width ||
      old.color != color ||
      !_listEq(old.dashPattern, dashPattern);

  static bool _listEq(List<double>? a, List<double>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Flat single-level disclosure that hides the precision slider by
/// default. Mirrors the Text Size panel's `_SizePrecisionAdvanced`
/// in shape and feel. Live mutation streams through `onChange` on
/// every tick — the per-call `UpdatePaintStyleCommand.mergeWith`
/// coalesces a whole drag to one undo entry, so the user gets live
/// canvas feedback AND a single undo step. `Listener.onPointerCancel`
/// guarantees a final commit even if the gesture is canceled by the
/// system or the sheet is dismissed mid-drag.
class _PaintSizePrecisionAdvanced extends StatefulWidget {
  const _PaintSizePrecisionAdvanced({
    required this.value,
    required this.min,
    required this.max,
    required this.onChange,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChange;

  @override
  State<_PaintSizePrecisionAdvanced> createState() =>
      _PaintSizePrecisionAdvancedState();
}

class _PaintSizePrecisionAdvancedState
    extends State<_PaintSizePrecisionAdvanced> {
  bool _open = false;
  bool _dragInFlight = false;
  double? _lastTickValue;

  String _format(double v) => '${v.round()}px';

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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final clampedValue = widget.value.clamp(widget.min, widget.max).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              EditorHaptics.tap();
              setState(() => _open = !_open);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _open
                          ? context.l10n.hidePreciseControls
                          : context.l10n.adjustPrecisely,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    _format(clampedValue),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _open ? scheme.primary : muted,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _open ? scheme.primary : muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
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
                        },
                        onChanged: (v) {
                          widget.onChange(
                            v.clamp(widget.min, widget.max).toDouble(),
                          );
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
