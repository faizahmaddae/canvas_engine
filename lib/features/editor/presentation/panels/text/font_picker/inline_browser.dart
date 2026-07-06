// Font picker panel (Phase 2A commit 2): extracted verbatim from the
// text_mode_toolbar part-file library. Rename-only promotions for the
// symbols that cross files; everything else stays private.

import 'package:flutter/material.dart';

import '../../../../../../core/utils/haptics.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../text/domain/font_catalog.dart';
import '../../../../text/domain/text_style_presets.dart';
import '../../../../../../app/theme/app_tokens.dart';
import 'cards.dart';
import 'tabs.dart';

/// In-dock font body — Persian-first font picker.
///
/// Layout (top → bottom):
///   * Two-tab script switcher [فارسی] [English]. Auto-detects from
///     the layer's content but respects an explicit user override.
///   * Personality filter chips (Recommended / Sans / Display /
///     Script / Mono for Latin; Recommended / Modern / Traditional
///     / Nastaliq / Display for Farsi). Lets the user narrow by
///     personality before scanning specimens.
///   * Horizontal strip of *type-specimen* cards. Each card shows a
///     real preview word ("Hello" / "POSTER" / "سلام دنیا") rendered
///     IN that face at display size, with the family name as a
///     small caption underneath. Variable width — wide-feeling
///     display fonts get more room than narrow sans, mirroring how
///     designers pick on a real specimen sheet.
///   * Trailing "All fonts" pill at the end of the strip opens the
///     full sectioned picker for power users. No bordered footer
///     row — the strip itself is the whole panel.
///
/// Selected state is intentionally *quiet*: a thin primary
/// underline + bolder caption. No background fill, no shadow, no
/// preview-text colour swap — the preview must read as the font's
/// real personality, not as a state badge.
class InlineFontBody extends StatefulWidget {
  const InlineFontBody({
    super.key,
    required this.layerId,
    required this.current,
    required this.content,
    required this.onPick,
    required this.onBrowseAll,
  });

  final String layerId;
  final String? current;
  final String content;
  final ValueChanged<String?> onPick;

  /// Invoked when the user taps the trailing "All fonts" card.
  /// Receives the currently-active script tab so the full picker
  /// can open scoped to the same language the user was browsing.
  final ValueChanged<FontScript> onBrowseAll;

  @override
  State<InlineFontBody> createState() => _InlineFontBodyState();
}

class _InlineFontBodyState extends State<InlineFontBody> {
  late FontScript _tab;

  /// Active personality filter. `null` = "Recommended" (the curated
  /// short list — what most users want first). A non-null value
  /// narrows the strip to that single [FontCategory] within the
  /// active script.
  FontCategory? _filter;

  /// Set to true once the user explicitly taps a tab. While true,
  /// out-of-band content/font edits will NOT auto-flip the tab —
  /// respecting the user's choice. Reset on selection change
  /// (different `layerId`) and on panel re-open (new State).
  bool _userOverride = false;

  /// Family to highlight as selected. When the user hasn't explicitly
  /// chosen a font (`current == null`) we fall back to the script-aware
  /// auto default so the picker doesn't look empty: Vazir for Persian
  /// content, Roboto for Latin. This is purely visual — controller
  /// state is unchanged.
  String? get _effectiveFamily {
    if (widget.current != null) return widget.current;
    return defaultFontFamilyForContent(widget.content);
  }

  /// Auto-detected tab. Driven ONLY by the layer's text content so
  /// the tab can never disagree with what the user actually typed
  /// (e.g. English text in a Persian face must still open English).
  /// Empty / punctuation-only content falls through to Latin via
  /// `textIsArabicScript`.
  FontScript get _autoTab =>
      textIsArabicScript(widget.content) ? FontScript.arabic : FontScript.latin;

  @override
  void initState() {
    super.initState();
    // Panel just opened — always honor the content's script.
    _tab = _autoTab;
  }

  @override
  void didUpdateWidget(covariant InlineFontBody old) {
    super.didUpdateWidget(old);
    if (old.layerId != widget.layerId) {
      // Selection moved to a different text layer: forget any
      // manual tab choice and re-sync to the new layer's script.
      _userOverride = false;
      final next = _autoTab;
      if (next != _tab) setState(() => _tab = next);
      return;
    }
    if (_userOverride) return;
    if (old.current != widget.current || old.content != widget.content) {
      // Same layer, no manual override yet — keep tab in sync with
      // content/font edits so the active tile stays visible.
      final next = _autoTab;
      if (next != _tab) setState(() => _tab = next);
    }
  }

  /// Filtered + ordered entries for the active tab. Applies the
  /// personality filter (or the curated "Recommended" short list
  /// when [_filter] is null). Vazir is always surfaced first on the
  /// Farsi tab so the default is one tap away.
  List<FontEntry> _entriesForCurrentTab() {
    final inScript = kFontCatalog.where((e) => e.script == _tab).toList();
    final List<FontEntry> base;
    if (_filter == null) {
      base = recommendedFontEntries(_tab);
    } else {
      base = inScript.where((e) => e.category == _filter).toList();
    }
    if (_tab == FontScript.arabic) {
      base.sort((a, b) {
        if (a.family == 'Vazir_Regular') return -1;
        if (b.family == 'Vazir_Regular') return 1;
        return 0;
      });
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entriesForCurrentTab();
    final isFarsi = _tab == FontScript.arabic;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: secondary filters on the left, quiet script
        // toggle on the right. Putting them on one line lowers the
        // panel's overall visual weight (the language switch used
        // to be a full-width segmented control above the chips,
        // which competed with the font previews — the actual
        // hero — for attention) and groups all "filtering" intent
        // into a single 32dp band, leaving the entire strip below
        // for the typeface specimens themselves.
        SizedBox(
          height: 32,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Categories scroll inside the remaining space so
              // adding a new bucket never pushes the script toggle
              // off-screen.
              Expanded(
                child: _FontCategoryFilter(
                  script: _tab,
                  value: _filter,
                  onChanged: (next) {
                    if (next == _filter) return;
                    EditorHaptics.tap();
                    setState(() => _filter = next);
                  },
                ),
              ),
              const SizedBox(width: 8),
              ScriptTabSwitcher(
                value: _tab,
                onChanged: (s) {
                  if (s == _tab) return;
                  EditorHaptics.tap();
                  setState(() {
                    _tab = s;
                    _userOverride = true;
                    // Reset filter when switching scripts —
                    // categories differ between scripts and
                    // "Recommended" is the safe landing for the
                    // new tab.
                    _filter = null;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Type-specimen strip — the panel's hero. Variable-width
        // selectable cards.
        //
        // Full-bleed: the strip extends edge-to-edge across the
        // panel, ignoring the body's horizontal gutter, so it
        // reads as a real horizontal carousel rather than a
        // boxed-in list. We achieve this by negative-margining the
        // wrapper by exactly the body padding
        // ([kEditorSubToolBodyPadding].horizontal / 2 = 20dp on
        // each side) and then re-introducing that gutter as the
        // ListView's own scroll-padding. Net effect: the cards
        // can scroll under the panel edges, the first/last card
        // still aligns flush with the title and chips above, and
        // the panel's outer rounded corners clip the overflow
        // cleanly so nothing visually leaks past the chrome.
        SizedBox(
          height: 84,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            child: KeyedSubtree(
              key: ValueKey('${_tab.name}:${_filter?.name ?? "rec"}'),
              // OverflowBox lets the strip render wider than its
              // parent without `Container`'s negative-margin
              // assertion. The +40 width matches the body's 20dp
              // gutter on each side, so the strip spans the full
              // panel width edge-to-edge.
              child: LayoutBuilder(
                builder: (_, c) {
                  final w = c.maxWidth + 40;
                  return OverflowBox(
                    minWidth: 0,
                    maxWidth: w,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: w,
                      child: FontCardStrip(
                        tab: _tab,
                        entries: entries,
                        current: _effectiveFamily,
                        onPick: widget.onPick,
                        onBrowseAll: () {
                          EditorHaptics.tap();
                          widget.onBrowseAll(_tab);
                        },
                        isFarsi: isFarsi,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Curated short list per script — what we put on the Recommended
/// tab. Top 4-5 workhorse families that cover the most common needs
/// (clean sans + one display + one script). Other entries remain
/// reachable via the category filter or "All fonts".
List<FontEntry> recommendedFontEntries(FontScript script) {
  const latin = <String>[
    'Roboto', // neutral workhorse sans
    'Hanken_Grotesk', // modern editorial sans
    'Lobster', // classic display script
    'Lato', // friendly humanist sans
    'Bungee_Shade', // statement display
    'Dancing_Script', // handwritten flourish
  ];
  const arabic = <String>[
    'Vazir_Regular', // modern Persian default
    'Shabnam', // clean Persian sans
    'Lalezar', // bold poster face
    'BNazanin', // traditional Naskh
    'B_Koodak_Bold_0', // friendly chunky
    'Samim_Bold', // strong sans
  ];
  final wanted = script == FontScript.latin ? latin : arabic;
  final byFamily = {
    for (final e in kFontCatalog.where((e) => e.script == script)) e.family: e,
  };
  return [
    for (final f in wanted)
      if (byFamily[f] != null) byFamily[f]!,
  ];
}

/// Personality filter chip row. "Recommended" + the categories
/// that exist for the active script. Drives the filter state above.
/// Uses a horizontal scroll so additional categories never overflow.
class _FontCategoryFilter extends StatelessWidget {
  const _FontCategoryFilter({
    required this.script,
    required this.value,
    required this.onChanged,
  });

  final FontScript script;
  final FontCategory? value;
  final ValueChanged<FontCategory?> onChanged;

  /// Categories surfaced as filter chips for [script], in display
  /// order. Built from the catalog so we never advertise an empty
  /// bucket (e.g. Latin doesn't ship Nastaliq).
  List<FontCategory> _categoriesFor(FontScript s) {
    final present = kFontCatalog
        .where((e) => e.script == s)
        .map((e) => e.category)
        .toSet();
    // Stable order: keep display priority within each script.
    const latinOrder = <FontCategory>[
      FontCategory.sans,
      FontCategory.display,
      FontCategory.script,
      FontCategory.mono,
    ];
    const arabicOrder = <FontCategory>[
      FontCategory.sans, // labelled "Modern" for Arabic
      FontCategory.traditional,
      FontCategory.nastaliq,
      FontCategory.display,
    ];
    final order = s == FontScript.latin ? latinOrder : arabicOrder;
    return [
      for (final c in order)
        if (present.contains(c)) c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final cats = _categoriesFor(script);
    // Secondary-weight chips: no resting border (the chip row used
    // to wear an outlineVariant border on every entry, which made
    // categories visually equal to the font specimens below). Now
    // resting reads as plain muted text; only the active chip
    // earns a soft primary tint pill — it's clearly a filter on
    // top of the hero strip, not a separate primary action.
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 26,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          // `maxLines: 1` + `overflow: visible` defends long
          // category names ("Nastaliq", "Traditional") against any
          // ancestor that imposes a width constraint — the row
          // scrolls horizontally so labels are allowed to take
          // their full intrinsic width without ever truncating
          // mid-word ("Na…").
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? tokens.accent : tokens.textSecondary,
              letterSpacing: 0.1,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      itemCount: cats.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 4),
      itemBuilder: (_, i) {
        if (i == 0) {
          return chip(
            label: l10n.recommendedFontsLabel,
            selected: value == null,
            onTap: () => onChanged(null),
          );
        }
        final cat = cats[i - 1];
        return chip(
          label: localizedFontCategoryLabel(l10n, script, cat),
          selected: value == cat,
          onTap: () => onChanged(cat),
        );
      },
    );
  }
}
