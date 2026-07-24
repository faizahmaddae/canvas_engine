import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../presentation/widgets/section_label.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import '../../../../core/utils/editor_value_format.dart';

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
/// the live overlay and commit ONE command per drag). Preset chips
/// fire `onChange(value)` immediately followed by `onChangeEnd()`,
/// so a tap is a single discrete commit (§3); the precision
/// slider's [onChangeEnd] also fires on pointer-cancel so an
/// interrupted drag still commits what the user saw (§7).
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
        StrokeHero(width: value, color: color),
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
              // Chip tap = one discrete commit: preview the value
              // and seal it in the same tap (§3). PresetChip emits
              // the selection haptic itself.
              onTap: () {
                onChange(_presets[i]);
                onChangeEnd?.call();
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        _PaintSizePrecisionAdvanced(
          value: value,
          min: 1,
          max: 80,
          onChange: onChange,
          onChangeEnd: onChangeEnd,
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
      height: 72,
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tokens.border.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
    final paint = Paint()
      ..color = color
      ..strokeWidth = width.clamp(1.0, 56.0).toDouble()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _StrokeHeroPainter old) =>
      old.width != width || old.color != color;
}

/// Flat single-level disclosure that hides the precision slider by
/// default. Mirrors the Text Size panel's `_SizePrecisionAdvanced`
/// in shape and feel. Ticks stream through `onChange` (the host
/// stages them as overlay previews per contract §2) and the drag
/// seals through `onChangeEnd` — fired on release AND on
/// pointer-cancel (`Listener.onPointerCancel`), so an interrupted
/// drag still commits the last previewed value (§7).
class _PaintSizePrecisionAdvanced extends StatefulWidget {
  const _PaintSizePrecisionAdvanced({
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
  State<_PaintSizePrecisionAdvanced> createState() =>
      _PaintSizePrecisionAdvancedState();
}

class _PaintSizePrecisionAdvancedState
    extends State<_PaintSizePrecisionAdvanced> {
  bool _open = false;
  bool _dragInFlight = false;
  double? _lastTickValue;

  String _format(double v) => EditorValueFormat.of(context).px(v.round());

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
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final muted = tokens.textSecondary;
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
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    _format(clampedValue),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _open ? tokens.accent : muted,
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
                      color: _open ? tokens.accent : muted,
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
