import 'package:flutter/material.dart';

import '../../features/templates/domain/template.dart';
import '../../features/templates/presentation/template_preview.dart';
import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';

/// Rounded template card (design doc §4) — category-colour fill, a
/// mini live preview, and a label. Reused on Home, Templates browse,
/// and the welcome screen's showcase.
///
/// Flat by design (design doc §3: "colour blocks do the work, no
/// decorative shadows") — the vivid category fill is the entire
/// visual treatment, no elevation.
class TemplateThumb extends StatelessWidget {
  const TemplateThumb({
    super.key,
    required this.template,
    this.width = 96,
    this.height = 128,
  });

  final Template template;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final fill = _categoryFill(template.category, tokens);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          // Design doc §3 "thumb: 12" coincides with the existing
          // button radius -- reused directly (see AppRadii doc).
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TemplatePreview(
                  template: template,
                  borderRadius: 8,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                template.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.onBrand,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps a template's category onto one of the four category
  /// accents (design doc §1: rose/saffron/teal/brand). No colour is
  /// stored on the domain model itself -- this is a presentation-only
  /// grouping, split roughly by mood: brand for
  /// promotional/commercial, rose for social/story content, saffron
  /// for editorial/warm content, teal for video/event content.
  static Color _categoryFill(TemplateCategory category, AppTokens tokens) {
    return switch (category) {
      TemplateCategory.promotionalPoster ||
      TemplateCategory.business ||
      TemplateCategory.sale => tokens.brand,
      TemplateCategory.instagramStory ||
      TemplateCategory.story ||
      TemplateCategory.social ||
      TemplateCategory.greeting => tokens.rose,
      TemplateCategory.poetryPost ||
      TemplateCategory.quote ||
      TemplateCategory.motivational ||
      TemplateCategory.food => tokens.saffron,
      TemplateCategory.youtubeThumbnail ||
      TemplateCategory.event => tokens.teal,
    };
  }
}
