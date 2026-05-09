import 'dart:math' as math;
import 'dart:ui';

import '../../engine/core/editor_document.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/modules/image/image_layer.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../../engine/modules/shape/shape_layer.dart';

/// Smart-default text colour for newly inserted text layers.
///
/// Problem: the editor's default `TextStyleSpec.color` is white. On a
/// white canvas (or under a white shape) brand-new text is invisible
/// — and the same happens for users that style their default to black
/// over a black background.
///
/// Solution: sample what the new text will sit on top of, then either
/// keep the user's chosen colour (if it's already readable) or swap it
/// for whichever of black / white reads best. The user's intent wins
/// whenever it's *legible*; we only override when text would be
/// invisible.
///
/// This is deliberately a small, pure module so it is trivially
/// testable and has no Riverpod / widget dependencies.
class TextColorResolver {
  const TextColorResolver._();

  /// The fallback canvas backdrop used when no opaque layer covers the
  /// target rect. Matches `DocumentView.background` in
  /// `lib/features/editor/engine/rendering/document_view.dart`.
  static const Color kCanvasFill = Color(0xFFFFFFFF);

  /// WCAG contrast ratio below which we treat the requested colour as
  /// unreadable and force a black/white override. 3.0 is the
  /// "AA Large Text" floor — anything dimmer reads as a faint smudge
  /// at typical caption sizes.
  static const double kMinContrast = 3.0;

  /// Near-black we prefer over pure `0xFF000000` for hero text — has
  /// just enough warmth to feel printed rather than digital noise.
  static const Color kHighContrastDark = Color(0xFF111111);
  static const Color kHighContrastLight = Color(0xFFFFFFFF);

  /// Returns a colour to use for a new text layer at [targetRect] in
  /// [doc]. Preserves [requested] when readable; otherwise returns the
  /// black/white that maximises contrast against the sampled
  /// background.
  ///
  /// [canvasFill] overrides the assumed canvas backdrop (defaults to
  /// the editor's white). Tests use this to simulate a black canvas.
  static Color resolve({
    required Color requested,
    required EditorDocument doc,
    required Rect targetRect,
    Color canvasFill = kCanvasFill,
  }) {
    final bg = sampleBackground(
      doc: doc,
      targetRect: targetRect,
      canvasFill: canvasFill,
    );
    if (bg == null) {
      // Topmost cover is an image / unknown — we can't compute a safe
      // contrast. Leave the user's choice alone.
      return requested;
    }
    if (_contrastRatio(requested, bg) >= kMinContrast) return requested;
    return _bestContrast(bg);
  }

  /// Returns the representative colour of the topmost opaque layer
  /// whose bounding rect covers [targetRect]'s centre, or [canvasFill]
  /// if no such layer is found.
  ///
  /// Returns `null` when the topmost cover is an image (or any layer
  /// we cannot summarise as a single colour) — callers should treat
  /// this as "unknown" and skip the auto-pick rather than guess.
  static Color? sampleBackground({
    required EditorDocument doc,
    required Rect targetRect,
    Color canvasFill = kCanvasFill,
  }) {
    final centre = targetRect.center;
    // Walk top-down so the front-most layer wins.
    for (var i = doc.layers.length - 1; i >= 0; i--) {
      final layer = doc.layers[i];
      if (!layer.visible) continue;
      final bounds = _axisAlignedBounds(layer);
      if (!bounds.contains(centre)) continue;
      final summary = _representativeColor(layer);
      if (summary == _Unknown.instance) return null;
      if (summary is Color && summary.a >= 0.95) return summary;
      // Translucent layer: keep walking — the colour beneath leaks
      // through, so the next-down layer is the dominant background.
    }
    return canvasFill;
  }

  /// Axis-aligned bounding rect of [layer]. Rotation is ignored
  /// — for the sampler's purpose the AABB is a safe over-estimate of
  /// "what the centre of the new text might overlap".
  static Rect _axisAlignedBounds(EditorLayer layer) =>
      layer.transform.position & layer.transform.size;

  /// Single-colour summary of [layer] for contrast purposes, or
  /// [_Unknown] when the layer has no representative flat colour
  /// (images, etc.).
  static Object _representativeColor(EditorLayer layer) {
    if (layer is ShapeLayer) return layer.fillColor;
    if (layer is PaintLayer) {
      // Filled primitives (rectangle/circle/hexagon/polygon) cover
      // their bbox with [fillColor]; for stroke-only kinds the
      // [strokeColor] is the only paint that lands on canvas, so we
      // use it as the representative even though coverage is partial
      // — better than guessing white.
      return layer.fillColor ?? layer.strokeColor;
    }
    if (layer is ImageLayer) return _Unknown.instance;
    // Text and unknown future layer types: ignore (text can sit on
    // text without contrast issues; unknown types stay safe).
    return _Skip.instance;
  }

  /// WCAG 2.1 relative luminance of a colour, treating it as opaque
  /// sRGB. Alpha is ignored — callers filter translucent layers out
  /// before reaching this.
  static double _luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    final r = channel(c.r);
    final g = channel(c.g);
    final b = channel(c.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// WCAG 2.1 contrast ratio between two opaque colours (1.0–21.0).
  static double _contrastRatio(Color a, Color b) {
    final la = _luminance(a);
    final lb = _luminance(b);
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Pick black or white — whichever yields the higher contrast vs
  /// [bg]. Ties go to dark text (matches platform conventions: iOS
  /// notes, Google Docs all default to dark).
  static Color _bestContrast(Color bg) {
    final dark = _contrastRatio(kHighContrastDark, bg);
    final light = _contrastRatio(kHighContrastLight, bg);
    return light > dark ? kHighContrastLight : kHighContrastDark;
  }

  // -----------------------------------------------------------------
  // Default-shadow helper.
  // -----------------------------------------------------------------

  /// Default shadow alpha for a freshly inserted text layer. 40%
  /// reads as a soft halo over photos / busy backgrounds without
  /// looking like the user explicitly pushed the shadow slider.
  static const int kDefaultShadowAlpha = 0x66;

  /// Subtle blur for the auto-applied default shadow. Distinct from
  /// the "Shadow" preset (blur 14) so users can immediately see the
  /// difference between "default" and "explicit drop shadow".
  static const double kDefaultShadowBlur = 6.0;

  /// Slight downward offset — same convention as the Shadow preset
  /// and matches macOS / iOS text-shadow defaults.
  static const Offset kDefaultShadowOffset = Offset(0, 2);

  /// Pick a subtle drop-shadow colour for text rendered in
  /// [textColor]. The shadow is the **opposite** luminance of the
  /// text so it always reads as a halo, never as a colour bleed:
  ///
  ///   * Light text (luminance > 0.5)  -> translucent black.
  ///   * Dark / mid-tone text          -> translucent white.
  ///
  /// Alpha is fixed at [kDefaultShadowAlpha] so the shadow stays
  /// "always subtle". Callers combine this with
  /// [kDefaultShadowBlur] / [kDefaultShadowOffset] to populate a
  /// [TextStyleSpec]'s shadow fields.
  static Color defaultShadowFor(Color textColor) {
    final lum = _luminance(textColor);
    final base = lum > 0.5 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    return Color.from(
      alpha: kDefaultShadowAlpha / 255.0,
      red: base.r,
      green: base.g,
      blue: base.b,
    );
  }
}

/// Sentinel: layer cannot be summarised (images, etc.). Sampler must
/// treat this as "unknown" and bail out instead of falling through to
/// the canvas fill.
class _Unknown {
  const _Unknown._();
  static const _Unknown instance = _Unknown._();
}

/// Sentinel: layer should be ignored by the sampler (text layers,
/// future layer kinds without a colour).
class _Skip {
  const _Skip._();
  static const _Skip instance = _Skip._();
}
