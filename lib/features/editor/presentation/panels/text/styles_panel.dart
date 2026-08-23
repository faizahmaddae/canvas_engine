// Styles panel (Phase 2A commit 3): extracted verbatim from the
// text_mode_toolbar part-file library (text_style_browser.dart +
// text_decoration_panels.dart). Rename-only promotions for the
// symbols the library consumes; everything else stays private.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_icons.dart';
import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/haptics.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../../../l10n/l10n.dart';
import '../../widgets/controls/connected_track.dart';
import '../../widgets/controls/toggle_segment.dart';
import 'effect_sections.dart';
import '../../../text/application/text_tool_controller.dart';
import '../../../text/domain/text_style_presets.dart';
import '../../../engine/modules/text/text_layer.dart';
import '../../../toolbar/presentation/widgets/preset_chip.dart';

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
/// redesign §3, "Style & Effects"). Stroke (کادر), shadow and
/// background are wired — they are THE home for text decoration now
/// that the bar consolidation removed their standalone dock tiles.
///
/// Glow and gradient chips shipped as "visibly disabled vocabulary"
/// in July and stayed inert for a month — a permanent promise is a
/// lying control (§10.3; ux-audit P2-19). Removed until the features
/// land; the categories return WITH their sections, not before.
enum _EffectCategory { stroke, shadow, background }

class _StylesBodyState extends ConsumerState<StylesBody> {
  /// Open effect sub-section. Panel-local by design: closing the
  /// sheet resets to the collapsed presets-only view.
  _EffectCategory? _openEffect;

  /// Active chip highlight: a preset is "current" iff merging its
  /// visual subset onto the layer's style is a no-op. Same merge
  /// rule the controller uses on apply.
  /// Which preset the layer's current style corresponds to, matched
  /// against what applying that preset would ACTUALLY produce.
  ///
  /// `p.spec` is the authored preset; `readableOnCanvas` may repaint it
  /// (a near-white fill on white paper becomes dark). Matching on the
  /// authored value meant tapping such a preset applied the resolved
  /// spec and then highlighted nothing — the rail went blank right
  /// after you chose from it. Apply, preview and match now share one
  /// projection.
  String? _matchPresetId(TextStyleSpec style) {
    final resolve = ref
        .read(textToolControllerProvider.notifier)
        .readableOnCanvas;
    for (final p in kTextStylePresets) {
      final merged = mergePresetVisual(current: style, preset: resolve(p.spec));
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

    // With an effect section open, the preset rail hides: the sheet
    // shows chips + the active section only. Keeps the whole panel
    // under the dock cap with zero internal scrolling — re-tapping
    // the chip (or switching sheets) brings the rail back.
    final sectionOpen = _openEffect != null;

    final section = switch (_openEffect) {
      _EffectCategory.shadow => ShadowEffectSection(layer: layer),
      _EffectCategory.background => BackgroundEffectSection(layer: layer),
      _EffectCategory.stroke => BorderEffectSection(layer: layer),
      _ => null,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!sectionOpen)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _StylesRow(
              presets: presets,
              activeId: activeId,
              onPick: apply,
              // Preview what APPLYING will produce, not what the
              // preset literally declares — several are authored
              // light-on-dark and get recoloured by
              // `readableOnCanvas` when the canvas is light.
              resolveColor: ref
                  .read(textToolControllerProvider.notifier)
                  .readableOnCanvas,
            ),
          ),
        const SizedBox(height: 10),
        // ONE instrument row: the B/I/U toggles beside the effects
        // track. B/I/U's home is this live panel (ux-audit P3-2 —
        // they used to mutate behind the «⋯» sheet's full scrim);
        // the effects track carries each treatment's LIVE state as a
        // colour dot, so nobody opens a section to learn nothing is
        // on. Reads straight off the layer (no local flags): writes
        // round-trip through the command and the rebuilt layer flips
        // the segment.
        SizedBox(
          height: 44,
          child: Row(
            children: [
              if (!sectionOpen) ...[
                ToggleSegmentGroup(
                  children: [
                    Semantics(
                      label: context.l10n.boldAction,
                      button: true,
                      child: ToggleSegment(
                        icon: AppIcons.bold,
                        selected: layer.style.isBold,
                        onTap: () => ctrl.setBold(!layer.style.isBold),
                      ),
                    ),
                    Semantics(
                      label: context.l10n.italicAction,
                      button: true,
                      child: ToggleSegment(
                        icon: AppIcons.textItalic,
                        selected: layer.style.italic,
                        onTap: () => ctrl.setItalic(!layer.style.italic),
                      ),
                    ),
                    Semantics(
                      label: context.l10n.underlineAction,
                      button: true,
                      child: ToggleSegment(
                        icon: AppIcons.textUnderline,
                        selected: layer.style.underline,
                        onTap: () => ctrl.setUnderline(!layer.style.underline),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _EffectsTrack(
                  style: layer.style,
                  open: _openEffect,
                  onToggle: (c) =>
                      setState(() => _openEffect = _openEffect == c ? null : c),
                ),
              ),
            ],
          ),
        ),
        // Sub-section area — grows/collapses under the chips.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: section == null
              ? const SizedBox(width: double.infinity, height: 0)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: section,
                ),
        ),
      ],
    );
  }
}

/// The effects track: خط دور · سایه · زمینه as one connected
/// instrument. Every segment opens a real section (§10.3: no
/// permanent disabled vocabulary; glow/gradient return with their
/// sections), and a live treatment shows its colour as a dot inside
/// its segment — the state is readable before any section opens.
class _EffectsTrack extends StatelessWidget {
  const _EffectsTrack({
    required this.style,
    required this.open,
    required this.onToggle,
  });

  final TextStyleSpec style;
  final _EffectCategory? open;
  final ValueChanged<_EffectCategory> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);

    Widget label(String text, bool active, Color? stateDot) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 12.5px is the effect-label size contract the tests
              // key off (tb2 15/16) — dock/preset labels use 10-11px.
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: active ? tokens.accentText : tokens.textPrimary,
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (stateDot != null) ...[
            const SizedBox(width: 5),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: stateDot,
                shape: BoxShape.circle,
                border: Border.all(
                  color: tokens.border.withValues(alpha: 0.7),
                  width: 0.5,
                ),
              ),
            ),
          ],
        ],
      );
    }

    TrackSegmentSpec seg(_EffectCategory c, String text, Color? stateDot) {
      final active = open == c;
      return TrackSegmentSpec(
        semanticLabel: text,
        active: active,
        onTap: () => onToggle(c),
        child: label(text, active, stateDot),
      );
    }

    return ConnectedTrack(
      segments: [
        seg(_EffectCategory.stroke, l10n.effectStrokeLabel, style.outlineColor),
        seg(_EffectCategory.shadow, l10n.shadowTool, style.shadowColor),
        // Short label (زمینه) — track real estate; the full word
        // (پس‌زمینه) stays on titles like the colour sheet.
        seg(
          _EffectCategory.background,
          l10n.bgShortLabel,
          style.backgroundColor,
        ),
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
    required this.resolveColor,
  });

  final List<TextStylePreset> presets;
  final String? activeId;
  final ValueChanged<TextStylePreset> onPick;

  /// Maps a preset to the spec it will actually apply as. Same
  /// function the controller runs on pick, so preview and result
  /// cannot disagree.
  final TextStyleSpec Function(TextStyleSpec) resolveColor;

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
          return PresetChip.option(
            preview: SizedBox(
              width: 44,
              height: 40,
              child: _StylePreviewTile(spec: resolveColor(p.spec)),
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
/// Backdrop is **adaptive**, and it adapts to the spec the caller
/// passes in — which is the RESOLVED spec, i.e. the one applying the
/// preset will really produce. That distinction is the whole point:
/// while the tile adapted to the preset's *authored* colour, a
/// white-on-nothing preset previewed as white glyphs on an invented
/// dark slate and then landed as dark glyphs on white paper. Feeding
/// it the resolved colour makes the two agree again.
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

// StyleTileRow / StyleTile (the 72dp icon-tile rail) retired in the
// compactness pass — every decoration surface now uses the 36dp
// preset-chip rows in `effect_sections.dart`.
