import 'package:flutter/material.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/app_tokens.dart';
import '../../../presentation/widgets/editor_breakpoints.dart';
import '../../../../../core/utils/haptics.dart';

/// THE preset-choice family for every editor panel (tb2 15/16 —
/// chip-grammar unification, phase4 §1 unparked by decision D-c).
/// Replaces the three drifted implementations (`PresetChip`,
/// `LayoutPresetChip`, `PanelOptionTile`) with one widget in two
/// layout modes:
///
///   * **Pill** ([PresetChip.new]) — text-only value chip used
///     above sliders and in preset rows (paint size/blur/opacity,
///     text size px row, style/effect section chips, …). Fixed
///     44dp height (kMinHitTarget), radius 14, 15sp tabular label.
///     Fires [EditorHaptics.snap] itself.
///   * **Option tile** ([PresetChip.option]) — glyph-above-label
///     selection tile used by panel preset rows (Adjust presets,
///     border thickness, mask shape, shadow style, text style
///     cards, context-panel actions). Radius 10, 11sp label, 44dp
///     MINIMUM height. Haptics stay caller-owned (tiles carry
///     semantic-specific feedback — toggle vs snap — at the call
///     site), preserving the old PanelOptionTile contract.
///
/// **One selected-state contract across both modes** (the richer
/// PresetChip treatment, same family as the active DockToolTile):
/// `accent @16%` fill + `accentDeep` foreground + 12dp `accent
/// @28%` soft shadow + w700 label. Resting fills stay per-mode
/// (pill `surfaceMuted @55%`, tile `@35%`) — density-appropriate
/// and deliberate. Press feedback is a uniform 0.96 scale-down;
/// tiles keep their desktop hover tint. Per-panel visual hacks
/// remain banned — extend this widget instead.
class PresetChip extends StatefulWidget {
  /// Text-only pill chip.
  const PresetChip({
    super.key,
    required String this.label,
    required this.selected,
    required this.onTap,
    this.minWidth = 56,
  }) : icon = null,
       preview = null,
       iconSize = 18,
       width = null,
       _tile = false;

  /// Glyph-above-label option tile (the old `PanelOptionTile`
  /// shape). Provide [icon] OR [preview] (or neither for a pure
  /// label tile).
  const PresetChip.option({
    super.key,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconSize = 18,
    this.preview,
    this.label,
    this.width,
  }) : assert(
         icon == null || preview == null,
         'Provide either icon or preview, not both.',
       ),
       minWidth = 0,
       _tile = true;

  final String? label;
  final bool selected;
  final VoidCallback onTap;

  /// Pill mode: minimum chip width so a scroller's chips share one
  /// width and the eye doesn't track variable widths while
  /// scrubbing through presets.
  final double minWidth;

  /// Tile mode: optional leading icon (rendered above the label).
  final IconData? icon;

  /// Tile mode: override the 18dp icon size — e.g. border
  /// thickness presets render the same glyph at 16/22/30.
  final double iconSize;

  /// Tile mode: custom artwork rendered in the glyph slot.
  final Widget? preview;

  /// Tile mode: fixed width; `null` where the parent stretches
  /// tiles via `Expanded`.
  final double? width;

  final bool _tile;

  @override
  State<PresetChip> createState() => _PresetChipState();
}

class _PresetChipState extends State<PresetChip> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final selected = widget.selected;
    final tile = widget._tile;

    // ── the ONE selected contract ───────────────────────────────
    final fg = selected
        ? tokens.accentText
        : (tile ? tokens.textSecondary : tokens.textPrimary);
    Color fill;
    if (selected) {
      fill = tokens.accent.withValues(alpha: 0.16);
    } else if (tile && _down) {
      fill = tokens.accent.withValues(alpha: 0.10);
    } else if (tile && _hover) {
      fill = tokens.textPrimary.withValues(alpha: 0.06);
    } else if (tile) {
      fill = tokens.surfaceMuted.withValues(alpha: 0.35);
    } else {
      // An unselected pill is an OUTLINE, not a filled slab: the
      // prototype's row of pills reads as a set of options, and a
      // filled unselected chip competes with the selected one.
      fill = Colors.transparent;
    }
    // Both modes carry a hairline now. An unselected TILE was a
    // `surfaceMuted @35%` fill and nothing else, which measured
    // 1.05:1 against the light panel and 1.02:1 against the dark one —
    // the tile rectangles were invisible, so a row of options read as
    // floating glyphs with one highlighted box among them. WCAG 1.4.11
    // wants 3:1 for a component boundary, and `border` does NOT reach
    // it: at full strength it is 1.31:1 light / 1.19:1 dark, so the
    // first attempt swapped one invisible edge for another. Hence
    // `borderStrong` below, which is the token that clears the bar.
    final border = Border.all(
      // `borderStrong`, not `border`: the decorative hairline measured
      // 1.31:1 light / 1.19:1 dark against the panel, so swapping one
      // invisible edge for another invisible edge fixed nothing. This
      // stop clears 3:1 on both the panel surface and the tile fill.
      // `accentText` for the selected edge too: `accent` measured
      // 2.92:1 on light `surface` — a 0.08 miss on the one boundary
      // that carries the selected state. The FILL stays `accent`.
      color: selected ? tokens.accentText : tokens.borderStrong,
      width: selected ? 1.5 : 1,
    );
    final shadow = selected && tile
        ? [
            BoxShadow(
              color: tokens.accent.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
        : const <BoxShadow>[];
    // Pills are FULLY round (tb7 3/7) — the prototype's chip
    // vocabulary. Tiles keep their 10dp card corner.
    final radius = BorderRadius.circular(tile ? 10 : 99);

    void handleTap() {
      // Pill chips self-fire; option tiles keep caller-owned
      // haptics (see class doc).
      if (!tile) EditorHaptics.snap();
      widget.onTap();
    }

    final Widget content = tile
        ? _tileContent(fg)
        : Text(
            widget.label!,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );

    Widget body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.standard),
      curve: AppMotion.curve,
      constraints: BoxConstraints(
        minWidth: widget.minWidth,
        // Tiles grow with their glyph+label content; the pill is
        // painted at 36 and padded out to the 44 floor.
        minHeight: tile ? 44 : 0,
      ),
      // Painted 36 like the prototype; the 44dp hit floor is restored
      // by the outer padding below, the ModeDoneButton split.
      height: tile ? null : 36,
      width: widget.width,
      padding: tile
          ? const EdgeInsets.symmetric(vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 14),
      alignment: tile ? null : Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        boxShadow: shadow,
      ),
      // FOREGROUND, so the hairline paints over the tile instead of
      // insetting it. As a `decoration` border it added 2dp of height
      // and overflowed every fixed-height host by exactly that.
      foregroundDecoration: BoxDecoration(borderRadius: radius, border: border),
      child: tile ? Center(child: content) : content,
    );

    if (tile) {
      body = MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: body,
      );
    } else {
      // Restore the 44dp touch floor around the 36dp painted pill —
      // the GestureDetector below is `opaque`, so the padding is live
      // hit area, not dead space.
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: (kMinHitTarget - 36) / 2),
        child: body,
      );
    }

    return Semantics(
      label: widget.label,
      button: true,
      selected: selected,
      onTap: handleTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: handleTap,
          child: AnimatedScale(
            scale: _down ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _tileContent(Color fg) {
    Widget glyph;
    if (widget.preview != null) {
      glyph = IconTheme(
        data: IconThemeData(color: fg, size: widget.iconSize),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: widget.preview!,
        ),
      );
    } else if (widget.icon != null) {
      glyph = Icon(widget.icon, size: widget.iconSize, color: fg);
    } else {
      glyph = const SizedBox.shrink();
    }
    final hasGlyph = widget.icon != null || widget.preview != null;
    final label = widget.label;

    Widget labelText(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w600,
        color: fg,
        letterSpacing: 0,
      ),
    );

    if (hasGlyph && label != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [glyph, const SizedBox(height: 4), labelText(label)],
      );
    }
    if (hasGlyph) return glyph;
    return labelText(label ?? '');
  }
}
