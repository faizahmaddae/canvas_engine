import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../engine/commands/image_commands.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../presentation/widgets/layer_border_body.dart';
import '../../presentation/widgets/layer_shadow_body.dart';
import '../../toolbar/presentation/widgets/preset_chip.dart';
import '../../ui/precision_disclosure.dart';
import 'image_panel_shell.dart';

/// The Image dock's «سبک» panel — one surface for how the photo's
/// silhouette is dressed (image-studio §3).
///
/// Shape, Border and Shadow were three separate sheets answering one
/// question. Here the shape strip sits on top (the most visual
/// choice, always visible), and the border and shadow bodies follow
/// as disclosures whose header rows carry their live value — so the
/// closed sheet already says what is on.
///
/// The shared [LayerBorderBody]/[LayerShadowBody] are reused through
/// their injectable `shell` hooks with a passthrough, so the §2
/// preview channels, adapter divergences and one-undo rule ship
/// untouched.
class ImageStyleBody extends ConsumerWidget {
  const ImageStyleBody({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = EditorValueFormat.of(context);
    // Live values for the disclosure headers: the closed row answers
    // "is this on?" without a tap.
    final borderValue = layer.borderWidth > 0
        ? fmt.px(layer.borderWidth.round())
        : l10n.noneOption;
    final shadowValue = layer.shadowOpacity > 0
        ? fmt.percent((layer.shadowOpacity * 100).round())
        : l10n.noneOption;
    return ImagePanelShell(
      title: l10n.styleTool,
      icon: AppIcons.stylePresets,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShapeStrip(layer: layer),
          const SizedBox(height: 6),
          PrecisionDisclosure(
            compact: true,
            icon: AppIcons.borderTool,
            titleClosed: l10n.borderTool,
            headerValue: borderValue,
            children: [ImageBorderSection(layer: layer)],
          ),
          PrecisionDisclosure(
            compact: true,
            icon: AppIcons.shadowTool,
            titleClosed: l10n.shadowTool,
            headerValue: shadowValue,
            children: [ImageShadowSection(layer: layer)],
          ),
        ],
      ),
    );
  }
}

/// The image-layer border body without a panel shell — the Style
/// sheet's «کادر» section. Public so the §2 contract tests can pump
/// the exact widget the sheet mounts.
class ImageBorderSection extends StatelessWidget {
  const ImageBorderSection({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context) {
    return LayerBorderBody<ImageLayer>(
      layer: layer,
      adapter: BorderPanelAdapter<ImageLayer>(
        command:
            ({
              required layerId,
              color,
              clearColor = false,
              width,
              live = false,
            }) => SetImageBorderCommand(
              layerId: layerId,
              color: color,
              width: width,
              live: live,
            ),
        read: (l) => (color: l.borderColor, width: l.borderWidth),
        hasColor: (_) => true,
        showPrecisionSlider: true,
        // Passthrough: this body is a section of the Style sheet,
        // not a panel of its own.
        shell: ({required child}) => child,
      ),
    );
  }
}

/// The image-layer shadow body without a panel shell — the Style
/// sheet's «سایه» section.
class ImageShadowSection extends StatelessWidget {
  const ImageShadowSection({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context) {
    return LayerShadowBody<ImageLayer>(
      layer: layer,
      adapter: ShadowPanelAdapter<ImageLayer>(
        command:
            ({required layerId, color, blur, offset, opacity, live = false}) =>
                SetImageShadowCommand(
                  layerId: layerId,
                  color: color,
                  blur: blur,
                  offset: offset,
                  opacity: opacity,
                  live: live,
                ),
        read: (l) => (
          color: l.shadowColor,
          blur: l.shadowBlur,
          offset: l.shadowOffset,
          opacity: l.shadowOpacity,
        ),
        shell: ({required child}) => child,
      ),
    );
  }
}

/// The silhouette strip — moved from the retired Shape sheet. Six
/// tiles map 1:1 to [ImageMask] values; tapping commits a
/// [SetImageMaskCommand] immediately so the change participates in
/// undo/redo. Source, transform, fit and selection are untouched.
class _ShapeStrip extends ConsumerWidget {
  const _ShapeStrip({required this.layer});

  final ImageLayer layer;

  static const _options = <ImageMask>[
    ImageMask.original,
    ImageMask.rounded,
    ImageMask.circle,
    ImageMask.squircle,
    ImageMask.star,
    ImageMask.heart,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final mask = _options[i];
          final selected = layer.mask == mask;
          return PresetChip.option(
            width: 76,
            selected: selected,
            label: _shapeOptionLabel(context, mask),
            preview: SizedBox(
              height: 32,
              width: 32,
              child: Builder(
                builder: (ctx) => CustomPaint(
                  painter: _MaskPreviewPainter(
                    mask: mask,
                    color:
                        IconTheme.of(ctx).color ??
                        AppTokens.of(ctx).textSecondary,
                  ),
                ),
              ),
            ),
            onTap: () {
              if (layer.mask == mask) return;
              EditorHaptics.toggle();
              ref
                  .read(documentControllerProvider.notifier)
                  .execute(SetImageMaskCommand(layerId: layer.id, mask: mask));
            },
          );
        },
      ),
    );
  }
}

String _shapeOptionLabel(BuildContext context, ImageMask mask) {
  return switch (mask) {
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
