import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/modules/text/text_direction_utils.dart';
import '../../engine/modules/text/text_style_spec.dart';
import 'font_catalog.dart';

// Script-detection + writing-direction helpers used to live here.
// They moved into the engine (text_direction_utils.dart) so
// `TextLayer`'s render path can resolve `TextDirection` without
// reaching into application/domain code. Re-exported here so the
// presentation/application call sites that have always imported
// these names from this file continue to compile unchanged.
export '../../engine/modules/text/text_direction_utils.dart'
    show textIsArabicScript, textDirectionForContent;

/// One-tap *visual* style for a text layer.
///
/// A preset describes look-only attributes — colour, background,
/// border, shadow, decoration — and is applied via
/// [TextToolController.applyStylePreset]. The controller is careful
/// to **never** change the layer's `fontFamily`, `fontSize`,
/// `letterSpacing`, `lineHeight`, content, position, rotation, or
/// bounding box — Styles are purely cosmetic. Font / size belong to
/// their own tools; Styles never overrides what the user picked
/// there.
///
/// To add a new preset: append a `TextStylePreset(...)` literal to
/// [kTextStylePresets]. Keep specs minimal — leave any field you
/// don't intentionally want to change at its default. The
/// controller will only apply the visual subset (`color`,
/// `backgroundColor` + radius/padding, `outlineColor` + width,
/// `shadowColor` + blur/offset, `fontWeight`, `italic`, `underline`).
///
/// Each preset belongs to exactly one [TextStylePresetCategory] —
/// an *internal* taxonomy used by [recommendedPresets] to surface
/// context-appropriate styles in the Recommended row. The category
/// is intentionally not exposed in the UI yet; it's a building
/// block, not a feature.

/// Use-case bucket for a [TextStylePreset]. Drives the Recommended
/// row's heuristic ranking — never shown directly in the UI.
enum TextStylePresetCategory {
  /// Highlight / draw attention to important words (highlights,
  /// strong, underline).
  emphasis,

  /// Maximises legibility on busy or photographic backgrounds
  /// (shadows, contrasting fills, semi-transparent plates).
  readability,

  /// Tags, mentions, calls-to-action — pill / chip shapes.
  social,

  /// Showy, expressive looks (neon, poster, outline).
  decorative,

  /// Quiet, low-key looks (mute, subtle border, soft italic).
  minimal,
}

@immutable
class TextStylePreset {
  const TextStylePreset({
    required this.id,
    required this.name,
    required this.spec,
    required this.category,
    this.recommended = false,
  });

  /// Stable id used by tests + selected-state highlight.
  final String id;

  /// Short, human display label (e.g. "Classic", "Badge", "Neon").
  /// This is the *primary* label shown on the chip — no preview
  /// glyphs.
  final String name;

  /// Visual style applied on tap. Only the visual subset is read by
  /// the controller; metric fields are intentionally ignored.
  final TextStyleSpec spec;

  /// Use-case bucket. Drives [recommendedPresets] only — not shown
  /// in the UI.
  final TextStylePresetCategory category;

  /// Static "safe pick" hint — used as the fallback Recommended
  /// list when no contextual signals are available.
  final bool recommended;
}

// ─── Curated visual presets ──────────────────────────────────────
//
// Names are short product nouns the user can match to a vibe at a
// glance — no "Hello" preview text needed. Specs intentionally
// avoid `fontFamily`, `fontSize`, `letterSpacing`, `lineHeight`
// since the controller drops those anyway; leaving them out keeps
// the data honest and the swatch preview accurate.

const List<TextStylePreset> kTextStylePresets = <TextStylePreset>[
  // ── Minimal (the default) ─────────────────────────────────────
  TextStylePreset(
    id: 'classic',
    name: 'Classic',
    recommended: true,
    category: TextStylePresetCategory.minimal,
    spec: TextStyleSpec(
      color: Color(0xFF111111),
    ),
  ),
  TextStylePreset(
    id: 'quote',
    name: 'Quote',
    category: TextStylePresetCategory.minimal,
    spec: TextStyleSpec(
      color: Color(0xFF1F2937),
      italic: true,
    ),
  ),

  // ── Emphasis ──────────────────────────────────────────────────
  TextStylePreset(
    id: 'highlight',
    name: 'Highlight',
    recommended: true,
    category: TextStylePresetCategory.emphasis,
    spec: TextStyleSpec(
      color: Color(0xFF111111),
      backgroundColor: Color(0xFFFEF08A),
      backgroundRadius: 0.15,
      backgroundPaddingX: 10,
      backgroundPaddingY: 4,
      fontWeight: FontWeight.w700,
    ),
  ),

  // ── Readability (photo-friendly) ──────────────────────────────
  TextStylePreset(
    id: 'shadow_soft',
    name: 'Shadow',
    recommended: true,
    category: TextStylePresetCategory.readability,
    spec: TextStyleSpec(
      color: Color(0xFFFFFFFF),
      shadowColor: Color(0x99000000),
      shadowBlur: 14,
      shadowOffset: Offset(0, 2),
      fontWeight: FontWeight.w700,
    ),
  ),
  TextStylePreset(
    id: 'contrast',
    name: 'Contrast',
    category: TextStylePresetCategory.readability,
    spec: TextStyleSpec(
      color: Color(0xFFFFFFFF),
      backgroundColor: Color(0xFF111111),
      backgroundRadius: 0.2,
      backgroundPaddingX: 14,
      backgroundPaddingY: 8,
      fontWeight: FontWeight.w700,
    ),
  ),
  TextStylePreset(
    id: 'glass',
    name: 'Glass',
    category: TextStylePresetCategory.readability,
    spec: TextStyleSpec(
      color: Color(0xFFFFFFFF),
      backgroundColor: Color(0x66000000),
      backgroundRadius: 0.4,
      backgroundPaddingX: 14,
      backgroundPaddingY: 8,
      fontWeight: FontWeight.w600,
    ),
  ),
  // Premium video-caption look: white text on a soft dark plate
  // with a subtle drop shadow. Pairs well with Reels / Shorts.
  TextStylePreset(
    id: 'caption',
    name: 'Caption',
    category: TextStylePresetCategory.readability,
    spec: TextStyleSpec(
      color: Color(0xFFFFFFFF),
      backgroundColor: Color(0xCC0F172A),
      backgroundRadius: 0.35,
      backgroundPaddingX: 14,
      backgroundPaddingY: 8,
      shadowColor: Color(0x66000000),
      shadowBlur: 10,
      shadowOffset: Offset(0, 1),
      fontWeight: FontWeight.w600,
    ),
  ),
  // TV-subtitle band: full-width black bar feel via tight padding,
  // square corners, hard contrast. Universal "always readable".
  TextStylePreset(
    id: 'subtitle_band',
    name: 'Subtitle',
    category: TextStylePresetCategory.readability,
    spec: TextStyleSpec(
      color: Color(0xFFFFFFFF),
      backgroundColor: Color(0xFF000000),
      backgroundRadius: 0.0,
      backgroundPaddingX: 12,
      backgroundPaddingY: 6,
      fontWeight: FontWeight.w700,
    ),
  ),

  // ── Social (action / chip / badge) ────────────────────────────
  TextStylePreset(
    id: 'cta',
    name: 'CTA',
    recommended: true,
    category: TextStylePresetCategory.social,
    spec: TextStyleSpec(
      color: Color(0xFFFFFFFF),
      backgroundColor: Color(0xFF111111),
      backgroundRadius: 1.0,
      backgroundPaddingX: 22,
      backgroundPaddingY: 12,
      fontWeight: FontWeight.w800,
    ),
  ),
  TextStylePreset(
    id: 'badge_red',
    name: 'Badge',
    category: TextStylePresetCategory.social,
    spec: TextStyleSpec(
      color: Color(0xFFFFFFFF),
      backgroundColor: Color(0xFFEF4444),
      backgroundRadius: 1.0,
      backgroundPaddingX: 18,
      backgroundPaddingY: 10,
      fontWeight: FontWeight.w700,
    ),
  ),
  // #-hashtag chip — soft violet pill, social-app feel.
  TextStylePreset(
    id: 'hashtag',
    name: 'Hashtag',
    category: TextStylePresetCategory.social,
    spec: TextStyleSpec(
      color: Color(0xFF6D28D9),
      backgroundColor: Color(0xFFEDE9FE),
      backgroundRadius: 1.0,
      backgroundPaddingX: 12,
      backgroundPaddingY: 6,
      fontWeight: FontWeight.w700,
    ),
  ),

  // ── Decorative (showy) ────────────────────────────────────────
  TextStylePreset(
    id: 'outline',
    name: 'Outline',
    category: TextStylePresetCategory.decorative,
    spec: TextStyleSpec(
      color: Color(0xFFFFFFFF),
      outlineColor: Color(0xFF000000),
      outlineWidth: 3,
      fontWeight: FontWeight.w800,
    ),
  ),
  TextStylePreset(
    id: 'neon',
    name: 'Neon',
    category: TextStylePresetCategory.decorative,
    spec: TextStyleSpec(
      color: Color(0xFFFEFEFE),
      shadowColor: Color(0xFF22D3EE),
      shadowBlur: 24,
      shadowOffset: Offset.zero,
      fontWeight: FontWeight.w700,
    ),
  ),
  TextStylePreset(
    id: 'poster',
    name: 'Poster',
    category: TextStylePresetCategory.decorative,
    spec: TextStyleSpec(
      color: Color(0xFF111111),
      backgroundColor: Color(0xFFFACC15),
      backgroundRadius: 0.1,
      backgroundPaddingX: 14,
      backgroundPaddingY: 6,
      fontWeight: FontWeight.w900,
    ),
  ),
  // Sticker bookmark: thick white outline + soft shadow lifts text
  // off any photo — the IG-story sticker look. Outline at 4px so
  // Flutter's centre-aligned stroke doesn't collapse glyph interiors.
  TextStylePreset(
    id: 'sticker',
    name: 'Sticker',
    category: TextStylePresetCategory.decorative,
    spec: TextStyleSpec(
      color: Color(0xFF111111),
      outlineColor: Color(0xFFFFFFFF),
      outlineWidth: 4,
      shadowColor: Color(0x66000000),
      shadowBlur: 16,
      shadowOffset: Offset(0, 4),
      fontWeight: FontWeight.w900,
    ),
  ),
  // Pop / 3D drop: hard offset solid shadow with zero blur. Comic /
  // poster pop — dimensional, very legible on busy photos because
  // the offset shape itself acts as an outline.
  TextStylePreset(
    id: 'pop_3d',
    name: 'Pop',
    category: TextStylePresetCategory.decorative,
    spec: TextStyleSpec(
      color: Color(0xFFFFFFFF),
      shadowColor: Color(0xFF111111),
      shadowBlur: 0,
      shadowOffset: Offset(4, 4),
      fontWeight: FontWeight.w900,
    ),
  ),
];

/// Backward-compatible alias — older call sites use the "all" name.
/// Prefer [kTextStylePresets] in new code.
List<TextStylePreset> get kAllTextStylePresets => kTextStylePresets;

/// Lookup by id. Returns `null` for unknown ids (e.g. presets that
/// existed in an older build of the app).
TextStylePreset? textStylePresetById(String id) {
  for (final p in kTextStylePresets) {
    if (p.id == id) return p;
  }
  return null;
}

// ─── default-font helpers (text creation only) ───────────────────
//
// These power the "new text gets a sensible default font for its
// script" rule. Never used by the Styles sheet — Styles is purely
// visual and must not touch font family.

/// Default font family for freshly-typed text, picked by script:
///   * Arabic / Persian → Vazir (`Vazir_Regular`)
///   * Latin / fallback → Roboto
///
/// Used by the controller at the moment of text creation so a brand-
/// new layer ships with a font that actually shapes the user's
/// content. After creation the font is fully under user control via
/// the Font tool — Styles never overrides it.
String defaultFontFamilyForContent(String content) {
  // Sanity check the catalog is wired correctly. Falls back to a
  // hard-coded family if the entry was renamed.
  String pick(String preferred) {
    for (final entry in kFontCatalog) {
      if (entry.family == preferred) return entry.family;
    }
    return preferred;
  }

  return textIsArabicScript(content)
      ? pick('Vazir_Regular')
      : pick('Roboto');
}

/// True when [family] is one of the two auto-defaults the controller
/// assigns based on script. Used so we only re-pick the font on edit
/// when the user hasn't explicitly chosen something else.
bool isAutoDefaultFontFamily(String? family) {
  return family == 'Vazir_Regular' || family == 'Roboto';
}

/// Merge the visual subset of [preset] onto [current], preserving
/// every metric-affecting field (`fontFamily`, `fontSize`,
/// `letterSpacing`, `lineHeight`, `alignment`) and content-flow
/// state. This is exactly the projection the controller applies on
/// `applyStylePreset` — exposed here so the UI can compute "is this
/// preset currently active?" using the same rule.
TextStyleSpec mergePresetVisual({
  required TextStyleSpec current,
  required TextStyleSpec preset,
}) {
  return current.copyWith(
    color: preset.color,
    fontWeight: preset.fontWeight,
    italic: preset.italic,
    underline: preset.underline,
    // Background: presets either set it or expect "no background".
    // Always sync the full background block (color + radius + pad).
    backgroundColor: preset.backgroundColor,
    clearBackground: preset.backgroundColor == null,
    backgroundRadius: preset.backgroundRadius,
    backgroundPaddingX: preset.backgroundPaddingX,
    backgroundPaddingY: preset.backgroundPaddingY,
    // Outline: same semantics — set or clear.
    outlineColor: preset.outlineColor,
    clearOutline: preset.outlineColor == null,
    outlineWidth: preset.outlineWidth,
    // Shadow: same semantics — set or clear.
    shadowColor: preset.shadowColor,
    clearShadow: preset.shadowColor == null,
    shadowBlur: preset.shadowBlur,
    shadowOffset: preset.shadowOffset,
  );
}

// ─── Recommended-row heuristics ──────────────────────────────────
//
// The Recommended row used to be a static list (presets flagged
// `recommended: true`). It is now picked at build-time from a few
// cheap signals about the current layer:
//
//   * canvas background (light vs dark) — drives whether we lean
//     into "dark text + highlight" or "light text + glow"
//   * font size (small vs large) — small text wants legibility
//     helpers (shadow, plate); large text invites decorative looks
//   * fresh layer — the user just typed; show the "safe trio"
//     (Classic, Highlight, Badge) so the first interaction is
//     instantly rewarding
//
// All scoring is plain arithmetic; the function is O(presets) and
// allocation-free aside from the result list.

/// Approximate WCAG luminance of [c] in the range [0, 1]. Uses the
/// same formula as [_StylePreviewTile] in the toolbar — kept local
/// so this file has no UI dependency.
double _presetLuminance(Color c) {
  double channel(double v) => v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// True when [style] looks like a brand-new layer — default text
/// colour, no fill / outline / shadow yet. The controller doesn't
/// expose a "fresh" flag, so we infer it from the style itself.
bool _isFreshTextStyle(TextStyleSpec style) {
  const defaults = TextStyleSpec();
  return style.color == defaults.color &&
      style.backgroundColor == null &&
      style.outlineColor == null &&
      style.shadowColor == null &&
      style.fontWeight == defaults.fontWeight &&
      !style.italic &&
      !style.underline;
}

/// Returns the styles to surface in the "Recommended" row, ranked
/// by simple use-case heuristics derived from the current layer.
///
/// * [layerStyle] — the layer's full visual state (drives the
///   fresh-layer detector and the inferred text-on-light vs
///   text-on-dark hint).
/// * [canvasBackground] — solid backdrop the text sits on. Defaults
///   to white because that's the document's default fill; callers
///   that know better (e.g. background image extractor) can pass
///   the dominant colour they computed.
/// * [maxResults] — soft cap on the row length; defaults to 6 so
///   the row stays scannable on phones.
///
/// Falls back to the static `recommended: true` set when no signals
/// fire (defensive — the function still returns a sensible row even
/// if a caller passes garbage).
List<TextStylePreset> recommendedPresets({
  required TextStyleSpec layerStyle,
  Color canvasBackground = const Color(0xFFFFFFFF),
  int maxResults = 6,
}) {
  final picks = <String>[];
  void add(String id) {
    if (!picks.contains(id) && textStylePresetById(id) != null) {
      picks.add(id);
    }
  }

  // Fresh layer → safe trio first. The user just typed; we want the
  // first three chips to be obviously useful, not exotic.
  if (_isFreshTextStyle(layerStyle)) {
    add('classic');
    add('highlight');
    add('badge_red');
  }

  // Background-driven picks. Light canvas → dark-on-light + a punchy
  // highlight + a soft shadow for hero text. Dark canvas → light text
  // with glow / outline so it stays readable.
  final bgIsLight = _presetLuminance(canvasBackground) >= 0.5;
  if (bgIsLight) {
    add('contrast');
    add('shadow_soft');
    add('highlight');
  } else {
    add('classic'); // dark-bg variant uses light text via overrides
    add('neon');
    add('outline');
    add('sticker'); // photo-friendly white halo on dark bg
  }

  // Font-size driven picks. Thresholds are eyeballed against the
  // default 96pt and the typical small-caption range (~24–32pt).
  if (layerStyle.fontSize <= 32) {
    // Small text on busy bg: caption-style plates beat plain shadow.
    add('caption');
    add('subtitle_band');
    add('shadow_soft');
    add('glass');
    add('contrast');
  } else if (layerStyle.fontSize >= 120) {
    add('neon');
    add('poster');
    add('outline');
    add('pop_3d'); // dimensional treatment shines at hero sizes
  }

  // Resolve ids → presets, drop any that vanished, cap length.
  final resolved = <TextStylePreset>[
    for (final id in picks)
      if (textStylePresetById(id) != null) textStylePresetById(id)!,
  ];
  if (resolved.isEmpty) {
    // Defensive fallback — should never happen in practice.
    return kTextStylePresets
        .where((p) => p.recommended)
        .toList(growable: false);
  }
  return resolved.take(maxResults).toList(growable: false);
}

/// Returns the **full** preset catalogue ordered for the single-row
/// Styles panel: contextually-ranked recommendations come first
/// (so the most useful chips for the current layer are visible
/// without scrolling), followed by the rest of the catalogue in
/// definition order. There is no "More styles" disclosure — this
/// single ordered list is the entire UX surface.
///
/// Stable across rebuilds for the same inputs (preserves catalogue
/// order for the tail) so chips don't shuffle around as the user
/// edits the layer.
List<TextStylePreset> orderedTextStylePresets({
  required TextStyleSpec layerStyle,
  Color canvasBackground = const Color(0xFFFFFFFF),
}) {
  final recs = recommendedPresets(
    layerStyle: layerStyle,
    canvasBackground: canvasBackground,
    // Cap the "front" of the row at a sensible 4 — beyond that the
    // user is genuinely browsing, not picking a recommendation.
    maxResults: 4,
  );
  final headIds = {for (final p in recs) p.id};
  return <TextStylePreset>[
    ...recs,
    for (final p in kTextStylePresets)
      if (!headIds.contains(p.id)) p,
  ];
}
