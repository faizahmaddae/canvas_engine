import 'package:flutter/widgets.dart';

import '../core/editor_document.dart';
import 'document_view.dart';

/// Single source of truth for "render an [EditorDocument] as a
/// thumbnail" — both the live Home template strip and the recent
/// project PNG capture should funnel through this widget so a
/// thumbnail can never disagree with the editor canvas.
///
/// Concretely it wraps [DocumentView] with the two settings the rest
/// of the app keeps forgetting:
///
///   * `backgroundFill: document.background` — mirrors whatever fill
///     (solid colour or gradient) the editor canvas paints, so a
///     gradient template never falls back to a flat tone on Home.
///   * `honorTransparentMode: true` — so a transparent project
///     stays transparent in the thumbnail instead of being flattened
///     to white.
///
/// Selection chrome, snap guides, gesture detectors and the viewport
/// transform are *not* part of [DocumentView], so they cannot leak
/// into a thumbnail captured through this widget.
class DocumentThumbnail extends StatelessWidget {
  const DocumentThumbnail({super.key, required this.document});

  final EditorDocument document;

  /// The backdrop colour a [ProjectSaveService] / PNG capture should
  /// pass to the exporter as the *opaque flatten* fill (e.g. JPG
  /// composite, letterbox). Returns the dominant tone of the
  /// document's [BackgroundFill]; gradient docs still render their
  /// gradient because the renderer reads `document.background`
  /// directly, but legacy headless paths that only know how to take
  /// a `Color` get a sensible fallback.
  static Color backgroundFor(EditorDocument document) =>
      // ignore: deprecated_member_use_from_same_package
      document.backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: document.width,
      height: document.height,
      child: DocumentView(
        document: document,
        backgroundFill: document.background,
        honorTransparentMode: true,
      ),
    );
  }
}
