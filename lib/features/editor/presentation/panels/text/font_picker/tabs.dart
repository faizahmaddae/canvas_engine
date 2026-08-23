// Font picker panel (Phase 2A commit 2): extracted verbatim from the
// text_mode_toolbar part-file library. Rename-only promotions for the
// symbols that cross files; everything else stays private.

import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_tokens.dart';
import '../../../../../../l10n/app_localizations.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../text/domain/font_catalog.dart';

String localizedFontCategoryLabel(
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

/// Two-pill script toggle (فارسی / English) sitting at the top-right
/// of the Font panel. Intentionally *quiet*: a tinted track with a
/// soft pill highlight on the active option. The previous design
/// was a full-width 38dp segmented control with onPrimary fill +
/// shadow, which competed with the font specimens for attention —
/// users perceived it as a primary action when it's actually a
/// preferences-level filter. Now sized for the language word
/// itself plus a small touch margin so it reads as a secondary
/// inline switch.
class ScriptTabSwitcher extends StatelessWidget {
  const ScriptTabSwitcher({
    super.key,
    required this.value,
    required this.onChanged,
  });

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
          // 32 (was 26): the row grew to a 40dp band so the script
          // switch stops being the panel's thinnest target.
          height: 32,
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
