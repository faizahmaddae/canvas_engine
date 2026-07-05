// Styles sheet body for the text-mode toolbar, split out of
// text_mode_toolbar.dart. Part file: every symbol resolves via the
// library root's imports — add imports there, never here.
part of 'text_mode_toolbar.dart';

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

class _StylesBody extends ConsumerStatefulWidget {
  const _StylesBody({required this.layer});

  final TextLayer layer;

  @override
  ConsumerState<_StylesBody> createState() => _StylesBodyState();
}

class _StylesBodyState extends ConsumerState<_StylesBody> {
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
      EditorHaptics.tap();
      ctrl.applyStylePreset(p.spec);
    }

    final activeId = _matchPresetId(layer.style);
    // Single sorted row: recommended-first, rest in catalogue
    // order. No "More styles" button — the curated list is short
    // enough to scroll comfortably.
    final presets = orderedTextStylePresets(layerStyle: layer.style);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _StylesRow(presets: presets, activeId: activeId, onPick: apply),
    );
  }
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

  // Chip vertical layout: 52 (preview tile) + 8 (gap) + ~16 (label)
  // + 10 (padding top+bottom) ≈ 86.
  static const double _rowHeight = 86;

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
          return _StyleChip(
            preset: p,
            selected: p.id == activeId,
            onTap: () => onPick(p),
          );
        },
      ),
    );
  }
}

/// Featherweight vertical chip: preview tile on top, style name
/// below. No frame around the chip — the preview tile itself is
/// the visual unit, and the label is just a caption.
///
/// Selection state uses ONE strong cue: a 1.5px primary ring
/// drawn directly around the preview tile. No checkmark badge,
/// no row-tint, no chrome — keeps the panel light and scannable.
class _StyleChip extends StatelessWidget {
  const _StyleChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final TextStylePreset preset;
  final bool selected;
  final VoidCallback onTap;

  // Tile dimensions are fixed so chips line up perfectly across
  // varying preset visuals (small radius vs pill shape, etc.).
  static const double _tileSize = 52;
  static const double _chipWidth = 68;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    return SizedBox(
      width: _chipWidth,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Preview tile — selection ring is drawn as an
              // overlay on the tile itself rather than around the
              // whole chip, so the visual "focus" lands where the
              // user is actually looking (the sample, not the
              // label).
              SizedBox(
                width: _tileSize,
                height: _tileSize,
                child: _StylePreviewTile(spec: preset.spec, selected: selected),
              ),
              const SizedBox(height: 8),
              Text(
                preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? tokens.accent : tokens.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
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
  const _StylePreviewTile({required this.spec, this.selected = false});

  final TextStyleSpec spec;
  final bool selected;
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
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: selected
            ? Border.all(color: AppTokens.of(context).accent, width: 1.5)
            : null,
      ),
      alignment: Alignment.center,
      child: tileContent,
    );
  }
}
