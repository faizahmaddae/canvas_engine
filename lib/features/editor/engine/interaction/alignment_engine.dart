import 'dart:ui';

import '../core/layer_transform.dart';

/// Which side of the shared bounding box each layer aligns to.
///
/// Mirrors the six standard alignment commands every vector editor
/// exposes (Figma / Sketch / Keynote / PowerPoint), grouped by axis:
///
/// * Horizontal axis: [left] / [centerX] / [right] — moves each layer
///   on X only, snapping its left edge / centre / right edge to the
///   group's bounding box.
/// * Vertical axis: [top] / [centerY] / [bottom] — same on Y.
///
/// Pure data: every value carries its target axis as a flag so the
/// engine does not have to switch on the enum at every callsite.
enum AlignAxis {
  left(isHorizontal: true),
  centerX(isHorizontal: true),
  right(isHorizontal: true),
  top(isHorizontal: false),
  centerY(isHorizontal: false),
  bottom(isHorizontal: false);

  const AlignAxis({required this.isHorizontal});
  final bool isHorizontal;
}

/// Axis along which a distribution operation evens out the gaps.
///
/// * [horizontal] — keeps each layer's Y intact, redistributes X so the
///   gaps between adjacent rects become equal.
/// * [vertical] — same on the Y axis.
enum DistributeAxis { horizontal, vertical }

/// Pure, stateless layout helpers: align + distribute.
///
/// Mirrors the [SnapEngine] in spirit: takes plain transforms in,
/// returns plain transforms out, knows nothing about widgets / providers
/// / commands. The application layer wraps the result in a
/// `CompositeCommand` of `SetLayerTransformCommand`s.
///
/// Operates on the *unrotated* bounding rect of every layer
/// ([LayerTransform.unrotatedRect]). Rotated layers get aligned by
/// their AABB, which matches Figma's behaviour and is what users
/// expect — aligning a rotated element by its true rotated edge would
/// be visually surprising.
class AlignmentEngine {
  const AlignmentEngine();

  /// Align every entry in [initials] along [axis]. Returns a new map
  /// with the same keys; values whose position would not change are
  /// returned unchanged so callers can drop them from their command
  /// batch.
  ///
  /// No-op (returns the input map) when fewer than two layers are
  /// supplied — alignment with one element is the identity.
  Map<String, LayerTransform> align(
    Map<String, LayerTransform> initials,
    AlignAxis axis,
  ) {
    if (initials.length < 2) return initials;
    final bounds = _bounds(initials.values);
    final out = <String, LayerTransform>{};
    initials.forEach((id, t) {
      final rect = t.unrotatedRect;
      double newX = rect.left;
      double newY = rect.top;
      switch (axis) {
        case AlignAxis.left:
          newX = bounds.left;
        case AlignAxis.centerX:
          newX = bounds.center.dx - rect.width / 2;
        case AlignAxis.right:
          newX = bounds.right - rect.width;
        case AlignAxis.top:
          newY = bounds.top;
        case AlignAxis.centerY:
          newY = bounds.center.dy - rect.height / 2;
        case AlignAxis.bottom:
          newY = bounds.bottom - rect.height;
      }
      out[id] = t.copyWith(position: Offset(newX, newY));
    });
    return out;
  }

  /// Distribute every entry in [initials] along [axis] so that the
  /// gaps between adjacent rects become equal. The first and last
  /// rects (along the axis) stay anchored — only the in-between rects
  /// move. This matches Figma / PowerPoint distribution.
  ///
  /// Returns the input map unchanged when fewer than three layers are
  /// supplied (distributing two layers has no defined behaviour) or
  /// when the available space between the outer rects is too small
  /// to fit the inner rects without overlap (in which case forcing
  /// distribution would crush them — better to no-op and let the
  /// caller surface a UI affordance).
  Map<String, LayerTransform> distribute(
    Map<String, LayerTransform> initials,
    DistributeAxis axis,
  ) {
    if (initials.length < 3) return initials;

    // Sort entries by leading edge along the chosen axis.
    final entries = initials.entries.toList()
      ..sort((a, b) {
        final ra = a.value.unrotatedRect;
        final rb = b.value.unrotatedRect;
        final av = axis == DistributeAxis.horizontal ? ra.left : ra.top;
        final bv = axis == DistributeAxis.horizontal ? rb.left : rb.top;
        return av.compareTo(bv);
      });

    final firstRect = entries.first.value.unrotatedRect;
    final lastRect = entries.last.value.unrotatedRect;

    // Total span = trailing edge of last rect minus leading edge of
    // first rect. Sum of inner rect extents = total length we need
    // to subtract before we can divide what's left into equal gaps.
    final spanStart = axis == DistributeAxis.horizontal
        ? firstRect.left
        : firstRect.top;
    final spanEnd =
        axis == DistributeAxis.horizontal ? lastRect.right : lastRect.bottom;
    final total = spanEnd - spanStart;

    double sumExtents = 0;
    for (final e in entries) {
      final r = e.value.unrotatedRect;
      sumExtents += axis == DistributeAxis.horizontal ? r.width : r.height;
    }

    final gapCount = entries.length - 1;
    final gap = (total - sumExtents) / gapCount;
    // Negative gap means the outer rects don't have room to host the
    // inner ones without overlap. Refuse rather than crush.
    if (gap < 0 || !gap.isFinite) return initials;

    final out = <String, LayerTransform>{};
    var cursor = spanStart;
    for (final e in entries) {
      final t = e.value;
      final r = t.unrotatedRect;
      final extent =
          axis == DistributeAxis.horizontal ? r.width : r.height;
      final leading = cursor;
      cursor = leading + extent + gap;
      Offset newPos;
      if (axis == DistributeAxis.horizontal) {
        newPos = Offset(leading, t.position.dy);
      } else {
        newPos = Offset(t.position.dx, leading);
      }
      out[e.key] = t.copyWith(position: newPos);
    }
    return out;
  }

  /// Axis-aligned union of every transform's [LayerTransform.unrotatedRect].
  /// Empty input is undefined — callers must check.
  Rect _bounds(Iterable<LayerTransform> transforms) {
    final it = transforms.iterator;
    if (!it.moveNext()) {
      throw StateError('AlignmentEngine._bounds requires at least one layer');
    }
    var bounds = it.current.unrotatedRect;
    while (it.moveNext()) {
      bounds = bounds.expandToInclude(it.current.unrotatedRect);
    }
    return bounds;
  }
}
