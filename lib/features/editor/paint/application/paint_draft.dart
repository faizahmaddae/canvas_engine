import 'dart:math' as math;
import 'dart:ui';

import '../../engine/core/layer_transform.dart';
import '../../engine/modules/paint/paint_layer.dart';

/// In-flight paint stroke / shape being drawn on the canvas.
///
/// Holds raw canvas-space points; defers normalization + bounding-box
/// computation until commit (or preview render) time so adding a point
/// during a freestyle drag is O(1).
///
/// Intentionally mutable — only the gesture surface owns and mutates a
/// draft, and the entire object is discarded once the gesture commits
/// or cancels.
class PaintDraft {
  PaintDraft({
    required this.kind,
    required this.strokeColor,
    required this.strokeWidth,
    required this.points,
    this.fillColor,
    this.sides = 6,
    this.blurSigma = 12.0,
  });

  final PaintKind kind;
  final Color strokeColor;
  final double strokeWidth;

  /// Optional fill colour. Honoured by the painter only for closed
  /// shape kinds (rectangle / circle / hexagon / polygon); ignored
  /// for line-style strokes and blur.
  final Color? fillColor;

  /// Side count for [PaintKind.polygon]. Hexagon ignores this.
  final int sides;

  /// Blur sigma for [PaintKind.blur].
  final double blurSigma;

  /// Raw canvas-space points captured during the gesture.
  final List<Offset> points;

  /// Bounding rectangle in canvas space, padded so the stroke isn't
  /// clipped by its own layer bounds. Returns null if the stroke is
  /// degenerate (no points).
  Rect? previewBounds() {
    if (points.isEmpty) return null;
    var minX = points.first.dx;
    var maxX = minX;
    var minY = points.first.dy;
    var maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    // Pad so the stroke (which extends ±strokeWidth/2 around each
    // point) and arrow-head fit inside the layer rect. Also enforces a
    // minimum so a single-point tap still has a visible bounding box.
    final pad = math.max(strokeWidth, 2.0);
    var rect = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    if (rect.width < 1 || rect.height < 1) {
      rect = Rect.fromCenter(
        center: rect.center,
        width: math.max(rect.width, 1),
        height: math.max(rect.height, 1),
      );
    }
    return rect;
  }

  /// Convert raw points into normalized (0..1) coordinates relative to
  /// [bounds]. Used both at commit time and when the preview painter
  /// renders the in-flight stroke.
  List<Offset> normalizedFor(Rect bounds) {
    final w = bounds.width;
    final h = bounds.height;
    if (w <= 0 || h <= 0) return const <Offset>[];
    return [
      for (final p in points)
        Offset((p.dx - bounds.left) / w, (p.dy - bounds.top) / h),
    ];
  }

  /// Build a finalized [PaintLayer] ready to ship through
  /// [AddLayerCommand]. Returns null when the stroke is degenerate
  /// (e.g. a zero-length line or a tap with a non-tap-friendly tool).
  PaintLayer? toLayer({
    required String id,
    required Size docSize,
  }) {
    if (points.isEmpty) return null;
    if (kind != PaintKind.freestyle && points.length < 2) return null;
    final bounds = previewBounds();
    if (bounds == null) return null;
    final norm = normalizedFor(bounds);
    if (norm.isEmpty) return null;
    return PaintLayer(
      id: id,
      transform: LayerTransform(
        position: bounds.topLeft,
        size: bounds.size,
      ),
      kind: kind,
      // Blur is bbox-only; storing the drag points wastes JSON space
      // since the painter never reads them. Wrap the runtime list so
      // PaintLayer's normalizedPoints stays unmodifiable for the life
      // of the document.
      normalizedPoints: kind == PaintKind.blur
          ? const <Offset>[]
          : List.unmodifiable(norm),
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      fillColor: _shouldFill ? fillColor : null,
      sides: kind == PaintKind.hexagon ? 6 : sides,
      blurSigma: blurSigma,
    );
  }

  /// Fill is meaningful only for closed shape kinds. Line-style strokes
  /// and blur drop any user-set fill at commit time so the persisted
  /// layer stays clean.
  bool get _shouldFill =>
      fillColor != null &&
      (kind == PaintKind.rectangle ||
          kind == PaintKind.circle ||
          kind == PaintKind.hexagon ||
          kind == PaintKind.polygon);
}

/// Convenience: produce a default name for a layer of [kind] (used by
