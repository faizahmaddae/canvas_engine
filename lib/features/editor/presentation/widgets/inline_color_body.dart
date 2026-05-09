import 'package:flutter/material.dart';

import '../../../../core/utils/haptics.dart';

/// Shared compact color body used by **every** colour-bearing
/// editor panel — Text, Image Border / Shadow, Shape Style /
/// Border / Shadow, Paint, Canvas Background.
///
/// Layout (single source of truth):
///   1. Slim status strip — small swatch + hex on the left,
///      **Custom** rainbow pill on the right. Replaces the old
///      bordered "Current" card; saves ~24dp of vertical space
///      and promotes the picker entry point out of the swatch
///      grid.
///   2. Optional "Recent" group — full-size labelled row, OR
///      compact inline row (label on the left of smaller dots)
///      when [compactRecents] is true.
///   3. "Palette" group — wrap of brightness-aware swatches with
///      a 2dp selected ring + 40 % check tick.
///
/// Behaviour is delegated to callers via [onPick] (palette /
/// recents tap) and [onCustom] (rainbow pill tap). Alpha
/// preservation, recents bookkeeping, and undoable commits stay
/// a caller concern.
class InlineColorBody extends StatelessWidget {
  const InlineColorBody({
    super.key,
    required this.current,
    required this.recents,
    required this.palette,
    required this.onPick,
    required this.onCustom,
    this.compactRecents = false,
  });

  final Color current;
  final List<Color> recents;
  final List<Color> palette;
  final ValueChanged<Color> onPick;
  final VoidCallback onCustom;

  /// Compact recents:
  ///   * Hidden entirely when fewer than 2 recents (one swatch
  ///     adds chrome without earning its row — the user just
  ///     picked it; it's still in the current strip).
  ///   * No "Recent" label above the row — instead a tiny inline
  ///     caption sits to the left of smaller (24 dp) dots.
  ///   * Recents are de-duped against the curated palette and
  ///     against themselves so neutrals/brand hues don't pile up.
  ///
  /// Defaults to false — callers that want the labelled, full-
  /// size recents row (e.g. Text colour, Background) opt out.
  final bool compactRecents;

  /// Default mobile-first palette — neutrals first, then warm →
  /// cool primaries. Surfaced so callers can reuse the curated
  /// order without redefining it.
  static const List<Color> defaultPalette = <Color>[
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFF6B7280),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFFFACC15),
    Color(0xFF22C55E),
    Color(0xFF06B6D4),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
  ];

  @override
  Widget build(BuildContext context) {
    // Compare on RGB only — callers preserve current alpha when
    // applying a palette/recent pick (so a swatch tap is a hue
    // choice, not an alpha reset). Comparing full ARGB would
    // hide the selected ring whenever opacity ≠ 1.
    int rgb(Color c) => c.toARGB32() & 0x00FFFFFF;
    final currentRgb = rgb(current);

    // De-dupe recents against the palette + themselves in
    // compact mode so neutrals/brand hues that already live in
    // the palette don't double-up the row. Order is preserved
    // (most-recent stays first). Non-compact mode keeps the
    // caller-supplied list verbatim for backwards compatibility
    // with the labelled Background / Text-colour rows.
    final List<Color> dedupedRecents;
    if (compactRecents) {
      final paletteRgb = palette.map(rgb).toSet();
      final seen = <int>{};
      dedupedRecents = <Color>[
        for (final c in recents)
          if (!paletteRgb.contains(rgb(c)) && seen.add(rgb(c))) c,
      ];
    } else {
      dedupedRecents = recents;
    }

    final showRecents = compactRecents
        ? dedupedRecents.length >= 2
        : dedupedRecents.isNotEmpty;
    final recentDotSize = compactRecents ? 24.0 : 28.0;
    final recentRowHeight = compactRecents ? 26.0 : 30.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        _CurrentColorStrip(color: current, onCustom: onCustom),
        SizedBox(height: compactRecents && showRecents ? 8 : 14),
        if (showRecents) ...[
          if (!compactRecents) ...[
            const _GroupLabel('Recent'),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: recentRowHeight,
            child: Row(
              children: [
                if (compactRecents) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 10),
                    child: Text(
                      'Recent',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.75),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                    ),
                  ),
                ],
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: dedupedRecents.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(width: compactRecents ? 6 : 8),
                    itemBuilder: (_, i) => _PolishedSwatch(
                      color: dedupedRecents[i],
                      size: recentDotSize,
                      selected: rgb(dedupedRecents[i]) == currentRgb,
                      onTap: () => onPick(dedupedRecents[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compactRecents ? 12 : 14),
        ],
        const _GroupLabel('Palette'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in palette)
              _PolishedSwatch(
                color: c,
                selected: rgb(c) == currentRgb,
                onTap: () => onPick(c),
              ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Subtle micro-label that names a swatch group without
/// dominating it. Sentence case + low-contrast onSurfaceVariant +
/// `labelSmall` weight; a touch of letter-spacing keeps it
/// legible at small sizes. Reads as caption, not as a heading.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Brightness-aware circular swatch with a slim 2dp selected
/// ring and a 40 %-of-diameter check tick. Same visual grammar
/// across every panel so users learn it once.
class _PolishedSwatch extends StatefulWidget {
  const _PolishedSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 36,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  State<_PolishedSwatch> createState() => _PolishedSwatchState();
}

class _PolishedSwatchState extends State<_PolishedSwatch> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final color = widget.color;
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: selected
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.55),
                  width: selected ? 2.0 : 1,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: a,
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        key: const ValueKey(true),
                        size: widget.size * 0.4,
                        color: checkColor,
                      )
                    : const SizedBox.shrink(key: ValueKey(false)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slim status strip that replaces the bordered "Current" card.
///
/// Layout: `[swatch]  #RRGGBB        [Custom rainbow pill]`
///
/// Total height ≈ 40 dp (vs ~64 dp for the boxed card). No heavy
/// container fill — just a thin pill on the Custom side so the
/// strip reads as editor chrome, not a settings row.
class _CurrentColorStrip extends StatelessWidget {
  const _CurrentColorStrip({required this.color, required this.onCustom});

  final Color color;
  final VoidCallback onCustom;

  String _hex(Color c) {
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String hh(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${hh(r)}${hh(g)}${hh(b)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.7),
              width: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _hex(color),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: scheme.onSurface,
          ),
        ),
        const Spacer(),
        _CustomColorPill(onTap: onCustom),
      ],
    );
  }
}

/// Compact "Custom" affordance — rainbow gradient dot + label
/// inside a soft pill. Replaces the rainbow tile that used to
/// live in the palette grid; promoting it to the header strip
/// makes the entry point unmissable without crowding the wrap.
class _CustomColorPill extends StatelessWidget {
  const _CustomColorPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Color(0xFFFF5252),
                      Color(0xFFFFD740),
                      Color(0xFF69F0AE),
                      Color(0xFF40C4FF),
                      Color(0xFFB388FF),
                      Color(0xFFFF5252),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Custom',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
