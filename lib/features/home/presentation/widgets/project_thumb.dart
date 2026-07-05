import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/saffron_diamond.dart';
import '../../domain/project.dart';

/// One recent-work thumbnail on Home's horizontal rail. Quiet
/// chrome: hairline-bordered surface card, radius 12, the project's
/// PNG thumbnail as the colour, the name in a small caption beneath.
///
/// Navigation-doc fix: a still-empty project (no layers yet) must
/// never read as a blank white card — its saved PNG *is* blank, so
/// rendering it looks broken. Empty projects get the subtle
/// mark+label placeholder instead, as do projects with no usable
/// thumbnail (no path, stale version, deleted file). The rail is a
/// teaser, not a renderer — it never decodes the document for a
/// preview.
class ProjectThumb extends StatelessWidget {
  const ProjectThumb({
    super.key,
    required this.project,
    required this.onTap,
    this.width = 110,
    this.height = 140,
  });

  final Project project;
  final VoidCallback onTap;
  final double width;
  final double height;

  bool get _hasFreshThumbnail =>
      project.thumbnailPath != null &&
      project.thumbnailVersion >= Project.currentThumbnailVersion;

  /// True when the saved document has no layers — its thumbnail
  /// would be a featureless canvas-colour rectangle. Decoding the
  /// stored JSON envelope is cheap at rail counts (≤8) and only the
  /// top-level `layers` list is inspected.
  bool get _isEmptyDesign {
    try {
      final doc = jsonDecode(project.documentJson);
      if (doc is! Map<String, dynamic>) return false;
      final layers = doc['layers'];
      return layers is List && layers.isEmpty;
    } on FormatException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final showPreview = _hasFreshThumbnail && !_isEmptyDesign;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: width,
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadii.button),
                border: Border.all(color: tokens.border),
              ),
              child: showPreview
                  ? Image.file(
                      File(project.thumbnailPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _EmptyDesignPlaceholder(name: project.name),
                    )
                  : _EmptyDesignPlaceholder(name: project.name),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypeScale.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtle mark+label placeholder for projects with nothing to
/// preview: the saffron diamond over the project name on
/// surfaceMuted — reads as "yours, not started" rather than broken.
class _EmptyDesignPlaceholder extends StatelessWidget {
  const _EmptyDesignPlaceholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SaffronDiamond(size: 10),
            const SizedBox(height: AppSpacing.xs),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypeScale.caption.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dashed «جدید» tile closing the rail — same footprint as a
/// [ProjectThumb], dashed hairline border, saffron plus + caption.
class NewProjectTile extends StatelessWidget {
  const NewProjectTile({
    super.key,
    required this.label,
    required this.onTap,
    this.width = 110,
    this.height = 140,
  });

  final String label;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomPaint(
              painter: _DashedBorderPainter(
                color: tokens.border,
                radius: AppRadii.button,
              ),
              child: SizedBox(
                width: width,
                height: height,
                child: Center(
                  child: Icon(
                    Icons.add_rounded,
                    size: 24,
                    color: tokens.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypeScale.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed rounded-rect border. Flutter's [Border] has no dash
/// support, so the tile paints its own: the rounded-rect path is
/// measured and stroked dash-by-dash.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          // Half-stroke inset keeps the dashes fully inside the tile.
          Rect.fromLTWH(0.6, 0.6, size.width - 1.2, size.height - 1.2),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
