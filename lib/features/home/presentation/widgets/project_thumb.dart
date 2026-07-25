import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/saffron_diamond.dart';
import '../../../editor/application/imported_image_path_codec.dart';
import '../../../editor/engine/core/editor_document.dart';
import '../../../editor/engine/rendering/document_thumbnail.dart';
import '../../../editor/engine/serialization/document_codec.dart';
import '../../domain/project.dart';

/// One recent-work thumbnail on Home's horizontal rail. Quiet
/// chrome: hairline-bordered surface card, radius 12, the project's
/// PNG thumbnail as the colour, the name in a small caption beneath.
///
/// Navigation-doc fix: a still-empty project (no layers yet) must
/// never read as a blank white card — its saved PNG *is* blank, so
/// rendering it looks broken. Empty projects get the subtle
/// mark+label placeholder instead, as do projects with no usable
/// thumbnail (no path, stale version, deleted file).
///
/// The rail used to stop there — "a teaser, not a renderer" — and
/// show the empty-design mark for ANY project without a usable PNG.
/// That is a claim, not a fallback: a project with a photo and a
/// headline in it announced itself on Home as an empty design, while
/// the Projects tab rendered the same document correctly one tab
/// away. Both now go through [ProjectPreview], which live-renders
/// when the PNG is missing or stale and reserves the empty-design
/// mark for documents that really are empty.
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
            Container(
              width: width,
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadii.button),
                border: Border.all(color: tokens.border),
              ),
              child: ProjectPreview(project: project),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Flexible so the caption yields instead of overflowing
            // when the user's text-size setting grows the line beyond
            // the rail's remaining height.
            Flexible(
              child: Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypeScale.caption.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one thing that decides what a saved project LOOKS like,
/// wherever it is shown.
///
/// The cascade, in order:
///   1. genuinely empty document  → the empty-design mark;
///   2. a fresh PNG on disk       → that PNG, letterboxed;
///   3. anything else             → a live render of the document;
///   4. undecodable JSON          → a neutral icon.
///
/// Step 3 is what the Home rail was missing. It had steps 1, 2 and
/// then fell back to step 1's placeholder — so "no thumbnail yet" and
/// "nothing in it" were indistinguishable, and a real design read as
/// empty. A cached PNG is an optimisation; the document is the truth,
/// and a preview should never be MORE wrong than the data allows.
class ProjectPreview extends ConsumerWidget {
  const ProjectPreview({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    // Neutral "page" colour behind the preview (paper-muted in light,
    // ink-muted in dark) — lets a letterboxed portrait or landscape
    // canvas breathe instead of being hard-cropped.
    final canvasBg = tokens.surfaceMuted;

    if (isEmptyDesignJson(project.documentJson)) {
      return ColoredBox(
        color: canvasBg,
        child: EmptyDesignPlaceholder(name: project.name),
      );
    }

    // Only trust a cached PNG if it exists AND was produced by the
    // current renderer. Older PNGs baked an opaque white backdrop and
    // would mis-represent any coloured or transparent canvas.
    final thumb = project.thumbnailPath;
    final pngIsFresh =
        thumb != null &&
        project.thumbnailVersion >= Project.currentThumbnailVersion &&
        File(thumb).existsSync();

    if (pngIsFresh) {
      return ColoredBox(
        color: canvasBg,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Image.file(
            File(thumb),
            // contain, so the whole canvas is visible — a portrait
            // 1080x1920 design is shown in full rather than
            // centre-cropped into a meaningless square.
            fit: BoxFit.contain,
            cacheWidth: 480,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) =>
                EmptyDesignPlaceholder(name: project.name),
          ),
        ),
      );
    }

    // Null on the first frame, before the directory future lands; the
    // decode then falls back to a raw one until it resolves.
    final importedImagesDir = ref
        .watch(importedImagesDirectoryProvider)
        .value
        ?.path;
    final doc = _tryDecode(project.documentJson, importedImagesDir);
    if (doc != null) {
      return ColoredBox(
        color: canvasBg,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: RepaintBoundary(child: DocumentThumbnail(document: doc)),
          ),
        ),
      );
    }

    // Corrupt JSON — still better than a blank rectangle.
    return DecoratedBox(
      decoration: BoxDecoration(color: canvasBg),
      child: Center(
        child: Icon(Icons.image_outlined, size: 28, color: tokens.textMuted),
      ),
    );
  }

  static EditorDocument? _tryDecode(String json, String? importedImagesDir) {
    try {
      if (importedImagesDir == null) return DocumentCodec.decode(json);
      return ImportedImagePathCodec.decodeToRuntime(
        json,
        importedImagesDir: importedImagesDir,
        fileExists: (path) => File(path).existsSync(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// True when the saved document would preview as a blank white
/// rectangle: no layers AND the default white background (the codec
/// omits `background` at the default, and writes a bare ARGB int for
/// solid colours). A layer-less canvas with a deliberate colour or
/// gradient background is real content and still previews live.
///
/// Decoding the stored JSON envelope is cheap at card counts; only
/// the top-level `layers` / `background` entries are inspected.
/// Shared by the Home rail's [ProjectThumb] and the Projects tab's
/// grid card so "never a blank white thumbnail" holds everywhere.
bool isEmptyDesignJson(String documentJson) {
  const whiteArgb = 0xFFFFFFFF;
  try {
    final doc = jsonDecode(documentJson);
    if (doc is! Map<String, dynamic>) return false;
    final layers = doc['layers'];
    if (layers is! List || layers.isNotEmpty) return false;
    final background = doc['background'];
    return background == null || background == whiteArgb;
  } on FormatException {
    return false;
  }
}

/// Subtle mark+label placeholder for projects with nothing to
/// preview: the saffron diamond over the project name on
/// surfaceMuted — reads as "yours, not started" rather than broken.
class EmptyDesignPlaceholder extends StatelessWidget {
  const EmptyDesignPlaceholder({super.key, required this.name});

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
