import 'package:flutter/material.dart';

import '../../../../core/utils/editor_value_format.dart';
import '../../../../l10n/l10n.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../toolbar/presentation/widgets/preset_slider_control.dart';

/// The Paint Size body, rendered in the inline dock panel. (Its
/// second host — the floating-toolbar modal sheet — died with
/// PaintFloatingToolbar when the unified quick capsule replaced the
/// per-type floating bars; the capsule's Size pill routes back to
/// this same dock slot.)
///
/// The widget is intentionally source-agnostic: it takes the
/// current [value] and [color] explicitly and streams ticks through
/// [onPreview] with [onCommit] sealing the gesture (contract §2: the
/// paint hosts stage previews on the live overlay and commit ONE
/// command per drag). The caller decides whether those values come
/// from the session defaults or from a selected `PaintLayer`.
///
/// Body layout: [StrokeHero] previews the actual stroke — genuinely
/// useful here and unique to Size, so it stays above the control —
/// and [PresetSliderControl] handles presets + fine adjustment the
/// same way every other numeric paint tool (Blur, Opacity) already
/// does: a live readout in its own header, preset chips, and the
/// slider always in view rather than behind a disclosure tap. Size
/// used to hand-roll its own version of all three (a floating badge,
/// a reflowing weight grid, a slider hidden behind "Adjust
/// precisely") — the one paint numeric control not on the shared
/// control, and the extra tap to reach the slider was friction for
/// what is usually the more direct way to pick a width.
class PaintSizeBody extends StatelessWidget {
  const PaintSizeBody({
    super.key,
    required this.value,
    required this.color,
    required this.onPreview,
    required this.onCommit,
  });

  final double value;
  final Color color;
  final ValueChanged<double> onPreview;
  final ValueChanged<double> onCommit;

  // Same four plain-language stroke weights the inline and modal
  // surfaces both surfaced before this redesign.
  static const List<double> _presets = [3, 8, 18, 36];

  static const double _min = 1;
  static const double _max = 80;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StrokeHero(width: value, color: color),
        const SizedBox(height: 14),
        PresetSliderControl(
          value: value,
          min: _min,
          max: _max,
          presets: _presets,
          presetLabels: [
            l10n.thinOption,
            l10n.mediumOption,
            l10n.thickOption,
            l10n.heavyOption,
          ],
          formatValue: (v) => EditorValueFormat.of(context).px(v.round()),
          onPreview: onPreview,
          onCommit: onCommit,
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
