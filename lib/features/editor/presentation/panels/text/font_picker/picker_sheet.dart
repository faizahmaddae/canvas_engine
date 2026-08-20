// The Font Room (`docs/text-studio-redesign-2026-08.md` §5): the
// all-fonts sheet as a two-column specimen gallery — the user's own
// words rendered large in every face, sectioned by category. The
// name-only list this replaces kept the catalogue's Persian depth
// (a nastaliq section no competitor ships) invisible.
//
// tb2 12/16 (kept verbatim): apply-on-highlight live preview. The
// first tap on a card HIGHLIGHTS it (stages the family on the
// caller's preview channel — the live session or a style-drag on
// the overlay — so the canvas behind the whisper barrier shows the
// real layer in the candidate font); tapping the highlighted card
// again PICKS it. Dismissing without picking reverts (the caller
// cancels/restores; zero history entries).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_tokens.dart';
import '../../../../../../core/utils/haptics.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../engine/modules/text/text_direction_utils.dart'
    show textIsArabicScript;
import '../../../../text/domain/font_catalog.dart';
import '../../../../../../app/ui/app_modal_sheet.dart';
import 'cards.dart' show fontSampleText;
import 'tabs.dart';
import '../../../../../../app/theme/app_icons.dart';

/// Debounce for the highlight→canvas preview. Each highlight costs
/// one full re-layout of the real layer (contract §8 keeps the
/// canvas preview uncapped), so rapid taps down the list coalesce
/// to the last one instead of measuring every intermediate family.
const Duration kFontPreviewDebounce = Duration(milliseconds: 120);

/// Cap for the IN-SHEET specimen line only (contract §8): the
/// specimen re-renders per highlight in the candidate face, and an
/// essay-length layer would relayout thousands of glyphs per tap
/// for a one-line strip. The canvas overlay preview deliberately
/// uses the layer's full, uncapped content.
const int kFontSpecimenExcerptCap = 200;

/// Result of the font picker. We need a tri-state because the user
/// can either:
///   * pick a family (`family != null`)
///   * pick "system default" (`family == null`, but a real choice)
///   * dismiss the sheet without picking — we must not overwrite.
class FontPickResult {
  const FontPickResult._(this.family, this._dismissed);
  final String? family;
  final bool _dismissed;

  static const unchanged = FontPickResult._(null, true);
  static const systemDefault = FontPickResult._(null, false);

  bool get isDismissed => _dismissed;
}

/// Bottom-sheet picker that lists the families in [kFontCatalog]
/// for **one script at a time**. The sheet opens scoped to
/// [initialScript] (the tab the user was browsing in the inline
/// panel) so taps never produce a mixed-language list. Users can
/// still switch script inside the sheet via the header tab
/// switcher — the sheet is the same data source as the inline
/// panel, just at full height with category headers visible.
Future<FontPickResult> showFontPickerSheet(
  BuildContext context, {
  required String? current,
  required FontScript initialScript,
  ValueChanged<String?>? onHighlight,
  String? specimenText,
}) async {
  // Whisper barrier (contract §9, 6%) ON PURPOSE: highlighting a
  // family previews it live on the canvas behind the sheet, so the
  // canvas must stay visible. Card + handle come from the shared
  // modal host (tb2 8/16) — the preview semantics (tb2 12/16) are
  // untouched.
  final result = await showAppSheet<FontPickResult>(
    context,
    barrier: AppSheetBarrier.whisper,
    maxHeightFraction: 0.7,
    maxWidth: 520,
    builder: (sheetCtx) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: _FontPickerSheet(
        current: current,
        initialScript: initialScript,
        onHighlight: onHighlight,
        specimenText: specimenText,
      ),
    ),
  );
  return result ?? FontPickResult.unchanged;
}

/// Stateful body of the All-fonts sheet. Owns the in-sheet script
/// tab so the user can browse one language at a time without
/// dismissing — initialised to the tab the inline panel was on —
/// plus the highlight state driving the live preview.
class _FontPickerSheet extends StatefulWidget {
  const _FontPickerSheet({
    required this.current,
    required this.initialScript,
    this.onHighlight,
    this.specimenText,
  });

  final String? current;
  final FontScript initialScript;

  /// Fires (debounced by [kFontPreviewDebounce]) when the user
  /// highlights a family — `null` means the system default. The
  /// caller stages it as a live preview; nothing commits here.
  final ValueChanged<String?>? onHighlight;

  /// The selected layer's content, rendered as a one-line specimen
  /// in the highlighted face (capped to [kFontSpecimenExcerptCap]
  /// chars, §8). Null/empty hides the strip.
  final String? specimenText;

  @override
  State<_FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends State<_FontPickerSheet> {
  late FontScript _script;

  /// Family currently highlighted for preview. Sentinel-wrapped so
  /// "nothing highlighted yet" and "system default highlighted"
  /// (family == null) stay distinguishable.
  (String?,)? _highlighted;
  Timer? _previewDebounce;

  @override
  void initState() {
    super.initState();
    _script = widget.initialScript;
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  /// First tap highlights (stages the debounced preview); a second
  /// tap on the highlighted row picks. The row that matches the
  /// layer's CURRENT family picks on first tap — it is already
  /// previewed by definition, so requiring a highlight step there
  /// would read as a dead tap.
  void _onRowTap(BuildContext ctx, String? family, FontPickResult result) {
    final alreadyHighlighted =
        _highlighted != null && _highlighted!.$1 == family;
    final isCurrent = _highlighted == null && family == widget.current;
    if (alreadyHighlighted || isCurrent) {
      _previewDebounce?.cancel();
      Navigator.of(ctx).pop(result);
      return;
    }
    EditorHaptics.tap();
    setState(() => _highlighted = (family,));
    if (widget.onHighlight != null) {
      _previewDebounce?.cancel();
      _previewDebounce = Timer(
        kFontPreviewDebounce,
        () => widget.onHighlight!(family),
      );
    }
  }

  String? get _specimenExcerpt {
    final text = widget.specimenText?.trim();
    if (text == null || text.isEmpty) return null;
    if (text.length <= kFontSpecimenExcerptCap) return text;
    return text.substring(0, kFontSpecimenExcerptCap);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final specimen = _specimenExcerpt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Handle comes from the shared modal host (tb2 8/16).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(AppIcons.fontFamily, size: 18, color: tokens.accent),
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
                    AppIcons.close,
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
          child: ScriptTabSwitcher(
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
          child: _FontRoomGrid(
            current: widget.current,
            highlighted: _highlighted,
            script: _script,
            specimen: specimen,
            onCardTap: _onRowTap,
          ),
        ),
      ],
    );
  }
}

/// The gallery: category headers over two-column rows of specimen
/// cards. Built as one flat `ListView.builder` of row-widgets so the
/// (60+ card) catalogue stays virtualized.
class _FontRoomGrid extends StatelessWidget {
  const _FontRoomGrid({
    required this.current,
    required this.highlighted,
    required this.script,
    required this.specimen,
    required this.onCardTap,
  });

  final String? current;

  /// Sentinel-wrapped highlighted family (see [_FontPickerSheetState]).
  final (String?,)? highlighted;

  /// Card tap handler owned by the sheet state (highlight vs pick).
  final void Function(BuildContext ctx, String? family, FontPickResult result)
  onCardTap;

  /// Restrict the gallery to families of this script. The sheet's
  /// header tab decides which one — the grid itself never mixes.
  final FontScript script;

  /// The layer's excerpt-capped content; null hides nothing — cards
  /// fall back to each face's own sample word.
  final String? specimen;

  /// Card-level cap on the specimen: the card is a recognition aid,
  /// and every card on screen re-lays-out its line per highlight
  /// (contract §8 keeps the CANVAS preview uncapped instead).
  static const int _cardExcerptCap = 14;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Sectioned rows scoped to a single script:
    //   System default            (Latin tab only — no Persian system font)
    //     Sans                    (category header)
    //       [Roboto][Lato] …      (two cards per row)
    final rows = <Widget>[
      if (script == FontScript.latin)
        _cardRow(<FontEntry?>[null], fillerAfter: true),
    ];
    final inScript = kFontCatalog.where((e) => e.script == script).toList();
    for (final category in FontCategory.values) {
      final inCat = inScript.where((e) => e.category == category).toList();
      if (inCat.isEmpty) continue;
      rows.add(_Header(localizedFontCategoryLabel(l10n, script, category)));
      for (var i = 0; i < inCat.length; i += 2) {
        rows.add(
          _cardRow(<FontEntry?>[
            inCat[i],
            if (i + 1 < inCat.length) inCat[i + 1],
          ], fillerAfter: i + 1 >= inCat.length),
        );
      }
    }

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  /// One gallery row: up to two cards, an empty filler keeping a
  /// half-full last row on the leading side.
  Widget _cardRow(List<FontEntry?> entries, {required bool fillerAfter}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: Row(
        children: [
          for (final entry in entries) ...[
            Expanded(
              child: _SpecimenCard(
                entry: entry,
                specimen: _sampleFor(entry),
                selected: highlighted != null
                    ? highlighted!.$1 == entry?.family
                    : entry?.family == current,
                onTap: (ctx) => onCardTap(
                  ctx,
                  entry?.family,
                  entry == null
                      ? FontPickResult.systemDefault
                      : FontPickResult._(entry.family, false),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (fillerAfter) const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  /// The user's words when they exist AND their script matches the
  /// card's face; the face's own sample otherwise. A nastaliq face
  /// asked to render Latin words would show fallback glyphs — the one
  /// thing a specimen must never do.
  String _sampleFor(FontEntry? entry) {
    final text = specimen;
    if (text != null && text.isNotEmpty) {
      final textIsArabic = textIsArabicScript(text);
      final cardIsArabic =
          (entry?.script ?? FontScript.latin) == FontScript.arabic;
      if (textIsArabic == cardIsArabic) {
        return text.length <= _cardExcerptCap
            ? text
            : text.substring(0, _cardExcerptCap);
      }
    }
    if (entry == null) return 'Aa';
    return fontSampleText(entry);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// One specimen card: the sample line rendered large in the candidate
/// face over the family name. Selection wears the panel-wide soft
/// fill + border; the specimen itself is never tinted — it must read
/// as the face's real personality.
class _SpecimenCard extends StatelessWidget {
  const _SpecimenCard({
    required this.entry,
    required this.specimen,
    required this.selected,
    required this.onTap,
  });

  /// Null = the system-default card (Latin tab only).
  final FontEntry? entry;
  final String specimen;
  final bool selected;
  final void Function(BuildContext) onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final family = entry?.family;
    final label =
        entry?.labelFor(Localizations.localeOf(context).languageCode) ??
        context.l10n.systemDefaultFont;
    final direction = (entry?.script ?? FontScript.latin) == FontScript.arabic
        ? TextDirection.rtl
        : TextDirection.ltr;
    return Material(
      color: selected
          ? tokens.accent.withValues(alpha: 0.12)
          : tokens.surfaceMuted.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('fontroom-card-${family ?? 'system'}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          EditorHaptics.tap();
          onTap(context);
        },
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? tokens.accent.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: Directionality(
                    textDirection: direction,
                    child: Text(
                      specimen,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: family,
                        fontFamilyFallback: const <String>[],
                        fontSize: 24,
                        height: 1.1,
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? tokens.accent : tokens.textSecondary,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(AppIcons.confirm, size: 14, color: tokens.accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
