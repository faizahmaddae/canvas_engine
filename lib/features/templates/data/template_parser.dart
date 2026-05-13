import 'package:flutter/foundation.dart';

import '../../editor/engine/core/editor_document.dart';
import '../../editor/engine/serialization/document_codec.dart';
import '../domain/template.dart';
import 'template_manifest.dart';

@immutable
class AssetTemplateRecord {
  const AssetTemplateRecord({
    required this.metadata,
    required this.documentSource,
    required this.template,
  });

  final TemplateAssetMetadata metadata;
  final String documentSource;
  final Template template;

  EditorDocument buildDocument() => template.build();
}

class TemplateParser {
  const TemplateParser();

  AssetTemplateRecord parseAssetTemplate({
    required TemplateAssetMetadata metadata,
    required String documentSource,
    String titleLocale = 'en',
  }) {
    final category = parseCategoryId(metadata.categoryId);
    final language = parseContentLanguageId(metadata.contentLanguageId);
    decodeDocument(documentSource);

    return AssetTemplateRecord(
      metadata: metadata,
      documentSource: documentSource,
      template: Template(
        id: metadata.id,
        name: metadata.title.resolve(titleLocale),
        thumbnailPath: metadata.thumbnailPath,
        category: category,
        language: language,
        build: () => decodeDocument(documentSource),
      ),
    );
  }

  EditorDocument decodeDocument(String documentSource) {
    return DocumentCodec.decode(documentSource);
  }

  TemplateCategory parseCategoryId(String categoryId) {
    for (final category in TemplateCategory.values) {
      if (category.name == categoryId) return category;
    }
    throw FormatException('unknown template category "$categoryId"');
  }

  TemplateLanguage parseContentLanguageId(String contentLanguageId) {
    for (final language in TemplateLanguage.values) {
      if (language.name == contentLanguageId) return language;
    }
    throw FormatException(
      'unknown template contentLanguage "$contentLanguageId"',
    );
  }
}
