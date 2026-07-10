import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';

/// Continuous 2D offset pad — drag the dot to set direction AND
/// distance in one gesture. Replaces the discrete 3×3
/// `PanelDirectionPad` + separate distance slider pairing on the
/// text Shadow section: one control, one write path
/// (`onChanged(Offset)`), half the vertical space.
///
/// Geometry is **physical**: the emitted offset is screen-space
/// (positive dx = right, positive dy = down) regardless of ambient
/// RTL, matching how the shadow offset is stored and rendered.
/// Gesture-local coordinates are already physical, so no
/// `Directionality` pinning is needed — but keep the painted chrome
/// symmetric so nothing *reads* as mirrored either.
class PanelOffsetPad extends StatefulWidget {
  const PanelOffsetPad({
    super.key,
    required this.offset,
    required this.maxDistance,
    required this.onChanged,
    this.onDragStart,
    this.onDragEnd,
    this.size = 104,
    this.semanticLabel,
  });

  /// Current offset in style units (px against the canvas).
  final Offset offset;

  /// Style-unit distance mapped to the pad's edge. Dragging the dot
  /// to the rim writes an offset of this magnitude.
  final double maxDistance;

  final ValueChanged<Offset> onChanged;

  /// Drag-transaction hooks — callers wrap the whole gesture in a
  /// `beginStyleDrag`/`endStyleDrag` window so a full drag lands as
  /// one undo entry (same contract as [EditorSliderRow]).
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// Square edge length in dp.
  final double size;

  final String? semanticLabel;

  @override
  State<PanelOffsetPad> createState() => _PanelOffsetPadState();
}

class _PanelOffsetPadState extends State<PanelOffsetPad> {
  bool _dragInFlight = false;

  static const double _dotRadius = 8;
  static const double _edgeInset = 6;

  /// Radius (in dp from the pad centre) the dot may travel.
  double get _travel => widget.size / 2 - _dotRadius - _edgeInset;

  /// Dead zone: releasing the dot very near the centre snaps to a
  /// clean zero offset so "no offset" is reachable without pixel
  /// hunting.
  static const double _snapFraction = 0.07;

  Offset _toLocalDot(Offset styleOffset) {
    if (widget.maxDistance <= 0) return Offset.zero;
    final scaled = styleOffset / widget.maxDistance * _travel;
    return scaled.distance <= _travel
        ? scaled
        : scaled / scaled.distance * _travel;
  }

  void _write(Offset localFromCenter) {
    var v = localFromCenter;
    if (v.distance > _travel) v = v / v.distance * _travel;
    var next = v / _travel * widget.maxDistance;
    if (next.distance < widget.maxDistance * _snapFraction) {
      next = Offset.zero;
    }
    widget.onChanged(next);
  }

  void _start(Offset localPos) {
    _dragInFlight = true;
    EditorHaptics.toggle();
    widget.onDragStart?.call();
    _write(localPos - Offset(widget.size / 2, widget.size / 2));
  }

  void _end() {
    if (!_dragInFlight) return;
    _dragInFlight = false;
    EditorHaptics.confirm();
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final dot = _toLocalDot(widget.offset);
    final center = widget.size / 2;
    return Semantics(
      label: widget.semanticLabel,
      container: true,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          // Joystick semantics: touching the pad IS using it, so the
          // recognizer claims the pointer on contact instead of
          // waiting out the slop. Without this the sheet's sibling
          // horizontal-swipe (slop 18) reliably steals diagonal
          // drags from a plain pan recognizer (slop 36).
          _ImmediatePanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _ImmediatePanGestureRecognizer
              >(_ImmediatePanGestureRecognizer.new, (r) {
                r.onStart = (d) => _start(d.localPosition);
                r.onUpdate = (d) {
                  _write(d.localPosition - Offset(center, center));
                };
                r.onEnd = (_) => _end();
                r.onCancel = _end;
              }),
        },
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surfaceMuted.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.border.withValues(alpha: 0.4)),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size.square(widget.size),
                  painter: _PadGuidesPainter(
                    color: tokens.border.withValues(alpha: 0.45),
                  ),
                ),
                Positioned(
                  left: center + dot.dx - _dotRadius,
                  top: center + dot.dy - _dotRadius,
                  child: Container(
                    width: _dotRadius * 2,
                    height: _dotRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.accent,
                      border: Border.all(color: tokens.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pan recognizer that wins the gesture arena on pointer-down.
class _ImmediatePanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Crosshair guides + centre ring so the zero point reads at a
/// glance while dragging.
class _PadGuidesPainter extends CustomPainter {
  const _PadGuidesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final c = size.center(Offset.zero);
    canvas.drawLine(Offset(c.dx, 8), Offset(c.dx, size.height - 8), paint);
    canvas.drawLine(Offset(8, c.dy), Offset(size.width - 8, c.dy), paint);
    canvas.drawCircle(c, 3, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_PadGuidesPainter old) => old.color != color;
}
