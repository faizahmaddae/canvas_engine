// Font picker panel (Phase 2A commit 2): extracted verbatim from the
// text_mode_toolbar part-file library. Rename-only promotions for the
// symbols that cross files; everything else stays private.

import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_tokens.dart';
import '../../../../../../core/utils/haptics.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../text/domain/font_catalog.dart';

/// Sample preview text used inside a [_FontCard]. Picks a string
/// that flatters the family's personality:
///   * sans / mono → "Hello"     (legibility check)
///   * display     → "POSTER"    (showcases statement weight)
///   * script      → "Hello"     (handwriting flow)
///   * Arabic *    → "سلام دنیا"  (full word, both directions)
String fontSampleText(FontEntry entry) {
  if (entry.script == FontScript.arabic) return 'سلام دنیا';
  switch (entry.category) {
    case FontCategory.display:
      return 'POSTER';
    case FontCategory.mono:
      return 'Hello 12';
    case FontCategory.sans:
    case FontCategory.script:
    case FontCategory.traditional:
    case FontCategory.nastaliq:
      return 'Hello';
  }
}

/// Horizontally-scrollable strip of [_FontCard] specimens.
/// Trailing entry is an "All fonts" pill that opens the full
/// sectioned picker — replaces the old bordered footer row.
class FontCardStrip extends StatelessWidget {
  const FontCardStrip({
    super.key,
    required this.tab,
    required this.entries,
    required this.current,
    required this.onPick,
    required this.onBrowseAll,
    required this.isFarsi,
  });

  final FontScript tab;
  final List<FontEntry> entries;
  final String? current;
  final ValueChanged<String?> onPick;
  final VoidCallback onBrowseAll;
  final bool isFarsi;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      // 20dp matches the body padding the parent wrapper cancels
      // out via negative margin — keeps the first/last card flush
      // with the chrome above while letting middle cards scroll
      // edge-to-edge across the panel.
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: entries.length + 1, // + trailing "All fonts"
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        if (i == entries.length) {
          return _AllFontsCard(onTap: onBrowseAll);
        }
        final entry = entries[i];
        final entryIsFarsi = entry.script == FontScript.arabic;
        return _FontCard(
          label: entry.labelFor(Localizations.localeOf(context).languageCode),
          family: entry.family,
          sample: fontSampleText(entry),
          previewDirection: entryIsFarsi
              ? TextDirection.rtl
              : TextDirection.ltr,
          selected: entry.family == current,
          onTap: () => onPick(entry.family),
        );
      },
    );
  }
}

/// Type-specimen card. Variable-width (sized to its sample word)
/// so wide display faces and narrow sans faces both feel right.
///
/// Selected state uses the same soft-fill grammar as
/// [PanelOptionTile] (the panel-wide preset chip): a `primary @
/// 12 %` fill plus a 1dp `primary @ 50 %` border. The previous
/// underline-only treatment was easy to miss when the strip was
/// scrolled — users couldn't tell at a glance which font was
/// active. The full-tile fill makes the active font obvious from
/// any scroll position while still keeping the preview text in
/// `onSurface` so the typeface's real personality reads truthfully
/// (we deliberately do NOT tint the sample text — the colour
/// would lie about how the font looks on the canvas).
class _FontCard extends StatelessWidget {
  const _FontCard({
    required this.label,
    required this.family,
    required this.sample,
    required this.previewDirection,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? family;
  final String sample;
  final TextDirection previewDirection;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final bg = selected
        ? tokens.accent.withValues(alpha: 0.12)
        : tokens.surfaceMuted.withValues(alpha: 0.35);
    final border = selected
        ? tokens.accent.withValues(alpha: 0.5)
        : Colors.transparent;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 78),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: Directionality(
                    textDirection: previewDirection,
                    child: Text(
                      sample,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontFamily: family,
                        fontFamilyFallback: const <String>[],
                        fontSize: 28,
                        height: 1.0,
                        // Preview must read as the font's real
                        // personality — never tint it for selection.
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? tokens.accent : tokens.textSecondary,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trailing card that opens the full sectioned picker. Same height
/// as the specimen cards so the strip baseline stays flat. Visual
/// language matches the resting [_FontCard]: same soft surface
/// fill, same radius — but with a primary-tinted icon + label so
/// it reads as an entry point, not a selectable font.
class _AllFontsCard extends StatelessWidget {
  const _AllFontsCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        child: Container(
          width: 84,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.surfaceMuted.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: Icon(
                    Icons.grid_view_rounded,
                    size: 22,
                    color: tokens.accent,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.allFontsTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: tokens.accent,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
