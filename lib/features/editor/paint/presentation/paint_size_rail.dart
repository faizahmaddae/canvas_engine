import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../application/paint_tool_controller.dart';
import '../domain/paint_bench_slot.dart';
import '../domain/paint_tool_type.dart';

/// Canvas-side stroke-width rail (`docs/paint-redesign-2026-08.md`
/// §2) — the standard drawing-app side slider: drag up for a thicker
/// stroke, live against the §2 width preview channel, ONE commit on
/// release. Visible only while an inking tool is armed (pen / line /
/// arrow / shape); blur and the eraser have no stroke width, and the
/// adjust posture already has the bench's size pill for the bound
/// stroke.
///
/// It is floating chrome layered above the paint gesture surface and
/// owns its own pointers — a drag on the rail never reaches the
/// canvas. Placement lives in [PaintSizeRailHost].
class PaintSizeRail extends ConsumerStatefulWidget {
  const PaintSizeRail({super.key});

  /// Width range the rail spans — the same 1..80 the pen sheet's
  /// size slider uses, so the two surfaces can never disagree.
  static const double min = 1;
  static const double max = 80;

  /// Whether the rail should exist for [tool].
  static bool visibleFor(PaintToolType? tool) {
    if (tool == null) return false;
    return switch (benchSlotForTool(tool)) {
      PaintBenchSlot.pen ||
      PaintBenchSlot.line ||
      PaintBenchSlot.arrow ||
      PaintBenchSlot.shape => true,
      _ => false,
    };
  }

  @override
  ConsumerState<PaintSizeRail> createState() => _PaintSizeRailState();
}

class _PaintSizeRailState extends ConsumerState<PaintSizeRail> {
  /// In-flight drag value; null when idle (render the style view).
  double? _dragValue;

  static const double _trackHeight = 180;
  static const double _thumbMax = 22;

  double get _range => PaintSizeRail.max - PaintSizeRail.min;

  void _onDragStart(DragStartDetails details) {
    EditorHaptics.toggle();
    setState(() => _dragValue = ref.read(paintStyleViewProvider).strokeWidth);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final current = _dragValue;
    if (current == null) return;
    // Up = thicker. The full track maps the full range.
    final next = (current - details.delta.dy * (_range / _trackHeight)).clamp(
      PaintSizeRail.min,
      PaintSizeRail.max,
    );
    setState(() => _dragValue = next);
    ref.read(paintToolControllerProvider.notifier).previewStrokeWidth(next);
  }

  void _onDragEnd() {
    final v = _dragValue;
    if (v == null) return;
    setState(() => _dragValue = null);
    EditorHaptics.confirm();
    ref.read(paintToolControllerProvider.notifier).commitStrokeWidth(v);
  }

  @override
  Widget build(BuildContext context) {
    final tool = ref.watch(
      paintToolControllerProvider.select((s) => s.activeTool),
    );
    if (!PaintSizeRail.visibleFor(tool)) return const SizedBox.shrink();
    final view = ref.watch(paintStyleViewProvider);
    final tokens = AppTokens.of(context);
    final value = (_dragValue ?? view.strokeWidth).clamp(
      PaintSizeRail.min,
      PaintSizeRail.max,
    );
    final t = (value - PaintSizeRail.min) / _range;
    final dragging = _dragValue != null;
    // Thumb grows with the value — the rail reads as state even
    // without the bubble.
    final thumb = 8 + t * (_thumbMax - 8);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      slider: true,
      label: context.l10n.strokeSizeSemantics,
      value: EditorValueFormat.of(context).px(value.round()),
      child: GestureDetector(
        key: const ValueKey('paint-size-rail'),
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: (_) => _onDragEnd(),
        onVerticalDragCancel: _onDragEnd,
        child: SizedBox(
          // 44dp-wide hit halo around a 28dp painted rail.
          width: 44,
          height: _trackHeight + 24,
          child: Center(
            child: Container(
              width: 28,
              height: _trackHeight + 16,
              decoration: BoxDecoration(
                color: tokens.surface.withValues(alpha: dragging ? 1 : 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tokens.border.withValues(alpha: 0.9)),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: isDark ? 0.4 : 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: CustomPaint(
                painter: _RailPainter(
                  t: t,
                  thumb: thumb,
                  ink: view.strokeColor.withValues(alpha: 1),
                  track: tokens.border,
                  bubbleText: dragging
                      ? EditorValueFormat.of(context).px(value.round())
                      : null,
                  bubbleBg: tokens.textPrimary,
                  bubbleFg: tokens.surface,
                  textDirection: Directionality.of(context),
                  textStyle: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the rail: a tapered track (thin at the bottom, wide at the
/// top — the universal "size" glyph), the ink-coloured thumb at the
/// current value, and the drag bubble beside it.
class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.t,
    required this.thumb,
    required this.ink,
    required this.track,
    required this.bubbleText,
    required this.bubbleBg,
    required this.bubbleFg,
    required this.textDirection,
    required this.textStyle,
  });

  final double t;
  final double thumb;
  final Color ink;
  final Color track;
  final String? bubbleText;
  final Color bubbleBg;
  final Color bubbleFg;
  final TextDirection textDirection;
  final TextStyle? textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 14.0;
    final cx = size.width / 2;
    final top = Offset(cx, inset);
    final bottom = Offset(cx, size.height - inset);
    // Tapered track: two straight edges from a 1px foot to a 5px
    // head, filled — reads "thin → thick" at a glance.
    final path = Path()
      ..moveTo(top.dx - 2.5, top.dy)
      ..lineTo(top.dx + 2.5, top.dy)
      ..lineTo(bottom.dx + 0.5, bottom.dy)
      ..lineTo(bottom.dx - 0.5, bottom.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = track.withValues(alpha: 0.9));

    final y = bottom.dy + (top.dy - bottom.dy) * t;
    final thumbCenter = Offset(cx, y);
    canvas.drawCircle(
      thumbCenter,
      thumb / 2 + 2,
      Paint()..color = bubbleFg.withValues(alpha: 0.9),
    );
    canvas.drawCircle(thumbCenter, thumb / 2, Paint()..color = ink);

    final text = bubbleText;
    if (text == null) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: (textStyle ?? const TextStyle(fontSize: 11)).copyWith(
          color: bubbleFg,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    // Bubble floats past the rail's edge, above the finger. It may
    // paint outside this painter's bounds — the rail widget is not
    // clipped, which is deliberate.
    final bubbleW = tp.width + 14;
    const bubbleH = 24.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, y - thumb / 2 - bubbleH),
        width: bubbleW,
        height: bubbleH,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = bubbleBg);
    tp.paint(canvas, rect.center.translate(-tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.t != t ||
      old.thumb != thumb ||
      old.ink != ink ||
      old.bubbleText != bubbleText;
}

/// Positions the rail, vertically centred over the canvas body, on
/// the PHYSICAL left — the non-drawing side for the right-handed
/// majority and Procreate's own default. Deliberately not
/// directional (RTL must not flip a hand), and deliberately not yet
/// keyed to `rightHandedToolbar`: that setting aligns the dock for
/// the *drawing* thumb and carries no left-handed signal to mirror
/// from. A dedicated handedness control can move the rail later.
class PaintSizeRailHost extends StatelessWidget {
  const PaintSizeRailHost({super.key});

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: PaintSizeRail(),
      ),
    );
  }
}
