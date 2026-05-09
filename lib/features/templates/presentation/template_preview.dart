import 'package:flutter/material.dart';

import '../../editor/engine/rendering/document_thumbnail.dart';
import '../domain/template.dart';

/// Renders a [Template] thumbnail by building the seed document and
/// scaling [DocumentThumbnail] down with [FittedBox]. Reusing the
/// same renderer the editor uses guarantees the preview matches
/// what the user gets after tapping it — no separate "thumbnail
/// painter" to drift out of sync.
///
/// The preview is wrapped in a [RepaintBoundary] so scrolling the
/// templates strip on Home doesn't repaint sibling cards.
class TemplatePreview extends StatelessWidget {
  const TemplatePreview({
    super.key,
    required this.template,
    this.borderRadius = 16,
    this.fit = BoxFit.cover,
  });

  final Template template;
  final double borderRadius;

  /// How the rendered document is fitted into the available box.
  ///
  /// `cover` reads as a magazine thumbnail (full-bleed, may crop) —
  /// good for the full-screen browse grid where each tile is large
  /// enough to absorb the crop. `contain` preserves the design's
  /// native aspect ratio with a small letterbox around it — better
  /// for the small Home strip tiles where a cropped headline would
  /// look broken.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final doc = template.build();
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: RepaintBoundary(
        child: FittedBox(
          fit: fit,
          alignment: Alignment.center,
          child: DocumentThumbnail(document: doc),
        ),
      ),
    );
  }
}
