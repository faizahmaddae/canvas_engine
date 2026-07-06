// Styles panel (Phase 2A commit 3): extracted verbatim from the
// text_mode_toolbar part-file library (text_style_browser.dart +
// text_decoration_panels.dart). Rename-only promotions for the
// symbols the library consumes; everything else stays private.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/haptics.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../l10n/l10n.dart';
import '../../../../color_picker/presentation/color_picker_sheet.dart';
import '../../../application/recent_colors_controller.dart';
import '../../../ui/editor_slider_row.dart';
import '../../../ui/panel_direction_pad.dart';
import '../../widgets/controls/panel_chip.dart';
import '../../widgets/controls/section_label.dart';
import '../../widgets/controls/slider_row.dart';
import '../../widgets/inline_color_body.dart';
import 'precision/shadow_precision.dart';
import '../../../text/application/text_tool_controller.dart';
import '../../../text/domain/text_style_presets.dart';
import '../../../engine/modules/text/text_layer.dart';
import '../../widgets/panel_option_tile.dart';

// ─── Styles sheet body ──────────────────────────────────────────
//
// One compact horizontal row of style chips — no "More styles"
// disclosure, no split sections, no expanded second row. The
// catalogue is small and curated; every preset rides the same
// scrollable rail with the contextually-recommended ones sorted
// to the front so the most useful chips appear without scrolling.
//
// Each chip is a small "Aa" preview tile rendered with the preset's
// actual visual treatment (text colour, background fill + radius +
// padding, outline, shadow / glow, weight / italic / underline),
// with the style name beneath it. The "Aa" lets the user recognise
// the look at a glance without needing to read sample text.
//
// Tap calls [TextToolController.applyStylePreset] which merges
// only the visual subset — fontFamily, fontSize, content,
// position, rotation, and the bounding box are all preserved.

class StylesBody extends ConsumerStatefulWidget {
  const StylesBody({super.key, required this.layer});

  final TextLayer layer;

  @override
  ConsumerState<StylesBody> createState() => _StylesBodyState();
}

/// Effect categories offered below the preset rail (text-tool
/// redesign §3, "Style & Effects"). Only [shadow] is wired today —
/// the rest render as visibly disabled chips so the grammar (and the
/// user's mental map) is already in place when they land.
enum _EffectCategory { stroke, shadow, glow, background, gradient }

class _StylesBodyState extends ConsumerState<StylesBody> {
  /// Open effect sub-section. Panel-local by design: closing the
  /// sheet resets to the collapsed presets-only view.
  _EffectCategory? _openEffect;

  /// Active chip highlight: a preset is "current" iff merging its
  /// visual subset onto the layer's style is a no-op. Same merge
  /// rule the controller uses on apply.
  String? _matchPresetId(TextStyleSpec style) {
    for (final p in kTextStylePresets) {
      final merged = mergePresetVisual(current: style, preset: p.spec);
      if (merged == style) return p.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.layer;
    final ctrl = ref.read(textToolControllerProvider.notifier);
    void apply(TextStylePreset p) {
      // Haptics fire at the tile (kit convention) — not here.
      ctrl.applyStylePreset(p.spec);
    }

    final activeId = _matchPresetId(layer.style);
    // Single sorted row: recommended-first, rest in catalogue
    // order. No "More styles" button — the curated list is short
    // enough to scroll comfortably.
    final presets = orderedTextStylePresets(layerStyle: layer.style);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _StylesRow(
            presets: presets,
            activeId: activeId,
            onPick: apply,
          ),
        ),
        const SizedBox(height: 10),
        _EffectChipsRow(
          open: _openEffect,
          onToggle: (c) =>
              setState(() => _openEffect = _openEffect == c ? null : c),
        ),
        // Sub-section area — grows/collapses under the chips.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _openEffect == _EffectCategory.shadow
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _ShadowEffectSection(layer: layer),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// Category chips: خط دور · سایه · درخشش · زمینه · گرادیان. Only
/// Shadow is interactive this step; the others are rendered at
/// reduced opacity behind an [IgnorePointer] so the vocabulary is
/// visible but honestly inert until each lands.
class _EffectChipsRow extends StatelessWidget {
  const _EffectChipsRow({required this.open, required this.onToggle});

  final _EffectCategory? open;
  final ValueChanged<_EffectCategory> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget chip(_EffectCategory c, String label, {bool enabled = false}) {
      final child = LayoutPresetChip(
        label: label,
        selected: open == c,
        onTap: () => onToggle(c),
      );
      if (enabled) return child;
      return Opacity(opacity: 0.38, child: IgnorePointer(child: child));
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          chip(_EffectCategory.stroke, l10n.effectStrokeLabel),
          const SizedBox(width: 6),
          chip(_EffectCategory.shadow, l10n.shadowTool, enabled: true),
          const SizedBox(width: 6),
          chip(_EffectCategory.glow, l10n.glowOption),
          const SizedBox(width: 6),
          chip(_EffectCategory.background, l10n.backgroundTool),
          const SizedBox(width: 6),
          chip(_EffectCategory.gradient, l10n.effectGradientLabel),
        ],
      ),
    );
  }
}

/// The wired سایه sub-section: colour (the shared compact colour
/// control) + distance/blur sliders + direction pad — all on the
/// shared kit, all writing through the same drag-coalesced
/// controller setters the Shadow tile panel uses, so undo behaviour
/// is identical from either entry point.
class _ShadowEffectSection extends ConsumerWidget {
  const _ShadowEffectSection({required this.layer});

  final TextLayer layer;

  /// Distance slider ceiling. Matches the direction pad's clamp so
  /// the two controls can never fight over the offset magnitude.
  static const double _maxDistance = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasShadow = style.shadowColor != null;
    final labelStyle = flatSliderLabelStyle(context);
    final readoutStyle = flatSliderReadoutStyle(context);
    final distance = style.shadowOffset.distance.clamp(0.0, _maxDistance);

    void setDistance(double v) {
      // Preserve the current direction; a fresh (zero-ish) offset
      // falls back to straight down so the first drag reads as a
      // natural drop shadow.
      final d = style.shadowOffset.distance;
      final dir = d < 0.01
          ? const Offset(0, 1)
          : style.shadowOffset / d;
      ctrl.setShadowOffset(dir * v);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasShadow)
          // Off state: one tap on a preset enables the shadow with a
          // sensible look (same tiles as the Shadow panel — one
          // vocabulary, one behaviour).
          StyleTileRow(
            tiles: [
              for (int i = 0; i < shadowPresets.length; i++)
                StyleTile(
                  icon: shadowPresetIcons[i],
                  label: shadowPresetLabel(context.l10n, shadowPresets[i]),
                  selected: false,
                  onTap: () {
                    ctrl.setShadowEnabled(true);
                    applyShadowPreset(
                      ref,
                      shadowPresets[i],
                      baseColor: const Color(0xFF000000),
                    );
                  },
                ),
            ],
          )
        else ...[
          InlineColorBody(
            current: style.shadowColor!,
            recents: ref.watch(recentColorsControllerProvider),
            palette: kCuratedTextSwatches,
            compactRecents: true,
            onPick: (c) {
              final a = style.shadowColor?.a ?? 0.5;
              ctrl.setShadowColor(c.withValues(alpha: a));
            },
            onCustom: () async {
              final original = style.shadowColor!;
              final picked = await showColorPickerSheet(
                context,
                initial: original,
                recents: ref.read(recentColorsControllerProvider),
                onLiveChange: ctrl.setShadowColor,
                title: context.l10n.shadowColorTitle,
              );
              if (picked == null) {
                ctrl.setShadowColor(original);
                return;
              }
              ctrl.setShadowColor(picked);
              ctrl.rememberRecentColor(picked);
            },
          ),
          const SizedBox(height: 8),
          EditorSliderRow(
            label: context.l10n.distanceLabel,
            labelWidth: 96,
            value: distance.toDouble(),
            max: _maxDistance,
            format: (v) => '${v.toStringAsFixed(0)}px',
            onChanged: setDistance,
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
          EditorSliderRow(
            label: context.l10n.blurLabel,
            labelWidth: 96,
            value: style.shadowBlur,
            max: 40,
            format: (v) => '${v.toStringAsFixed(0)}px',
            onChanged: ctrl.setShadowBlur,
            onDragStart: ctrl.beginStyleDrag,
            onDragEnd: ctrl.endStyleDrag,
            haptics: EditorSliderHaptics.startTickEnd,
            labelStyle: labelStyle,
            readoutStyle: readoutStyle,
          ),
          const SizedBox(height: 4),
          PanelSectionLabel(context.l10n.directionLabel),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: 168,
              child: PanelDirectionPad(
                offset: style.shadowOffset,
                magnitude: shadowDirectionMagnitude(style.shadowOffset),
                size: 144,
                onPick: (off) {
                  EditorHaptics.toggle();
                  ctrl.setShadowOffset(off);
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}


/// Localized display name for a style preset. Keys off the stable
/// preset id (never the hardcoded English `name`, which stays as the
/// domain fallback for ids added without an l10n case).
String textStylePresetLabel(AppLocalizations l10n, TextStylePreset p) {
  return switch (p.id) {
    'classic' => l10n.stylePresetClassic,
    'quote' => l10n.stylePresetQuote,
    'highlight' => l10n.stylePresetHighlight,
    'shadow_soft' => l10n.stylePresetShadowSoft,
    'contrast' => l10n.stylePresetContrast,
    'glass' => l10n.stylePresetGlass,
    'caption' => l10n.stylePresetCaption,
    'subtitle_band' => l10n.stylePresetSubtitleBand,
    'cta' => l10n.stylePresetCta,
    'badge_red' => l10n.stylePresetBadgeRed,
    'hashtag' => l10n.stylePresetHashtag,
    'outline' => l10n.stylePresetOutline,
    'neon' => l10n.stylePresetNeon,
    'poster' => l10n.stylePresetPoster,
    'sticker' => l10n.stylePresetSticker,
    'pop_3d' => l10n.stylePresetPop3d,
    _ => p.name,
  };
}

/// Horizontal scroll list of [_StyleChip]s. Chips are 86dp tall
/// (preview tile + name + breathing room) and the row reserves a
/// uniform 16dp leading inset so the first chip never looks
/// half-clipped against the sheet edge.
class _StylesRow extends StatelessWidget {
  const _StylesRow({
    required this.presets,
    required this.activeId,
    required this.onPick,
  });

  final List<TextStylePreset> presets;
  final String? activeId;
  final ValueChanged<TextStylePreset> onPick;

  // Kit tile vertical layout: 40 preview + label ≈ 76 (matches the
  // StyleTileRow rail below so the two rails read identically).
  static const double _rowHeight = 76;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Generous trailing inset so the last chip clears the
        // sheet edge cleanly and the row reads as scrollable
        // (final chip never butts against the bezel).
        padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
        clipBehavior: Clip.none,
        itemCount: presets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final p = presets[i];
          // Kit tile: preview slot carries the "Aa" specimen; the
          // tile owns label + selection chrome (the old bespoke
          // _StyleChip and its in-preview selection ring are gone).
          return PanelOptionTile(
            preview: SizedBox(
              width: 44,
              height: 40,
              child: _StylePreviewTile(spec: p.spec),
            ),
            label: textStylePresetLabel(context.l10n, p),
            selected: p.id == activeId,
            width: 76,
            onTap: () {
              EditorHaptics.toggle();
              onPick(p);
            },
          );
        },
      ),
    );
  }
}

/// Renders an "Aa" glyph preview using the preset's actual visual
/// treatment — text colour, background fill (+ radius + padding),
/// outline ring, shadow / glow, weight, italic, underline. Painted
/// at a fixed 22pt so every tile reads at the same rhythm
/// regardless of the preset's intended font-size on a real layer.
///
/// Backdrop is **adaptive** (not a flat dark gradient): when the
/// preset's text colour is light (white/near-white) the tile uses
/// a soft dark slate card so the glyphs read truthfully; when it's
/// dark the tile uses a clean off-white card. Mirrors how the
/// preset is actually used on a real canvas — no preview lies, no
/// "row of dark boxes" feeling.
class _StylePreviewTile extends StatelessWidget {
  const _StylePreviewTile({required this.spec});

  final TextStyleSpec spec;
  static const String _previewText = 'Aa';
  static const double _previewFontSize = 22;

  // Adaptive backdrop palette — soft, premium. The light card is
  // a touch warmer than pure white so it doesn't fight a true-white
  // preset background; the dark card is slate-800 (not black) for
  // the same reason.
  static const Color _lightCard = Color(0xFFF5F5F7); // Apple-grey
  static const Color _darkCard = Color(0xFF1F2937); // slate-800

  // WCAG relative luminance.
  static double _luminance(Color c) {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  @override
  Widget build(BuildContext context) {
    final hasOutline = spec.outlineColor != null;
    final hasBg = spec.backgroundColor != null;
    // Adaptive card: pick the card colour against the preset's
    // *text* colour so light text always lands on the dark card
    // and vice versa. Presets that ship their own background
    // plate (Caption, CTA, Highlight, …) get the light card so
    // the plate itself stays the visual focus.
    final backdropIsDark = !hasBg && _luminance(spec.color) > 0.7;
    final cardColor = backdropIsDark ? _darkCard : _lightCard;

    final shadows = spec.shadowColor == null
        ? null
        : <Shadow>[
            Shadow(
              color: spec.shadowColor!,
              // Dial blur down so the small tile doesn't smear; the
              // tile is ~1/3 the size of a real layer's glyphs.
              blurRadius: spec.shadowBlur * 0.6,
              offset: Offset(
                spec.shadowOffset.dx * 0.4,
                spec.shadowOffset.dy * 0.4,
              ),
            ),
          ];
    // Fill pass.
    final fillStyle = TextStyle(
      fontSize: _previewFontSize,
      color: spec.color,
      fontWeight: spec.fontWeight,
      fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
      decoration: spec.underline ? TextDecoration.underline : null,
      decorationColor: spec.color,
      shadows: shadows,
      height: 1.0,
    );
    final fillText = Text(_previewText, style: fillStyle);
    Widget glyphs;
    if (hasOutline) {
      // Stroke + fill double-pass — same trick the canvas uses, so
      // the preview matches what lands on the layer. `color` is
      // omitted on the stroke pass to dodge the TextStyle assertion.
      final strokeStyle = TextStyle(
        fontSize: _previewFontSize,
        fontWeight: spec.fontWeight,
        fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
        height: 1.0,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (spec.outlineWidth * 0.6).clamp(0.5, 4.0)
          ..color = spec.outlineColor!,
      );
      glyphs = Stack(
        alignment: Alignment.center,
        children: [
          Text(_previewText, style: strokeStyle),
          fillText,
        ],
      );
    } else {
      glyphs = fillText;
    }
    // Background fill: padding is the only thing scaled down for
    // the small tile; the radius is a percentage so it self-scales
    // against the preview box and stays a faithful pill / rounded
    // / square shape regardless of the preset's intended font size.
    Widget tileContent = glyphs;
    if (hasBg) {
      tileContent = TextBackgroundBox(
        color: spec.backgroundColor!,
        radiusPercent: spec.backgroundRadius,
        paddingX: (spec.backgroundPaddingX * 0.4).clamp(2.0, 10.0),
        paddingY: (spec.backgroundPaddingY * 0.4).clamp(2.0, 8.0),
        child: glyphs,
      );
    }
    // Tile chrome — adaptive card with an optional selection ring
    // around its edge (only visible cue for the selected state,
    // since the chip itself has no frame).
    // Selection chrome lives on the kit PanelOptionTile now — the
    // preview stays selection-agnostic content.
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: tileContent,
    );
  }
}

// ─── Canva-style sub-tool helpers ───────────────────────────────────
//
// Shared widgets for the "presets-first, advanced-hidden" sub-tool
// redesign. The canvas above each sheet is the live preview, so these
// helpers focus on fast 1-tap choices instead of large preview tiles.

/// Single-select tile group for visual style presets (Background
/// shape, Shadow style, Border style, etc). Each tile renders
/// through the shared [PanelOptionTile] so selection / hover /
/// pressed states match the Adjust preset chip.
class StyleTileRow extends StatelessWidget {
  const StyleTileRow({super.key, required this.tiles});

  final List<StyleTile> tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tiles[i];
          return PanelOptionTile(
            icon: t.icon,
            iconSize: t.iconSize,
            label: t.label,
            selected: t.selected,
            onTap: () {
              EditorHaptics.toggle();
              t.onTap();
            },
            width: 76,
          );
        },
      ),
    );
  }
}

/// Value spec consumed by [StyleTileRow]. Keeps the call sites
/// declarative — actual chrome lives in [PanelOptionTile].
class StyleTile {
  const StyleTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconSize = 22,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Icon size override — e.g. border thickness presets render the
  /// same horizontal-rule glyph at 16/22/28 so the preview itself
  /// communicates Thin / Medium / Thick.
  final double iconSize;
}
