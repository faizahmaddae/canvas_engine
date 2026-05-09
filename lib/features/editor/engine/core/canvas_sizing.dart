import 'dart:math' as math;
import 'dart:ui';

import 'editor_document.dart';

/// Single source of truth for "how big should a freshly-inserted
/// object be on this canvas?".
///
/// Background. Insertion flows (Add Shape, Add Sticker, Add Text,
/// future Add ...) author their default sizes against a single
/// reference canvas — historically `1080×1080`. On a tiny sticker
/// canvas (e.g. `512×512`) those defaults look bloated; on a huge
/// poster / photo canvas (e.g. `6720×4480`) they look invisible
/// and the user thinks the tool didn't fire.
///
/// The Text controller already solved the problem for font size
/// via a private `_effectiveCanvasDim` + `_referenceCanvasSize`
/// pair. This helper extracts that idea into one engine-level
/// utility every insertion flow can call. The Text controller
/// continues to own font-specific clamping (8..400 pt + 0.5 pt
/// snap), but delegates the canvas-dimension math here so the
/// "what counts as the canvas's effective size?" rule lives in
/// exactly one place.
///
/// Pure / no Riverpod — depends only on [EditorDocument].
class CanvasSizing {
  CanvasSizing._();

  /// Author-time reference canvas. Every insertion flow should
  /// author its default sizes assuming a `referenceCanvasDim`-square
  /// canvas; on any other canvas [scaleSize] / [scaleDimension]
  /// produces the visually-equivalent value.
  ///
  /// Pinning to `1080` matches the historical Text default and is
  /// the most common "design" canvas long-edge across our entry
  /// flows (square posts, social cards). Other canvases scale
  /// proportionally — they don't penalise the reference.
  static const double referenceCanvasDim = 1080.0;

  /// Aspect-ratio threshold beyond which we use the canvas's long
  /// axis instead of the geometric mean. At ratios above this
  /// (e.g. a `4096×400` ticker) the geometric mean still
  /// under-represents the canvas's "presence" and inserted
  /// objects feel too small. Mirrors the Text controller's
  /// previous private constant.
  static const double extremeAspectRatio = 4.0;

  /// Fraction of canvas the inserted object is allowed to fill on
  /// either axis. Stops a huge reference size from spilling off a
  /// tiny canvas after up-scaling never applies (the inserted
  /// object is bigger than the canvas itself). 90 % matches the
  /// Text controller's `_newLayerWrapFraction` so all insertion
  /// flows agree on the comfortable-margin budget.
  static const double maxCanvasFillFraction = 0.9;

  /// The single representative pixel-dimension we treat the canvas
  /// as having for default-size purposes.
  ///
  /// Geometric mean (`sqrt(w × h)`) wins over `min(w, h)` because
  /// it reflects the canvas's overall *presence* instead of its
  /// narrowest axis. For pathological aspect ratios (≥ 4:1) we
  /// fall back to the long axis so ticker-tape canvases still get
  /// usable defaults.
  static double effectiveDim(EditorDocument doc) {
    final w = doc.width;
    final h = doc.height;
    if (w <= 0 || h <= 0) return 0.0;
    final long = w > h ? w : h;
    final short = w > h ? h : w;
    if (short <= 0) return long;
    if (long / short >= extremeAspectRatio) return long;
    return math.sqrt(w * h);
  }

  /// Scalar applied to author-time defaults so they read at the
  /// same visual proportion on any canvas. Returns `1.0` for
  /// degenerate / empty documents so inserts still produce a
  /// sensible non-zero size.
  static double scaleFactor(EditorDocument doc) {
    final eff = effectiveDim(doc);
    if (eff <= 0) return 1.0;
    return eff / referenceCanvasDim;
  }

  /// Rescale [reference] (designed against [referenceCanvasDim])
  /// for [doc]. The result is then capped at
  /// [maxCanvasFillFraction] of each axis so the inserted object
  /// always fits comfortably inside the canvas — even when the
  /// reference itself is wider/taller than a small canvas.
  ///
  /// Aspect ratio of [reference] is preserved by the cap.
  static Size scaleSize(Size reference, EditorDocument doc) {
    final f = scaleFactor(doc);
    var w = reference.width * f;
    var h = reference.height * f;
    final maxW = doc.width * maxCanvasFillFraction;
    final maxH = doc.height * maxCanvasFillFraction;
    if (maxW > 0 && maxH > 0 && (w > maxW || h > maxH)) {
      final shrink = math.min(maxW / w, maxH / h);
      w *= shrink;
      h *= shrink;
    }
    return Size(w, h);
  }

  /// Rescale a single dimension (e.g. font size) the same way
  /// [scaleSize] would scale a width. Callers that need extra
  /// clamping (font min/max, snap-to-half-pt) layer it on top.
  static double scaleDimension(double reference, EditorDocument doc) {
    return reference * scaleFactor(doc);
  }

  /// Convert a "fraction-of-canvas" into a concrete pixel
  /// thickness, with a sane absolute min/max clamp.
  ///
  /// Designed for stroke-like presets (shape borders, future
  /// underline / divider widths, etc.) that should read at the
  /// same *visual proportion* on any canvas. The formula is the
  /// same on every input — there is no reference canvas, no
  /// per-size special case:
  ///
  /// ```
  ///   px = clamp(effectiveDim(doc) * fraction, minPx, maxPx)
  /// ```
  ///
  /// * `effectiveDim` already encodes the geometric-mean / extreme-
  ///   aspect rule, so a `4096×400` ticker doesn't get a hairline
  ///   stroke from its short axis.
  /// * `minPx` keeps tiny canvases (e.g. 100×100 stickers) from
  ///   producing sub-pixel strokes that vanish.
  /// * `maxPx` keeps huge canvases (e.g. 12000×12000 print) from
  ///   producing bezel-thick strokes when the user picks "Bold".
  ///
  /// Both clamps are required so the same call works on every
  /// canvas size. Returns `minPx` for degenerate / empty
  /// documents.
  static double proportionalStroke(
    EditorDocument doc, {
    required double fraction,
    required double minPx,
    required double maxPx,
  }) {
    assert(fraction > 0, 'fraction must be > 0');
    assert(minPx >= 0 && maxPx >= minPx, 'minPx <= maxPx required');
    final eff = effectiveDim(doc);
    if (eff <= 0) return minPx;
    final raw = eff * fraction;
    if (raw < minPx) return minPx;
    if (raw > maxPx) return maxPx;
    return raw;
  }
}
