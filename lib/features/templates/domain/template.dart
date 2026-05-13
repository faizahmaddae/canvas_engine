import 'package:flutter/foundation.dart';

import '../../editor/engine/core/editor_document.dart';

/// Loose grouping shown as filter chips on the templates browse
/// screen. Keep the list short — categories are a navigation aid,
/// not a taxonomy.
enum TemplateCategory {
  instagramStory('Instagram Story'),
  youtubeThumbnail('YouTube Thumbnail'),
  poetryPost('پست شاعرانه'),
  promotionalPoster('پوستر تبلیغاتی'),
  social('Social'),
  story('Story'),
  quote('Quote'),
  sale('Sale'),
  greeting('Greeting'),
  business('Business'),
  event('Event'),
  food('Food'),
  motivational('Motivation');

  const TemplateCategory(this.label);
  final String label;
}

/// Primary script / language of a template.
///
/// Templates are authored in either English (LTR, Latin fonts) or
/// Persian (RTL, Persian fonts shipped under `assets/fonts/farsi`).
/// The browse screen surfaces these as two top-level sections so a
/// user picking a starter design never has to wade through the
/// other language to find theirs.
enum TemplateLanguage {
  english('English'),
  persian('فارسی');

  const TemplateLanguage(this.label);
  final String label;
}

/// A single starter design entry.
///
/// Production templates are parsed from JSON assets. The deprecated
/// `TemplateCatalog` still creates the same model temporarily for migration and
/// audit tests. The [build] callback returns a fresh [EditorDocument] every
/// time the template is opened - never share instances, since opening a
/// template seeds an editing session that the user is free to mutate.
@immutable
class Template {
  const Template({
    required this.id,
    required this.name,
    required this.category,
    required this.language,
    required this.build,
    this.thumbnailPath,
  });

  /// Stable id. Used for analytics + as a thumbnail cache key.
  final String id;

  /// Short, user-facing name shown under the thumbnail.
  final String name;

  /// Optional bundled raster thumbnail for asset-backed templates.
  /// Legacy Dart templates leave this null and keep using the live
  /// document renderer for previews.
  final String? thumbnailPath;

  final TemplateCategory category;

  /// Primary script of the template's text content. Drives section
  /// grouping in the browse UI.
  final TemplateLanguage language;

  /// Constructs the seed document. Called every time the user opens
  /// the template — the result is then handed to
  /// [DocumentController] like any other freshly-created project.
  final EditorDocument Function() build;
}
