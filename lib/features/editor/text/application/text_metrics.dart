import 'package:flutter/material.dart';

import '../../engine/core/canvas_sizing.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/modules/text/text_layer.dart';
import 'text_color_resolver.dart';

/// Text measurement + insertion-size policy for the text tool.
///
/// Pure maths: every entry point is a static function of its
/// arguments, with no `Ref`, no provider read, and no document
/// mutation. Split out of `TextToolController` (roadmap 5.6) so the
/// one place that knows how a [TextStyleSpec] turns into a bounding
/// box is not buried inside the controller's write seam and dock
/// state.
///
/// Two families live here:
///
///   * **Measurement** — [measureForMode] and friends lay a
///     [TextPainter] out with exactly the metric-affecting subset of
///     the style ([affectsMetrics] names that subset) and report the
///     size the layer's bounding box must take.
///   * **Insertion policy** — [scaleStyleToCanvas],
///     [resolveNewLayerLayout], [seedDefaultShadowIfMissing]: the
///     "author against a 1080-px reference canvas" rules that decide
///     what a brand-new text layer looks like on this document.
///
/// The visual-scale pair ([translateFontSizeForVisualScale] for
/// writes, [visualFontSizeOf] for readouts) also lives here because
/// they must agree — see [kVisualScaleCompensationThreshold].
class TextMetrics {
  const TextMetrics._();

  /// Up-scale threshold above which the size pipeline treats the
  /// FittedBox magnification as user intent: writes compensate
  /// ([translateFontSizeForVisualScale]) and readouts report the
  /// magnified px ([visualFontSizeOf]). The 2% headroom absorbs
  /// float noise from re-measures so a nominally-unscaled layer
  /// never flips between the two spaces. One constant, both
  /// directions — they must never disagree.
  static const double kVisualScaleCompensationThreshold = 1.02;

  /// Fraction of the canvas width that newly-added text is allowed
  /// to occupy before it must wrap. Matches Canva / Keynote: when
  /// you start typing a new text element it grows along the centre
  /// line and breaks onto a new line a comfortable margin before
  /// the canvas edge, instead of shooting off-canvas as a single
  /// runaway line. Existing layers the user has already placed and
  /// sized are NOT subject to this cap.
  static const double newLayerWrapFraction = 0.9;

  /// Reference shadow offset (designed against the 1080 canvas).
  /// Only `dy` is meaningful for the default — `dx` stays 0 so the
  /// halo sits straight under the glyph.
  static const double referenceShadowOffsetDy = 2.0;

  /// Reference canvas dimension that the user-facing default
  /// font sizes (`TextStyleSpec.fontSize` defaults like 48 pt) are
  /// authored against. A 48-pt text on a 1080-square canvas
  /// occupies ~4.4 % of the canvas — the proportion is what makes
  /// it feel "right" rather than the absolute pixel count.
  ///
  /// Pinning to a baseline matches Canva / Figma / CapCut: the
  /// designer's mental model is "this text reads as a heading on
  /// my poster", not "this text is 48 logical pixels".
  ///
  /// Delegated to [CanvasSizing.referenceCanvasDim] so every insert
  /// flow shares the same "author against 1080" rule.
  static double get _referenceCanvasSize => CanvasSizing.referenceCanvasDim;

  /// Hard floor / ceiling for the auto-scaled font size. The floor
  /// keeps a 100-px sticker canvas from collapsing the type to an
  /// invisible sub-pixel value; the ceiling stops an 8000-px export
  /// from producing an unreadable wall of glyphs that overflows the
  /// frame on first insert.
  static const double _minScaledFontSize = 8.0;
  static const double _maxScaledFontSize = 400.0;

  // ─── measurement ─────────────────────────────────────────────────

  /// Returns the bounding-box size that [content] should occupy at
  /// [style] under [mode].
  ///
  /// * [TextResizeMode.scaleText] — natural (unwrapped) size of the
  ///   text. Width grows with longer content; aspect-locked corner
  ///   drag scales the rendered text via [FittedBox].
  /// * [TextResizeMode.resizeBox] — paragraph box. Width is fixed at
  ///   [currentWidth]; height is the wrapped layout height. Corner
  ///   drag changes the wrap width and we re-measure height for the
  ///   new column.
  static Size measureForMode(
    String content,
    TextStyleSpec style,
    TextResizeMode mode,
    double currentWidth, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    switch (mode) {
      case TextResizeMode.scaleText:
        return measureNaturalSize(
          content,
          style,
          textDirectionMode: textDirectionMode,
        );
      case TextResizeMode.resizeBox:
        return measureBoxHeight(
          content,
          style,
          currentWidth,
          textDirectionMode: textDirectionMode,
        );
    }
  }

  /// Measure the natural (unwrapped) size of [content] in [style].
  ///
  /// Used by [TextResizeMode.scaleText]: bounding box equals the
  /// painter's natural size, so the visual text always fits exactly.
  /// Empty content is rendered at one space's worth of height so a
  /// freshly-staged layer still has a visible, touchable box.
  static Size measureNaturalSize(
    String content,
    TextStyleSpec style, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    final painter = _layoutPainter(
      content,
      style,
      double.infinity,
      textDirectionMode: textDirectionMode,
    );
    final size = Size(painter.width, painter.height);
    painter.dispose();
    return size;
  }

  /// Measure [content] for a NEW text layer being added to [doc]:
  /// natural size, but capped to wrap at
  /// [newLayerWrapFraction] × canvas width so the very first
  /// keystrokes of a long word / sentence don't shoot the bounding
  /// box off-canvas. The returned size is the painter's actual
  /// laid-out size (snug to the longest wrapped line), which is
  /// what callers feed into the layer transform.
  ///
  /// Falls back to a pure natural measure when the canvas has no
  /// width yet (e.g. tests with a 0-sized doc).
  static Size measureForNewLayer(
    String content,
    TextStyleSpec style,
    EditorDocument doc, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    final canvasWidth = doc.width;
    if (canvasWidth <= 0) {
      return measureNaturalSize(
        content,
        style,
        textDirectionMode: textDirectionMode,
      );
    }
    final cap = canvasWidth * newLayerWrapFraction;
    final painter = _layoutPainter(
      content,
      style,
      cap,
      textDirectionMode: textDirectionMode,
    );
    final size = Size(painter.width, painter.height);
    painter.dispose();
    return size;
  }

  /// Measure the height required to render [content] in [style]
  /// wrapped at [width]. Used by [TextResizeMode.resizeBox] so the
  /// box height tracks the wrapped paragraph as content / width / style
  /// changes.
  static Size measureBoxHeight(
    String content,
    TextStyleSpec style,
    double width, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    final painter = _layoutPainter(
      content,
      style,
      width,
      textDirectionMode: textDirectionMode,
    );
    final h = painter.height;
    painter.dispose();
    return Size(width, h);
  }

  static TextPainter _layoutPainter(
    String content,
    TextStyleSpec style,
    double maxWidth, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    return TextPainter(
      text: TextSpan(
        // Empty content collapses to zero height; one space preserves
        // a line of height during a momentary clear.
        text: content.isEmpty ? ' ' : content,
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: style.letterSpacing,
          height: style.lineHeight,
        ),
      ),
      textAlign: style.alignment,
      textDirection: textDirectionForContent(content, mode: textDirectionMode),
      maxLines: null,
    )..layout(maxWidth: maxWidth);
  }

  /// True when [next] differs from [base] in any field that changes
  /// the text painter's measured size. Decoration fields (color,
  /// shadow, background) are intentionally ignored.
  static bool affectsMetrics(TextStyleSpec base, TextStyleSpec next) {
    return base.fontFamily != next.fontFamily ||
        base.fontSize != next.fontSize ||
        base.fontWeight != next.fontWeight ||
        base.italic != next.italic ||
        base.letterSpacing != next.letterSpacing ||
        base.lineHeight != next.lineHeight ||
        base.alignment != next.alignment;
  }

  // ─── visual scale (FittedBox compensation) ───────────────────────

  /// When a `scaleText` layer's bounding box has been corner-dragged
  /// to a different size than its natural metrics, [TextStyleSpec.fontSize]
  /// no longer reflects what the user sees on canvas — the
  /// [FittedBox] in the renderer is multiplying it by the box's
  /// scale factor. The size sheet (stepper / slider / preset chips)
  /// computes its requests against `style.fontSize`, so applying
  /// them verbatim would snap the rendered glyphs back to the
  /// natural metrics and cause a visual jump.
  ///
  /// To keep the user's intent honest, we translate the requested
  /// `size` by the same scale factor — so a +10% bump in the
  /// stepper produces a +10% bump in the rendered glyph height,
  /// regardless of any prior corner drag. After the write, the
  /// box is re-measured to natural metrics for the new fontSize
  /// (via the caller's apply-style path), so the layer ends in a
  /// normalized state and subsequent size changes operate directly
  /// without any further translation.
  ///
  /// [layer] is the currently-selected text layer; `null` (nothing
  /// selected) passes [requested] straight through.
  static double translateFontSizeForVisualScale(
    TextLayer? layer,
    double requested,
  ) {
    if (layer == null) return requested;
    if (layer.resizeMode != TextResizeMode.scaleText) return requested;
    if (layer.style.fontSize <= 0) return requested;
    final natural = measureNaturalSize(
      layer.content,
      layer.style,
      textDirectionMode: layer.textDirectionMode,
    );
    if (natural.height <= 0) return requested;
    final scale = layer.transform.size.height / natural.height;
    // Only translate when the visual is *larger* than the natural
    // metrics — i.e. the user scaled the layer UP via corner drag.
    // In that direction, applying a raw font-size write would snap
    // the bounding box back to natural and shrink the rendered
    // glyphs visibly. Translating preserves the user's visual size
    // through the change.
    //
    // When scale <= 1 (box smaller than natural; FittedBox is
    // shrinking glyphs to fit), letting the raw write through keeps
    // the historical "auto-fit on style change" behaviour for
    // layers the user never enlarged.
    if (scale <= kVisualScaleCompensationThreshold) return requested;
    final ratio = requested / layer.style.fontSize;
    return layer.style.fontSize * scale * ratio;
  }

  /// Visual (rendered) px of [layer]'s glyphs — what the size chip
  /// and quick-capsule readouts must display (tb2 12/16, audit:
  /// size-readout-visual-scale-lie). Mirrors the WRITE space of
  /// [translateFontSizeForVisualScale] exactly, including its
  /// deliberate asymmetry: an up-scaled `scaleText` layer reports
  /// raw × scale (the FittedBox is magnifying; a +10% nudge then
  /// moves the number +10% instead of snapping it 2×), while a
  /// down-scaled box keeps reporting raw px — the space its writes
  /// land in. Writes stay raw; only readouts consume this.
  static double visualFontSizeOf(TextLayer layer) {
    final scale = visualScaleOf(layer);
    return layer.style.fontSize *
        (scale > kVisualScaleCompensationThreshold ? scale : 1.0);
  }

  /// Visual scale ratio of [layer] for `scaleText` mode — the
  /// multiplier applied by the on-canvas [FittedBox] to the natural
  /// glyph height. `1.0` for `resizeBox` (where the box width is the
  /// wrap column, not a scale) and as a safety fallback.
  static double visualScaleOf(TextLayer layer) {
    if (layer.resizeMode != TextResizeMode.scaleText) return 1.0;
    final natural = measureNaturalSize(
      layer.content,
      layer.style,
      textDirectionMode: layer.textDirectionMode,
    );
    if (natural.height <= 0) return 1.0;
    return layer.transform.size.height / natural.height;
  }

  /// Multiply [naturalSize] by the live session's `scaleAtBegin` so
  /// editing existing `scaleText` layers keeps the visual size the
  /// user manually set via corner-drag. Pass-through for `resizeBox`
  /// — that mode owns its width as the wrap column, not as a scale.
  static Size scalePreservedEditSize(
    Size naturalSize,
    TextResizeMode mode,
    double scaleAtBegin,
  ) {
    if (mode != TextResizeMode.scaleText) return naturalSize;
    if ((scaleAtBegin - 1).abs() < 0.001) return naturalSize;
    return Size(
      naturalSize.width * scaleAtBegin,
      naturalSize.height * scaleAtBegin,
    );
  }

  // ─── insertion policy ────────────────────────────────────────────

  /// Position [size] so it sits centred on the canvas. Used by the
  /// document-centred quick-add path (`addCenteredText`); the live
  /// composer flow places around the visible-viewport anchor instead
  /// (ux-audit P2-12 — see `ViewportController.insertPositionFor`).
  static Offset centerOnCanvas(Size size, EditorDocument doc) =>
      Offset(doc.width / 2 - size.width / 2, doc.height / 2 - size.height / 2);

  /// Decide the final ([TextResizeMode], [Size]) for a brand-new
  /// text layer being committed with [content] / [style] onto [doc].
  ///
  /// Rule: if the content's natural unwrapped width fits within the
  /// new-layer wrap cap, keep the layer in [TextResizeMode.scaleText]
  /// so corner-drag scales the single-line snug box (Canva sticker
  /// behaviour). If the content is long enough that it had to wrap
  /// during the live preview, promote it to [TextResizeMode.resizeBox]
  /// at the wrap-cap width so corner-drag re-wraps the paragraph
  /// instead of scaling a frozen wrapped layout (Canva paragraph
  /// behaviour). This keeps each mode's semantics clean and matches
  /// how Keynote / Pages decide between "text label" and "text
  /// frame" on the first commit.
  static ({TextResizeMode mode, Size size}) resolveNewLayerLayout(
    String content,
    TextStyleSpec style,
    EditorDocument doc, {
    TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  }) {
    final canvasWidth = doc.width;
    if (canvasWidth <= 0) {
      return (
        mode: TextResizeMode.scaleText,
        size: measureNaturalSize(
          content,
          style,
          textDirectionMode: textDirectionMode,
        ),
      );
    }
    final natural = measureNaturalSize(
      content,
      style,
      textDirectionMode: textDirectionMode,
    );
    final cap = canvasWidth * newLayerWrapFraction;
    if (natural.width <= cap) {
      return (mode: TextResizeMode.scaleText, size: natural);
    }
    final wrapped = measureBoxHeight(
      content,
      style,
      cap,
      textDirectionMode: textDirectionMode,
    );
    return (mode: TextResizeMode.resizeBox, size: wrapped);
  }

  /// The single representative pixel-dimension we treat the canvas
  /// as having for font-scale purposes. Delegates to
  /// [CanvasSizing.effectiveDim] so shape / sticker / text inserts
  /// all compute "what is the canvas's effective size?" the same way.
  static double effectiveCanvasDim(EditorDocument doc) =>
      CanvasSizing.effectiveDim(doc);

  /// Resolve [base] for insertion into [doc] by scaling its
  /// `fontSize` proportionally to the canvas's effective dimension.
  /// Tiny canvases get smaller default text, huge canvases get larger
  /// — the visual proportion stays constant. The result is rounded
  /// to the nearest 0.5 pt so the size shown in the slider/label
  /// reads as a clean number rather than a floating-point trail.
  ///
  /// Only `fontSize` is touched; every other field of the style
  /// (colour, weight, family, shadow…) is preserved verbatim.
  static TextStyleSpec scaleStyleToCanvas(
    TextStyleSpec base,
    EditorDocument doc,
  ) {
    final effective = effectiveCanvasDim(doc);
    if (effective <= 0) return base;
    final raw = base.fontSize * effective / _referenceCanvasSize;
    final clamped = raw.clamp(_minScaledFontSize, _maxScaledFontSize);
    // Snap to nearest 0.5 pt for clean labels in the size slider.
    final scaled = (clamped * 2).round() / 2;
    if ((scaled - base.fontSize).abs() < 0.01) return base;
    return base.copyWith(fontSize: scaled);
  }

  /// Seed [base] with the canvas-aware default drop-shadow when it
  /// has none (`shadowColor == null`). The blur and offset are
  /// scaled via [CanvasSizing.scaleDimension] so a tiny sticker
  /// canvas gets a subtle halo and a huge poster canvas gets a
  /// proportionally chunkier one — same visual presence on both.
  /// Returns [base] unchanged when a shadow is already configured;
  /// existing layers are never overwritten through this path.
  static TextStyleSpec seedDefaultShadowIfMissing(
    TextStyleSpec base,
    EditorDocument doc,
  ) {
    if (base.shadowColor != null) return base;
    final blur = CanvasSizing.scaleDimension(
      TextColorResolver.kDefaultShadowBlur,
      doc,
    );
    final offset = Offset(
      0,
      CanvasSizing.scaleDimension(referenceShadowOffsetDy, doc),
    );
    return base.copyWith(
      shadowColor: TextColorResolver.defaultShadowFor(base.color),
      shadowBlur: blur,
      shadowOffset: offset,
    );
  }
}
