import 'package:flutter/foundation.dart';

/// Asset manifest schema version for bundled templates.
///
/// This is intentionally separate from `DocumentCodec.schemaVersion`:
/// the manifest describes template packaging and metadata, while the
/// referenced document JSON keeps using the editor document schema.
const int kTemplateManifestSchemaVersion = 1;
const int kTemplateMetadataSchemaVersion = 1;

@immutable
class TemplateAssetManifest {
  const TemplateAssetManifest({
    required this.schemaVersion,
    required this.templates,
  });

  final int schemaVersion;
  final List<String> templates;

  factory TemplateAssetManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _schemaVersion(json, 'template manifest');
    if (schemaVersion != kTemplateManifestSchemaVersion) {
      throw FormatException(
        'unsupported template manifest schemaVersion $schemaVersion '
        '(supported: $kTemplateManifestSchemaVersion)',
      );
    }

    final rawTemplates = json['templates'];
    if (rawTemplates is! List) {
      throw const FormatException('template manifest templates must be a list');
    }

    final templates = <String>[];
    for (var index = 0; index < rawTemplates.length; index++) {
      final rawPath = rawTemplates[index];
      if (rawPath is! String || rawPath.trim().isEmpty) {
        throw FormatException(
          'template manifest templates[$index] must be a non-empty string',
        );
      }
      templates.add(rawPath);
    }

    return TemplateAssetManifest(
      schemaVersion: schemaVersion,
      templates: List.unmodifiable(templates),
    );
  }
}

@immutable
class TemplateAssetMetadata {
  const TemplateAssetMetadata({
    required this.schemaVersion,
    required this.id,
    required this.title,
    required this.categoryId,
    required this.contentLanguageId,
    required this.thumbnailPath,
    required this.documentPath,
    required this.tags,
    this.home,
  });

  final int schemaVersion;
  final String id;
  final LocalizedTemplateTitle title;
  final String categoryId;
  final String contentLanguageId;
  final String thumbnailPath;
  final String documentPath;
  final List<String> tags;
  final TemplateHomeMetadata? home;

  factory TemplateAssetMetadata.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _schemaVersion(json, 'template metadata');
    if (schemaVersion != kTemplateMetadataSchemaVersion) {
      throw FormatException(
        'unsupported template metadata schemaVersion $schemaVersion '
        '(supported: $kTemplateMetadataSchemaVersion)',
      );
    }

    final rawHome = json['home'];
    if (rawHome != null && rawHome is! Map) {
      throw const FormatException('template metadata home must be an object');
    }

    return TemplateAssetMetadata(
      schemaVersion: schemaVersion,
      id: _requiredString(json, 'id'),
      title: LocalizedTemplateTitle.fromJson(json['title']),
      categoryId: _requiredString(json, 'category'),
      contentLanguageId: _requiredString(json, 'contentLanguage'),
      thumbnailPath: _requiredString(json, 'thumbnail'),
      documentPath: _requiredString(json, 'document'),
      tags: _stringList(json['tags'], 'tags'),
      home: rawHome == null
          ? null
          : TemplateHomeMetadata.fromJson(Map<String, dynamic>.from(rawHome)),
    );
  }
}

@immutable
class LocalizedTemplateTitle {
  const LocalizedTemplateTitle({required this.en, required this.fa});

  final String en;
  final String fa;

  factory LocalizedTemplateTitle.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('template metadata title must be an object');
    }
    final json = Map<String, dynamic>.from(raw);
    return LocalizedTemplateTitle(
      en: _requiredString(json, 'en'),
      fa: _requiredString(json, 'fa'),
    );
  }

  String resolve(String localeCode) {
    final normalized = localeCode.toLowerCase();
    if (normalized.startsWith('fa')) return fa;
    return en;
  }
}

@immutable
class TemplateHomeMetadata {
  const TemplateHomeMetadata({this.featured = false, this.sortOrder});

  final bool featured;
  final int? sortOrder;

  factory TemplateHomeMetadata.fromJson(Map<String, dynamic> json) {
    final rawFeatured = json['featured'];
    if (rawFeatured != null && rawFeatured is! bool) {
      throw const FormatException('template home featured must be a boolean');
    }
    final rawSortOrder = json['sortOrder'];
    if (rawSortOrder != null && rawSortOrder is! int) {
      throw const FormatException('template home sortOrder must be an integer');
    }
    return TemplateHomeMetadata(
      featured: rawFeatured as bool? ?? false,
      sortOrder: rawSortOrder as int?,
    );
  }
}

int _schemaVersion(Map<String, dynamic> json, String context) {
  final rawVersion = json['schemaVersion'];
  if (rawVersion is! int) {
    throw FormatException('$context schemaVersion must be an integer');
  }
  return rawVersion;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final rawValue = json[key];
  if (rawValue is! String || rawValue.trim().isEmpty) {
    throw FormatException('template metadata $key must be a non-empty string');
  }
  return rawValue;
}

List<String> _stringList(Object? raw, String key) {
  if (raw == null) return const <String>[];
  if (raw is! List) {
    throw FormatException('template metadata $key must be a list');
  }
  final values = <String>[];
  for (var index = 0; index < raw.length; index++) {
    final rawValue = raw[index];
    if (rawValue is! String || rawValue.trim().isEmpty) {
      throw FormatException(
        'template metadata $key[$index] must be a non-empty string',
      );
    }
    values.add(rawValue);
  }
  return List.unmodifiable(values);
}
