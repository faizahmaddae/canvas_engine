import 'package:flutter/material.dart';

import '../../features/templates/domain/template.dart';
import '../../features/templates/presentation/template_preview.dart';
import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';

/// Rounded template card (design doc §4) — category-colour fill, a
/// mini live preview, and a label. Reused on Home, Templates browse,
/// and the welcome screen's showcase.
///
/// Flat by default (design doc §3: "colour blocks do the work, no
/// decorative shadows") — the vivid category fill is the entire
/// visual treatment. [boxShadow] is an opt-in escape hatch for the
/// one surface that floats the cards free of any backing panel (the
/// welcome hero, where a soft drop shadow reads them as lifted off
/// the colour block); it defaults to none so every other consumer
/// stays flat.
class TemplateThumb extends StatelessWidget {
  const TemplateThumb({
    super.key,
    required this.template,
    this.width = 96,
    this.height = 128,
    this.borderRadius = AppRadii.button,
    this.boxShadow,
    this.outlined = false,
  });

  final Template template;
  final double width;
  final double height;

  /// Card corner radius. Defaults to [AppRadii.button] (12) — design
  /// doc §3's "thumb: 12". The welcome showcase passes 16.
  final double borderRadius;

  /// Optional drop shadow for floating (panel-free) placements. Null
  /// keeps the card flat.
  final List<BoxShadow>? boxShadow;

  /// Quiet variant for dense browsers: hairline surface card with a
  /// near-full-bleed preview and a muted caption — the preview IS
  /// the card. The default (filled) variant keeps the category-
  /// colour frame for teaser rails, where the accent encodes
  /// meaning at a glance.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final fill = outlined
        ? tokens.surface
        : _categoryFill(template.category, tokens);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(borderRadius),
          border: outlined ? Border.all(color: tokens.border) : null,
          boxShadow: boxShadow,
        ),
        child: Padding(
          padding: EdgeInsets.all(outlined ? 3 : 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TemplatePreview(
                  template: template,
                  borderRadius: borderRadius - 4,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: outlined ? 4 : 0,
                ),
                child: Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: outlined ? tokens.textSecondary : tokens.onBrand,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
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
