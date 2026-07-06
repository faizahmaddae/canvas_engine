// Font sub-tool panel and the full-sheet font picker for the
// text-mode toolbar, split out of text_mode_toolbar.dart. Part file:
// every symbol resolves via the library root's imports — add
// imports there, never here.
part of 'text_mode_toolbar.dart';

String _localizedFontCategoryLabel(
  AppLocalizations l10n,
  FontScript script,
  FontCategory category,
) {
  return switch (category) {
    FontCategory.sans =>
      script == FontScript.arabic
          ? l10n.fontCategoryModern
          : l10n.fontCategorySans,
    FontCategory.display => l10n.fontCategoryDisplay,
    FontCategory.script => l10n.fontCategoryScript,
    FontCategory.mono => l10n.fontCategoryMono,
    FontCategory.traditional => l10n.fontCategoryTraditional,
    FontCategory.nastaliq => l10n.fontCategoryNastaliq,
  };
}

/// Result of the font picker. We need a tri-state because the user
/// can either:
///   * pick a family (`family != null`)
///   * pick "system default" (`family == null`, but a real choice)
///   * dismiss the sheet without picking — we must not overwrite.
class _FontPickResult {
  const _FontPickResult._(this.family, this._dismissed);
  final String? family;
  final bool _dismissed;

  static const unchanged = _FontPickResult._(null, true);
  static const systemDefault = _FontPickResult._(null, false);

  bool get isDismissed => _dismissed;
}

/// Bottom-sheet picker that lists the families in [kFontCatalog]
/// for **one script at a time**. The sheet opens scoped to
/// [initialScript] (the tab the user was browsing in the inline
/// panel) so taps never produce a mixed-language list. Users can
/// still switch script inside the sheet via the header tab
/// switcher — the sheet is the same data source as the inline
/// panel, just at full height with category headers visible.
Future<_FontPickResult> _showFontPickerSheet(
  BuildContext context, {
  required String? current,
  required FontScript initialScript,
}) async {
  final result = await showModalBottomSheet<_FontPickResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Near-transparent barrier ON PURPOSE: this is a control panel —
    // the user must keep seeing the live font change on the canvas
    // behind the sheet. The sheet's own elevation separates it.
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.06),
    builder: (sheetCtx) {
      final tokens = AppTokens.of(sheetCtx);
      final media = MediaQuery.of(sheetCtx);
      final maxHeight = media.size.height * 0.7;
      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: _FontPickerSheet(
              current: current,
              initialScript: initialScript,
            ),
          ),
        ),
      );
    },
  );
  return result ?? _FontPickResult.unchanged;
}

/// Stateful body of the All-fonts sheet. Owns the in-sheet script
/// tab so the user can browse one language at a time without
/// dismissing — initialised to the tab the inline panel was on.
class _FontPickerSheet extends StatefulWidget {
  const _FontPickerSheet({required this.current, required this.initialScript});

  final String? current;
  final FontScript initialScript;

  @override
  State<_FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends State<_FontPickerSheet> {
  late FontScript _script;

  @override
  void initState() {
    super.initState();
    _script = widget.initialScript;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: tokens.border.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(
                Icons.font_download_outlined,
                size: 18,
                color: tokens.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.allFontsTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // In-sheet script switcher — same widget the inline panel
        // uses, so users carry the same mental model.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: _ScriptTabSwitcher(
            value: _script,
            onChanged: (s) {
              if (s == _script) return;
              EditorHaptics.tap();
              setState(() => _script = s);
            },
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: _FontPickerList(current: widget.current, script: _script),
        ),
      ],
    );
  }
}

class _FontPickerList extends StatelessWidget {
  const _FontPickerList({required this.current, required this.script});
  final String? current;

  /// Restrict the list to families of this script. The sheet's
  /// header tab decides which one — the list itself never mixes.
  final FontScript script;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Sectioned list scoped to a single script:
    //   System default            (Latin tab only — no Persian system font)
    //     Sans                    (category header, small)
    //       Roboto, Lato, …
    //     Display
    //       Lobster, …
    //
    // Within each category bucket the order is whatever
    // `kFontCatalog` defines, which we keep alphabetical-ish there.
    final items = <_PickerItem>[
      // "System default" only makes sense for Latin — the platform
      // default is always a Latin face, so offering it under Farsi
      // would silently clear the Persian font.
      if (script == FontScript.latin) const _PickerItem.system(),
    ];
    final inScript = kFontCatalog.where((e) => e.script == script).toList();
    for (final category in FontCategory.values) {
      final inCat = inScript.where((e) => e.category == category).toList();
      if (inCat.isEmpty) continue;
      items.add(
        _PickerItem.categoryHeader(
          _localizedFontCategoryLabel(l10n, script, category),
        ),
      );
      items.addAll(inCat.map(_PickerItem.entry));
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final tokens = AppTokens.of(ctx);
        if (item.kind == _PickerItemKind.categoryHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              item.headerLabel!.toUpperCase(),
              style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                fontSize: 11,
              ),
            ),
          );
        }
        final family = item.entry?.family;
        final label =
            item.entry?.labelFor(Localizations.localeOf(ctx).languageCode) ??
                ctx.l10n.systemDefaultFont;
        final selected = family == current;
        return Material(
          color: selected
              ? tokens.accent.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(ctx).pop(
              item.entry == null
                  ? _FontPickResult.systemDefault
                  : _FontPickResult._(family, false),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: family,
                        fontSize: 18,
                        color: selected ? tokens.accent : tokens.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_rounded, size: 18, color: tokens.accent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _PickerItemKind { entry, categoryHeader }

class _PickerItem {
  const _PickerItem.system()
    : entry = null,
      headerLabel = null,
      kind = _PickerItemKind.entry;
  const _PickerItem.entry(FontEntry this.entry)
    : headerLabel = null,
      kind = _PickerItemKind.entry;
  const _PickerItem.categoryHeader(String this.headerLabel)
    : entry = null,
      kind = _PickerItemKind.categoryHeader;

  final FontEntry? entry;
  final String? headerLabel;
  final _PickerItemKind kind;
}

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
class _InlineFontBody extends StatefulWidget {
  const _InlineFontBody({
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
  State<_InlineFontBody> createState() => _InlineFontBodyState();
}

class _InlineFontBodyState extends State<_InlineFontBody> {
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
  void didUpdateWidget(covariant _InlineFontBody old) {
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
              _ScriptTabSwitcher(
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
                      child: _FontCardStrip(
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

/// Two-pill script toggle (فارسی / English) sitting at the top-right
/// of the Font panel. Intentionally *quiet*: a tinted track with a
/// soft pill highlight on the active option. The previous design
/// was a full-width 38dp segmented control with onPrimary fill +
/// shadow, which competed with the font specimens for attention —
/// users perceived it as a primary action when it's actually a
/// preferences-level filter. Now sized for the language word
/// itself plus a small touch margin so it reads as a secondary
/// inline switch.
class _ScriptTabSwitcher extends StatelessWidget {
  const _ScriptTabSwitcher({required this.value, required this.onChanged});

  final FontScript value;
  final ValueChanged<FontScript> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    Widget pill({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      String? fontFamily,
      TextDirection? textDirection,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Directionality(
            textDirection: textDirection ?? Directionality.of(context),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? tokens.accent : tokens.textSecondary,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(
            label: context.l10n.fontScriptPersian,
            selected: value == FontScript.arabic,
            onTap: () => onChanged(FontScript.arabic),
            textDirection: TextDirection.rtl,
            // The Persian label MUST render in a Persian face — the
            // platform default is Latin and shapes "فارسی" with broken
            // joining. Vazir is the canonical Persian default we
            // already ship and use as the auto-fallback.
            fontFamily: 'Vazir_Regular',
          ),
          const SizedBox(width: 2),
          pill(
            label: context.l10n.fontScriptEnglish,
            selected: value == FontScript.latin,
            onTap: () => onChanged(FontScript.latin),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
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
          label: _localizedFontCategoryLabel(l10n, script, cat),
          selected: value == cat,
          onTap: () => onChanged(cat),
        );
      },
    );
  }
}

/// Horizontally-scrollable strip of [_FontCard] specimens.
/// Trailing entry is an "All fonts" pill that opens the full
/// sectioned picker — replaces the old bordered footer row.
class _FontCardStrip extends StatelessWidget {
  const _FontCardStrip({
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
