// Extracted verbatim from paint_mode_toolbar.dart (tb1 4/17); behaviour-preserving.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/editor_value_format.dart';
import '../../../../../l10n/l10n.dart';
import '../../../presentation/widgets/section_label.dart';
import '../../../toolbar/presentation/widgets/preset_chip.dart';
import '../../application/paint_tool_controller.dart';

class PaintPolygonBody extends ConsumerWidget {
  const PaintPolygonBody({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(paintToolControllerProvider.notifier);
    final style = ref.watch(paintStyleViewProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        _PolygonHero(
          sides: value,
          strokeColor: style.strokeColor,
          fillColor: style.fillColor,
        ),
        const SizedBox(height: 12),
        SectionLabel(
          context.l10n.polygonSidesLabel,
          uppercase: false,
          letterSpacing: 0,
        ),
        // Horizontal scroll mirrors the chip strip used by every
        // other preset surface in the editor (paint Size/Blur,
        // text sliders) — single layout grammar across modes.
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: 8,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              const sides = <int>[3, 4, 5, 6, 7, 8, 10, 12];
              final n = sides[i];
              return PresetChip(
                label: EditorValueFormat.of(context).digits(n),
                selected: n == value,
                onTap: () => ctrl.setPolygonSides(n),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PolygonHero extends StatelessWidget {
  const _PolygonHero({
    required this.sides,
    required this.strokeColor,
    required this.fillColor,
  });

  final int sides;
  final Color strokeColor;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderStrong),
      ),
      padding: const EdgeInsets.all(12),
      child: CustomPaint(
        painter: _PolygonHeroPainter(
          sides: sides,
          strokeColor: strokeColor,
          fillColor: fillColor,
        ),
      ),
    );
  }
}

class _PolygonHeroPainter extends CustomPainter {
  const _PolygonHeroPainter({
    required this.sides,
    required this.strokeColor,
    required this.fillColor,
  });

  final int sides;
  final Color strokeColor;
  final Color? fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final count = sides.clamp(3, 24);
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.42;
    final path = Path();
    for (var index = 0; index < count; index++) {
      final angle = -math.pi / 2 + (math.pi * 2 * index) / count;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    final fill = fillColor;
    if (fill != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PolygonHeroPainter oldDelegate) =>
      oldDelegate.sides != sides ||
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.fillColor != fillColor;
}
