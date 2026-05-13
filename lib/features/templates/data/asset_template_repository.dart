import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/template.dart';
import 'template_manifest.dart';
import 'template_parser.dart';

class AssetTemplateRepository {
  AssetTemplateRepository({
    AssetBundle? bundle,
    this.manifestPath = defaultManifestPath,
    TemplateParser parser = const TemplateParser(),
  }) : _bundle = bundle ?? rootBundle,
       _parser = parser;

  static const String defaultManifestPath = 'assets/templates/manifest.json';

  final AssetBundle _bundle;
  final TemplateParser _parser;
  final String manifestPath;

  Future<TemplateAssetManifest> loadManifest() async {
    final source = await _bundle.loadString(manifestPath);
    return TemplateAssetManifest.fromJson(
      _decodeJsonObject(source, manifestPath),
    );
  }

  Future<List<TemplateAssetMetadata>> loadTemplateMetadata() async {
    final manifest = await loadManifest();
    final metadata = <TemplateAssetMetadata>[];
    for (final metadataPath in manifest.templates) {
      metadata.add(await loadMetadataAt(metadataPath));
    }
    return List.unmodifiable(metadata);
  }

  Future<TemplateAssetMetadata> loadMetadataAt(String metadataPath) async {
    final source = await _bundle.loadString(metadataPath);
    return TemplateAssetMetadata.fromJson(
      _decodeJsonObject(source, metadataPath),
    );
  }

  Future<List<AssetTemplateRecord>> loadAssetTemplates({
    String titleLocale = 'en',
  }) async {
    final manifest = await loadManifest();
    final records = <AssetTemplateRecord>[];
    for (final metadataPath in manifest.templates) {
      final metadata = await loadMetadataAt(metadataPath);
      final documentSource = await _bundle.loadString(metadata.documentPath);
      records.add(
        _parser.parseAssetTemplate(
          metadata: metadata,
          documentSource: documentSource,
          titleLocale: titleLocale,
        ),
      );
    }
    return List.unmodifiable(records);
  }

  Future<List<Template>> loadTemplates({String titleLocale = 'en'}) async {
    final records = await loadAssetTemplates(titleLocale: titleLocale);
    return List.unmodifiable(records.map((record) => record.template));
  }

  Map<String, dynamic> _decodeJsonObject(String source, String assetPath) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException(
        'template asset "$assetPath" is not valid JSON: ${error.message}',
      );
    }
    if (decoded is! Map) {
      throw FormatException(
        'template asset "$assetPath" top-level JSON must be an object',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }
}
