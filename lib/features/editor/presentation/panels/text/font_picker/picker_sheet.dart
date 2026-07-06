// Font picker panel (Phase 2A commit 2): extracted verbatim from the
// text_mode_toolbar part-file library. Rename-only promotions for the
// symbols that cross files; everything else stays private.

import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_tokens.dart';
import '../../../../../../core/utils/haptics.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../text/domain/font_catalog.dart';
import 'tabs.dart';

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
}) async {
  final result = await showModalBottomSheet<FontPickResult>(
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
  return result ?? FontPickResult.unchanged;
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
