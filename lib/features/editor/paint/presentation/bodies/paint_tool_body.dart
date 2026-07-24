// Extracted verbatim from paint_mode_toolbar.dart (tb1 4/17); behaviour-preserving.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../l10n/l10n.dart';
import '../../application/paint_tool_controller.dart';
import '../../domain/paint_tool_type.dart';

String? paintToolLabel(AppLocalizations l10n, PaintToolType? tool) {
  return switch (tool) {
    null => null,
    PaintToolType.freestyle => l10n.penTool,
    PaintToolType.line => l10n.lineTool,
    PaintToolType.arrow => l10n.arrowTool,
    PaintToolType.dashLine => l10n.dashedOption,
    PaintToolType.dashDotLine => l10n.dashDotOption,
    PaintToolType.rectangle => l10n.squareLabel,
    PaintToolType.circle => l10n.circleLabel,
    PaintToolType.hexagon => l10n.hexagonLabel,
    PaintToolType.polygon => l10n.polygonLabel,
    PaintToolType.eraser => l10n.eraserTool,
    PaintToolType.blur => l10n.blurLabel,
  };
}

String _paintGroupLabel(AppLocalizations l10n, _ToolGroup group) {
  return switch (group.title) {
    'Draw' => l10n.drawGroup,
    'Shapes' => l10n.shapesGroup,
    'Effects' => l10n.effectsGroup,
    _ => group.title,
  };
}

/// Compact chooser of every paint tool, organised into three
/// human-readable groups (Draw / Shapes / Effects). Picking a tool
/// calls `selectTool` which arms the canvas and immediately
/// collapses the sheet (controller clears `openSlot`).
///
/// Each tile renders a **live mini-preview** of the tool's stroke
/// in the user's current paint colour, so the picker reads as a
/// visual catalogue, not a row of generic icons.
class PaintToolBody extends ConsumerWidget {
  const PaintToolBody({super.key});

  // ─── Group definitions ──────────────────────────────────────
  // Order is the catalogue order. Friendly labels override the
  // technical enum labels so non-designers don't see jargon like
  // "Dash-dot" / "Polygon".
  static const List<_ToolGroup> _groups = <_ToolGroup>[
    _ToolGroup(
      title: 'Draw',
      tools: [
        (PaintToolType.freestyle, 'Pen'),
        (PaintToolType.line, 'Line'),
        (PaintToolType.arrow, 'Arrow'),
        (PaintToolType.dashLine, 'Dashed'),
        (PaintToolType.dashDotLine, 'Dash dot'),
        (PaintToolType.eraser, 'Eraser'),
      ],
    ),
    _ToolGroup(
      title: 'Shapes',
      tools: [
        (PaintToolType.rectangle, 'Square'),
        (PaintToolType.circle, 'Circle'),
        (PaintToolType.hexagon, 'Hexagon'),
        (PaintToolType.polygon, 'Polygon'),
      ],
    ),
    _ToolGroup(title: 'Effects', tools: [(PaintToolType.blur, 'Blur')]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 360 ? 5 : 4;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < _groups.length; g++) ...[
          if (g > 0) const SizedBox(height: 14),
          _GroupHeader(title: _paintGroupLabel(context.l10n, _groups[g])),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.92,
            padding: EdgeInsets.zero,
            children: [
              for (final (tool, label) in _groups[g].tools)
                _PaintToolGridTile(
                  tool: tool,
                  label: paintToolLabel(context.l10n, tool) ?? label,
                  paintColor: session.strokeColor,
                  selected: session.activeTool == tool,
                  onTap: tool.available
                      ? () {
                          EditorHaptics.tap();
                          ctrl.selectTool(tool);
                        }
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ToolGroup {
  const _ToolGroup({required this.title, required this.tools});
  final String title;
  final List<(PaintToolType, String)> tools;
}

/// Section label above each tool group. Aligned with Text's
/// `_PanelSectionLabel` (11sp, w700, letterSpacing 0.8, muted) for
/// a single editor-wide section-heading style. Caller still owns
/// outer spacing (this builder leaves the parent's vertical gaps
/// untouched and only adds a hairline left inset to match the
/// tool-grid alignment).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppTokens.of(context).textSecondary,
        ),
      ),
    );
  }
}

class _PaintToolGridTile extends StatelessWidget {
  const _PaintToolGridTile({
    required this.tool,
    required this.label,
    required this.paintColor,
    required this.selected,
    required this.onTap,
  });

  final PaintToolType tool;
  final String label;
  final Color paintColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final theme = Theme.of(context);
    final enabled = onTap != null;

    final bgColor = selected
        ? tokens.accent.withValues(alpha: 0.14)
        : tokens.surfaceMuted.withValues(alpha: 0.40);
    final borderColor = selected
        ? tokens.accent.withValues(alpha: 0.85)
        : tokens.border.withValues(alpha: 0.35);
    final labelColor = !enabled
        ? tokens.textPrimary.withValues(alpha: 0.32)
        : selected
        ? tokens.accent
        : tokens.textPrimary.withValues(alpha: 0.88);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: 0.20),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 38,
                height: 26,
                child: CustomPaint(
                  painter: _ToolPreviewPainter(
                    tool: tool,
                    color: enabled
                        ? paintColor
                        : tokens.textPrimary.withValues(alpha: 0.25),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 10.5,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a 1:1 mini-preview of each paint tool's stroke / shape
/// using the user's current paint colour. Faster than memorising
/// abstract icons \u2014 the user sees what the tool will draw.
class _ToolPreviewPainter extends CustomPainter {
  _ToolPreviewPainter({required this.tool, required this.color});

  final PaintToolType tool;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    final cy = h / 2;

    switch (tool) {
      case PaintToolType.freestyle:
        // Hand-drawn squiggle.
        final path = Path()
          ..moveTo(2, cy + 4)
          ..cubicTo(w * 0.25, cy - 8, w * 0.45, cy + 8, w * 0.6, cy)
          ..cubicTo(w * 0.75, cy - 8, w * 0.9, cy + 6, w - 2, cy - 2);
        canvas.drawPath(path, stroke);
        break;
      case PaintToolType.line:
        canvas.drawLine(Offset(2, cy), Offset(w - 2, cy), stroke);
        break;
      case PaintToolType.arrow:
        canvas.drawLine(Offset(2, cy), Offset(w - 6, cy), stroke);
        final head = Path()
          ..moveTo(w - 2, cy)
          ..lineTo(w - 9, cy - 4)
          ..moveTo(w - 2, cy)
          ..lineTo(w - 9, cy + 4);
        canvas.drawPath(head, stroke);
        break;
      case PaintToolType.dashLine:
        _dashes(canvas, stroke, w, cy, dashOn: 5, dashOff: 3);
        break;
      case PaintToolType.dashDotLine:
        _dashDot(canvas, stroke, w, cy);
        break;
      case PaintToolType.eraser:
        // Tilted rounded eraser block.
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, cy), width: 18, height: 12),
          const Radius.circular(2.5),
        );
        canvas.save();
        canvas.translate(w / 2, cy);
        canvas.rotate(-0.35);
        canvas.translate(-w / 2, -cy);
        canvas.drawRRect(r, stroke);
        canvas.restore();
        break;
      case PaintToolType.rectangle:
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w / 2, cy), width: 22, height: 14),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(r, stroke);
        break;
      case PaintToolType.circle:
        canvas.drawCircle(Offset(w / 2, cy), 9, stroke);
        break;
      case PaintToolType.hexagon:
        canvas.drawPath(_polygonPath(w / 2, cy, 10, 6), stroke);
        break;
      case PaintToolType.polygon:
        canvas.drawPath(_polygonPath(w / 2, cy, 10, 5), stroke);
        break;
      case PaintToolType.blur:
        // Soft blur halo: stacked translucent circles.
        final halo = Paint()
          ..color = color.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(Offset(w / 2, cy), 9, halo);
        canvas.drawCircle(Offset(w / 2, cy), 6, stroke);
        break;
    }
  }

  void _dashes(
    Canvas c,
    Paint p,
    double w,
    double y, {
    required double dashOn,
    required double dashOff,
  }) {
    var x = 2.0;
    while (x < w - 2) {
      final end = (x + dashOn).clamp(0.0, w - 2).toDouble();
      c.drawLine(Offset(x, y), Offset(end, y), p);
      x = end + dashOff;
    }
  }

  void _dashDot(Canvas c, Paint p, double w, double y) {
    var x = 2.0;
    var i = 0;
    while (x < w - 2) {
      if (i.isEven) {
        final end = (x + 5).clamp(0.0, w - 2).toDouble();
        c.drawLine(Offset(x, y), Offset(end, y), p);
        x = end + 3;
      } else {
        c.drawCircle(Offset(x + 1, y), 1.1, Paint()..color = p.color);
        x += 5;
      }
      i++;
    }
  }

  Path _polygonPath(double cx, double cy, double r, int sides) {
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i) / sides;
      final x = cx + r * 0.95 * math.cos(angle);
      final y = cy + r * 0.95 * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _ToolPreviewPainter old) =>
      old.tool != tool || old.color != color;
}
