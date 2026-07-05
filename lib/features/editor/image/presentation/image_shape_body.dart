import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../presentation/widgets/panel_option_tile.dart';
import 'image_panel_shell.dart';

/// Expanded panel body for the Image sub-tool's "Shape" tab.
///
/// Six tiles map 1:1 to [ImageMask] values. Tapping a tile commits a
/// [SetImageMaskCommand] immediately so the change participates in
/// undo/redo. The image source, transform, fit and selection are
/// untouched — only the visible silhouette changes.
class ImageShapeBody extends ConsumerWidget {
  const ImageShapeBody({super.key, required this.layer});

  final ImageLayer layer;

  static const _options = <_ShapeOption>[
    _ShapeOption(mask: ImageMask.original, label: 'Original'),
    _ShapeOption(mask: ImageMask.rounded, label: 'Rounded'),
    _ShapeOption(mask: ImageMask.circle, label: 'Circle'),
    _ShapeOption(mask: ImageMask.squircle, label: 'Squircle'),
    _ShapeOption(mask: ImageMask.star, label: 'Star'),
    _ShapeOption(mask: ImageMask.heart, label: 'Heart'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ImagePanelShell(
      title: context.l10n.shapeTool,
      icon: Icons.crop_square_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header already says "Shape" — no duplicate SectionLabel.
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _options.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final option = _options[i];
                final selected = layer.mask == option.mask;
                return PanelOptionTile(
                  width: 76,
                  selected: selected,
                  label: _shapeOptionLabel(context, option),
                  preview: SizedBox(
                    height: 32,
                    width: 32,
                    child: Builder(
                      builder: (ctx) => CustomPaint(
                        painter: _MaskPreviewPainter(
                          mask: option.mask,
                          color:
                              IconTheme.of(ctx).color ??
                              AppTokens.of(ctx).textSecondary,
                        ),
                      ),
                    ),
                  ),
                  onTap: () {
                    if (layer.mask == option.mask) return;
                    EditorHaptics.toggle();
                    ref
                        .read(documentControllerProvider.notifier)
                        .execute(
                          SetImageMaskCommand(
                            layerId: layer.id,
                            mask: option.mask,
                          ),
                        );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ShapeOption {
  const _ShapeOption({required this.mask, required this.label});
  final ImageMask mask;
  final String label;
}

String _shapeOptionLabel(BuildContext context, _ShapeOption option) {
  return switch (option.mask) {
    ImageMask.original => context.l10n.originalOption,
    ImageMask.rounded => context.l10n.roundedOption,
    ImageMask.circle => context.l10n.circleLabel,
    ImageMask.squircle => context.l10n.squircleOption,
    ImageMask.star => context.l10n.starOption,
    ImageMask.heart => context.l10n.heartOption,
  };
}

/// Filled silhouette of an [ImageMask] used inside the shape tile.
/// Drawing the actual silhouette (instead of an icon proxy) keeps
/// the preview honest — what you see is what gets clipped.
class _MaskPreviewPainter extends CustomPainter {
  const _MaskPreviewPainter({required this.mask, required this.color});

  final ImageMask mask;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    final rect = Offset.zero & size;
    switch (mask) {
      case ImageMask.original:
        canvas.drawRect(rect, paint);
        break;
      case ImageMask.rounded:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          paint,
        );
        break;
      case ImageMask.circle:
        canvas.drawCircle(rect.center, size.shortestSide / 2, paint);
        break;
      case ImageMask.squircle:
        final path = ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(size.shortestSide * 0.4),
        ).getOuterPath(rect);
        canvas.drawPath(path, paint);
        break;
      case ImageMask.star:
        canvas.drawPath(_starPath(size), paint);
        break;
      case ImageMask.heart:
        canvas.drawPath(_heartPath(size), paint);
        break;
    }
  }

  Path _starPath(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.shortestSide / 2;
    final inner = outer * 0.4;
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / points;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  Path _heartPath(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w / 2, h * 0.95);
    path.cubicTo(-w * 0.1, h * 0.6, w * 0.15, -h * 0.05, w / 2, h * 0.28);
    path.cubicTo(
      w - w * 0.15,
      -h * 0.05,
      w + w * 0.1,
      h * 0.6,
      w / 2,
      h * 0.95,
    );
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _MaskPreviewPainter oldDelegate) =>
      oldDelegate.mask != mask || oldDelegate.color != color;
}
