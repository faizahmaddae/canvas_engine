// Font picker panel (Phase 2A commit 2): extracted verbatim from the
// text_mode_toolbar part-file library. Rename-only promotions for the
// symbols that cross files; everything else stays private.
//
// tb2 12/16: apply-on-highlight live preview. The first tap on a row
// HIGHLIGHTS it (stages the family on the caller's preview channel —
// a style-drag session on the live overlay — so the canvas behind
// the whisper barrier shows the real layer in the candidate font);
// tapping the highlighted row again PICKS it. Dismissing without
// picking reverts (the caller cancels the session; zero history
// entries).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_tokens.dart';
import '../../../../../../core/utils/haptics.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../text/domain/font_catalog.dart';
import '../../../widgets/editor_modal_sheet.dart';
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
  final result = await showEditorSheet<FontPickResult>(
    context,
    barrier: EditorSheetBarrier.whisper,
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
        if (specimen != null) ...[
          const SizedBox(height: 8),
          // Specimen strip: the user's own words in the highlighted
          // face (excerpt-capped, §8). One line — the canvas behind
          // the whisper barrier is the full-fidelity preview.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.surfaceMuted.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              specimen,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: _highlighted != null
                    ? _highlighted!.$1
                    : widget.current,
                fontSize: 16,
                color: tokens.textPrimary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Flexible(
          child: _FontPickerList(
            current: widget.current,
            highlighted: _highlighted,
            script: _script,
            onRowTap: _onRowTap,
          ),
        ),
      ],
    );
  }
}

class _FontPickerList extends StatelessWidget {
  const _FontPickerList({
    required this.current,
    required this.highlighted,
    required this.script,
    required this.onRowTap,
  });

  final String? current;

  /// Sentinel-wrapped highlighted family (see [_FontPickerSheetState]).
  final (String?,)? highlighted;

  /// Row tap handler owned by the sheet state (highlight vs pick).
  final void Function(BuildContext ctx, String? family, FontPickResult result)
  onRowTap;

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
          localizedFontCategoryLabel(l10n, script, category),
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
        // Highlight (in-flight preview) wins the selected treatment;
        // before any highlight, the layer's current family shows it.
        final selected = highlighted != null
            ? highlighted!.$1 == family
            : family == current;
        return Material(
          color: selected
              ? tokens.accent.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onRowTap(
              ctx,
              family,
              item.entry == null
                  ? FontPickResult.systemDefault
                  : FontPickResult._(family, false),
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
                    Icon(AppIcons.confirm, size: 18, color: tokens.accent),
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
