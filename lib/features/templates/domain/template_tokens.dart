/// Design tokens for the templates system.
///
/// This file defines the foundational color palettes and font pairings used
/// across all templates. Templates should reference these tokens rather than
/// hard-coding colors or font families, so we can:
///
///   * keep visual identity consistent across the catalog,
///   * iterate on the system in one place, and
///   * compose new templates quickly from a known-good toolbox.
///
/// Nothing in here imports `package:flutter/material.dart` — these are pure
/// data classes safe to use anywhere (engine, codecs, tests, exporters).
library;

import 'dart:ui';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Color palettes
// ---------------------------------------------------------------------------

/// A small, semantic palette intended to fully clothe a template.
///
/// Field meanings:
///   * [background] — the dominant canvas color.
///   * [surface]    — the primary card / content surface (typically a
///                    neutral close to [background] in tone).
///   * [surfaceAlt] — an inverse / contrast surface for callouts, dark
///                    cards on light backgrounds, or accent panels.
///   * [primary]    — the main text color (high contrast against [background]).
///   * [secondary]  — muted text and supporting elements.
///   * [accent]     — highlights, CTAs, and attention moments.
///   * [decorativeColors] — optional extra hues for decorative shapes,
///                    illustrations, or accents beyond the core six roles.
///                    Defaults to an empty list when a palette doesn't need
///                    extras.
///
/// The first six fields are required so a template can rely on every slot
/// being populated; pick the closest meaning if a palette doesn't have an
/// obvious "secondary" — never leave a field null.
@immutable
class TemplatePalette {
  const TemplatePalette({
    required this.name,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.secondary,
    required this.accent,
    this.decorativeColors = const <Color>[],
  });

  final String name;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color secondary;
  final Color accent;
  final List<Color> decorativeColors;
}

/// Soft, cute, friendly. Best for greeting cards, baby/family announcements,
/// gentle quotes, and lifestyle posts that should feel warm and approachable.
const TemplatePalette warmPastel = TemplatePalette(
  name: 'Warm Pastel',
  background: Color(0xFFFAF3E7), // cream
  surface: Color(0xFFF5C7C7), // blush pink
  surfaceAlt: Color(0xFFA8B89C), // sage (inverse cards)
  primary: Color(0xFF2D2D2D), // charcoal text
  secondary: Color(0xFF8C7B6E), // muted taupe (supporting text)
  accent: Color(0xFFD89A9A), // dusty rose
);

/// Punchy, high-contrast marketing. Best for sales, promo bursts, urgent
/// announcements, and anything that needs to stop a thumb mid-scroll.
/// Templates wanting the classic "yellow-with-black-text" look should swap
/// [background] and [accent] at the call site.
const TemplatePalette boldHighContrast = TemplatePalette(
  name: 'Bold High Contrast',
  background: Color(0xFF0A0A0A), // off-black
  surface: Color(0xFFFFFFFF), // pure white (inverse cards)
  surfaceAlt: Color(0xFF1A1A1A), // dark gray
  primary: Color(0xFFFFFFFF), // white text on black
  secondary: Color(0xFF999999), // medium gray
  accent: Color(0xFFFFD60A), // bright yellow
  decorativeColors: <Color>[
    Color(0xFFE63946), // accent red — secondary punch color
  ],
);

/// Sophisticated, magazine-like. Best for quotes, long-form pull-quotes,
/// editorial covers, and anything that should feel considered and timeless.
const TemplatePalette editorialMuted = TemplatePalette(
  name: 'Editorial Muted',
  background: Color(0xFFF5F1EB), // off-white
  surface: Color(0xFFDDD7CC), // warm gray neutral
  surfaceAlt: Color(0xFF1F3A5F), // navy (inverse callouts)
  primary: Color(0xFF2C2C2C), // charcoal text
  secondary: Color(0xFF6B6359), // warm gray
  accent: Color(0xFFC45D3A), // terracotta
);

/// Trendy violet → magenta gradient palette. Best for tech, music, fashion,
/// and any "modern / now" content. The [background] and [accent] fields are
/// the two ends of the canonical gradient — render them as a linear gradient
/// when a template wants a gradient surface, or use [background] as a solid
/// when it wants a flat fill.
const TemplatePalette modernGradient = TemplatePalette(
  name: 'Modern Gradient',
  background: Color(0xFF7C5CFF), // violet (gradient start)
  surface: Color(0xFFE8DFFF), // light lavender
  surfaceAlt: Color(0xFF2D1B4E), // deep purple (inverse panels)
  primary: Color(0xFFFFFFFF), // pure white text
  secondary: Color(0xFFB8A8E8), // soft lilac (supporting text)
  accent: Color(0xFFE85DDC), // magenta (gradient end)
);

/// Retro warmth — 70s record sleeve, vintage poster. Best for nostalgia,
/// food/coffee content, lo-fi music covers, and anything seasonal/autumnal.
const TemplatePalette vintageFaded = TemplatePalette(
  name: 'Vintage Faded',
  background: Color(0xFFF5E8D0), // cream
  surface: Color(0xFFE8D5B0), // deeper cream (cards)
  surfaceAlt: Color(0xFF5C4033), // sepia brown (inverse cards)
  primary: Color(0xFF3D2A1F), // deep sepia text
  secondary: Color(0xFF8B6F47), // warm brown (muted body text)
  accent: Color(0xFFD4A24C), // mustard — vintage signature
  decorativeColors: <Color>[
    Color(0xFFC8633A), // burnt orange
    Color(0xFF6B8E8A), // dusty teal
  ],
);

/// Convenience list of all palettes in their canonical display order.
const List<TemplatePalette> kTemplatePalettes = <TemplatePalette>[
  warmPastel,
  boldHighContrast,
  editorialMuted,
  modernGradient,
  vintageFaded,
];

// ---------------------------------------------------------------------------
// Font pairings
// ---------------------------------------------------------------------------

/// A font pairing recommends a display + body family along with the weights
/// that best embody the pairing's character.
///
/// Weights are exposed as integers (100..900) rather than `FontWeight` so this
/// file stays free of `package:flutter/material.dart`. Convert at the call
/// site with `FontWeight.values[(weight ~/ 100) - 1]` or via a helper.
@immutable
class TemplateFontPairing {
  const TemplateFontPairing({
    required this.name,
    required this.displayFont,
    required this.bodyFont,
    required this.displayWeight,
    required this.bodyWeight,
    required this.notes,
  });

  final String name;

  /// Family name as registered in `pubspec.yaml`.
  final String displayFont;

  /// Family name as registered in `pubspec.yaml`.
  final String bodyFont;

  /// Recommended weight for the display font (100..900).
  final int displayWeight;

  /// Recommended weight for the body font (100..900).
  final int bodyWeight;

  /// One-line guidance on when to reach for this pairing.
  final String notes;
}

/// Refined, magazine-style. Use for quotes, articles, gallery captions, and
/// any content that should feel considered and editorial.
const TemplateFontPairing editorialSerifSans = TemplateFontPairing(
  name: 'Editorial Serif/Sans',
  displayFont: 'Playfair_Display',
  bodyFont: 'Hanken_Grotesk',
  displayWeight: 700,
  bodyWeight: 400,
  notes: 'Quotes, articles, and sophisticated long-form content.',
);

/// Heavy display + clean sans body. Use for sales, promos, event posters,
/// and anything that needs to shout the headline and whisper the details.
const TemplateFontPairing boldDisplay = TemplateFontPairing(
  name: 'Bold Display',
  displayFont: 'Bungee_Shade',
  bodyFont: 'Hanken_Grotesk',
  displayWeight: 400,
  bodyWeight: 500,
  notes: 'Marketing, sales, promos — headline-first compositions.',
);

/// Friendly script + crisp geometric sans. Use for greetings, birthdays,
/// celebrations, thank-you notes, and personal/handwritten moments.
const TemplateFontPairing scriptModern = TemplateFontPairing(
  name: 'Script Modern',
  displayFont: 'Dancing_Script',
  bodyFont: 'Josefin_Sans',
  displayWeight: 600,
  bodyWeight: 400,
  notes: 'Greetings, celebrations, and personal messages.',
);

/// Persian calligraphy + modern Persian sans. Use for Farsi quotes, poetic
/// content, religious/seasonal cards, and anything that should feel rooted
/// in Persian typographic tradition while remaining legible.
const TemplateFontPairing persianClassic = TemplateFontPairing(
  name: 'Persian Classic',
  displayFont: 'IranNastaliq',
  bodyFont: 'Shabnam',
  displayWeight: 400,
  bodyWeight: 400,
  notes: 'Persian poetry, quotes, and culturally-rooted compositions.',
);

/// Convenience list of all pairings in their canonical display order.
const List<TemplateFontPairing> kTemplateFontPairings = <TemplateFontPairing>[
  editorialSerifSans,
  boldDisplay,
  scriptModern,
  persianClassic,
];
