import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../templates/domain/template.dart';
import '../../../templates/presentation/template_preview.dart';
import 'home_style.dart';

/// Single template tile rendered inside a category row.
///
/// Width is derived from each template's native aspect ratio (kept
/// within [minWidth] / [maxWidth]) so square posts read square and
/// stories read tall — matches the artboard the user will land in
/// after tapping it.
class TemplateCard extends StatelessWidget {
  const TemplateCard({
    super.key,
    required this.template,
    required this.onTap,
    this.height = 160,
    this.minWidth = 110,
    this.maxWidth = 180,
    this.aspectRatioOverride,
  });

  final Template template;
  final VoidCallback onTap;
  final double height;
  final double minWidth;
  final double maxWidth;

  /// When set, the thumbnail is rendered at this aspect ratio
  /// instead of the template's native artboard aspect. Used by the
  /// home rows to keep mixed-format categories (square + portrait)
  /// on a uniform rhythm. The artboard's real aspect still applies
  /// once the user enters the editor.
  final double? aspectRatioOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final doc = template.build();
    final nativeAspect = doc.width / doc.height;
    final aspect = aspectRatioOverride ?? nativeAspect;
    final thumbnailWidth = (height * aspect).clamp(minWidth, maxWidth);
    final framePadding = AppSpacing.xs * 2;

    return SizedBox(
      key: ValueKey<String>('template-card-size-${template.id}'),
      width: thumbnailWidth + framePadding,
      child: Semantics(
        button: true,
        label: l10n.openTemplateSemantics(template.name),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: HomePalette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: HomePalette.hairline.withValues(alpha: 0.62),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: HomePalette.shadow.withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        key: ValueKey<String>(
                          'template-card-thumbnail-${template.id}',
                        ),
                        width: thumbnailWidth,
                        height: height,
                        child: TemplatePreview(
                          template: template,
                          borderRadius: 12,
                          fit: template.thumbnailPath == null
                              ? BoxFit.contain
                              : BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _displayName(context, l10n, template),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: HomePalette.ink,
                    height: 1.18,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  _languageLabel(l10n, template.language),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: HomePalette.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _displayName(
  BuildContext context,
  AppLocalizations l10n,
  Template template,
) {
  if (Localizations.localeOf(context).languageCode != 'fa') {
    return template.name;
  }
  return switch (template.id) {
    'en_yt_thumb_v1' => l10n.categoryYoutubeThumbnail,
    'en_yt_question_v1' => l10n.categoryYoutubeThumbnail,
    'en_yt_list_v1' => l10n.categoryYoutubeThumbnail,
    'en_yt_reaction_v1' => l10n.categoryYoutubeThumbnail,
    'en_yt_tutorial_v1' => l10n.categoryYoutubeThumbnail,
    'en_quote_editorial_gradient' => l10n.categoryQuote,
    'en_quote_editorial' => l10n.categoryQuote,
    'en_quote_minimal' => l10n.categoryQuote,
    _ => template.name,
  };
}

String _languageLabel(AppLocalizations l10n, TemplateLanguage language) =>
    switch (language) {
      TemplateLanguage.english => l10n.templateLanguageEnglish,
      TemplateLanguage.persian => l10n.templateLanguagePersian,
    };
