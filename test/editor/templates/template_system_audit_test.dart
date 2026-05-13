import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/combined_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/domain/template_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _auditReportPath = 'docs/template-system-audit.md';
const _thumbnailAspectTolerance = 0.02;

const _recommendedNextBatchIds = <String>[];

void main() {
  group('Template system audit', () {
    test('every asset template in the manifest loads and validates', () async {
      final audit = await _buildAudit();

      expect(audit.assetTemplateCount, audit.assetMetadata.length);
      expect(audit.assetManifestDuplicateIds, isEmpty);
      expect(audit.missingThumbnailIds, isEmpty);
      expect(audit.invalidThumbnailIds, isEmpty);
      expect(audit.missingLocalizedTitleIds, isEmpty);
      expect(audit.invalidCategoryOrLanguageIds, isEmpty);
      expect(audit.documentDecodeFailureIds, isEmpty);
      expect(audit.thumbnailAspectMismatchIds, isEmpty);
    });

    test(
      'every asset document decodes and every thumbnail is an image',
      () async {
        final audit = await _buildAudit();

        for (final metadata in audit.assetMetadata) {
          final document = audit.documentsById[metadata.id];
          expect(document, isNotNull, reason: metadata.id);
          expect(document!.width, greaterThan(0), reason: metadata.id);
          expect(document.height, greaterThan(0), reason: metadata.id);
          expect(document.layers, isNotEmpty, reason: metadata.id);

          final thumbnail = audit.thumbnailsById[metadata.id];
          expect(thumbnail, isNotNull, reason: metadata.id);
          expect(thumbnail!.width, greaterThan(0), reason: metadata.id);
          expect(thumbnail.height, greaterThan(0), reason: metadata.id);
        }
      },
    );

    test('combined templates have unique final ids', () async {
      final audit = await _buildAudit();
      final finalIds = audit.combinedTemplates.map((template) => template.id);

      expect(finalIds.toSet(), hasLength(finalIds.length));
      expect(
        audit.combinedTemplateCount,
        audit.legacyTemplateCount + audit.assetOnlyIds.length,
      );
    });

    test('duplicate replacements are intentional and warned', () async {
      final audit = await _buildAudit();

      expect(audit.replacedByAssetIds, isNotEmpty);
      expect(
        audit.combinedWarnings,
        hasLength(audit.replacedByAssetIds.length),
      );
      for (final id in audit.replacedByAssetIds) {
        expect(
          audit.combinedWarnings,
          contains(contains('Duplicate template id "$id"')),
          reason: id,
        );
      }
    });

    test('legacy fallback still works when asset loading fails', () async {
      final legacyTemplates = TemplateCatalog.all.take(4).toList();
      final repository = CombinedTemplateRepository(
        assetRepository: AssetTemplateRepository(bundle: _FailingAssetBundle()),
        legacyTemplates: legacyTemplates,
      );

      final result = await repository.loadTemplateResult();

      expect(result.templates.map((template) => template.id), [
        for (final template in legacyTemplates) template.id,
      ]);
      expect(
        result.warnings.single,
        contains('Asset template loading failed; using legacy templates only'),
      );
    });

    test('developer migration report is up to date', () async {
      final audit = await _buildAudit();
      final expected = _formatMarkdownReport(audit);

      expect(File(_auditReportPath).readAsStringSync(), expected);
    });
  });
}

Future<_TemplateSystemAudit> _buildAudit() async {
  final manifestSource = _assetText(
    AssetTemplateRepository.defaultManifestPath,
  );
  final manifest = TemplateAssetManifest.fromJson(_jsonObject(manifestSource));
  final repository = AssetTemplateRepository(bundle: _assetBundle());
  final assetMetadata = await repository.loadTemplateMetadata();
  final combinedRepository = CombinedTemplateRepository(
    assetRepository: repository,
    legacyTemplates: TemplateCatalog.all,
  );
  final combinedResult = await combinedRepository.loadTemplateResult();

  final legacyIds = [for (final template in TemplateCatalog.all) template.id];
  final legacyIdsSet = legacyIds.toSet();
  final assetIds = [for (final metadata in assetMetadata) metadata.id];
  final assetIdsSet = assetIds.toSet();
  final replacedByAssetIds = [
    for (final id in legacyIds)
      if (assetIdsSet.contains(id)) id,
  ];
  final legacyOnlyIds = [
    for (final id in legacyIds)
      if (!assetIdsSet.contains(id)) id,
  ];
  final assetOnlyIds = [
    for (final id in assetIds)
      if (!legacyIdsSet.contains(id)) id,
  ];

  final missingThumbnailIds = <String>[];
  final invalidThumbnailIds = <String>[];
  final missingLocalizedTitleIds = <String>[];
  final invalidCategoryOrLanguageIds = <String>[];
  final documentDecodeFailureIds = <String>[];
  final thumbnailAspectMismatchIds = <String>[];
  final documentsById = <String, EditorDocument>{};
  final thumbnailsById = <String, img.Image>{};

  for (var index = 0; index < manifest.templates.length; index++) {
    final metadataPath = manifest.templates[index];
    final rawMetadata = _jsonObject(_assetText(metadataPath));
    final id = rawMetadata['id'] is String
        ? rawMetadata['id'] as String
        : 'manifest[$index]';
    _auditLocalizedTitle(
      id: id,
      rawMetadata: rawMetadata,
      missingLocalizedTitleIds: missingLocalizedTitleIds,
    );
    _auditCategoryAndLanguage(
      id: id,
      rawMetadata: rawMetadata,
      invalidCategoryOrLanguageIds: invalidCategoryOrLanguageIds,
    );
  }

  for (final metadata in assetMetadata) {
    final document = _decodeDocument(
      metadata: metadata,
      documentDecodeFailureIds: documentDecodeFailureIds,
    );
    if (document != null) documentsById[metadata.id] = document;

    final thumbnail = _decodeThumbnail(
      metadata: metadata,
      missingThumbnailIds: missingThumbnailIds,
      invalidThumbnailIds: invalidThumbnailIds,
    );
    if (thumbnail != null) thumbnailsById[metadata.id] = thumbnail;

    if (document != null && thumbnail != null) {
      final documentAspect = document.width / document.height;
      final thumbnailAspect = thumbnail.width / thumbnail.height;
      if ((documentAspect - thumbnailAspect).abs() >
          _thumbnailAspectTolerance) {
        thumbnailAspectMismatchIds.add(metadata.id);
      }
    }
  }

  return _TemplateSystemAudit(
    manifest: manifest,
    assetMetadata: assetMetadata,
    legacyTemplates: TemplateCatalog.all,
    combinedTemplates: combinedResult.templates,
    combinedWarnings: combinedResult.warnings,
    assetManifestDuplicateIds: _duplicates(assetIds),
    replacedByAssetIds: replacedByAssetIds,
    legacyOnlyIds: legacyOnlyIds,
    assetOnlyIds: assetOnlyIds,
    missingThumbnailIds: missingThumbnailIds,
    invalidThumbnailIds: invalidThumbnailIds,
    missingLocalizedTitleIds: missingLocalizedTitleIds,
    invalidCategoryOrLanguageIds: invalidCategoryOrLanguageIds,
    documentDecodeFailureIds: documentDecodeFailureIds,
    thumbnailAspectMismatchIds: thumbnailAspectMismatchIds,
    documentsById: documentsById,
    thumbnailsById: thumbnailsById,
  );
}

void _auditLocalizedTitle({
  required String id,
  required Map<String, dynamic> rawMetadata,
  required List<String> missingLocalizedTitleIds,
}) {
  final rawTitle = rawMetadata['title'];
  if (rawTitle is! Map) {
    missingLocalizedTitleIds.add(id);
    return;
  }
  final title = Map<String, dynamic>.from(rawTitle);
  final hasEnglish =
      title['en'] is String && (title['en'] as String).trim().isNotEmpty;
  final hasPersian =
      title['fa'] is String && (title['fa'] as String).trim().isNotEmpty;
  if (!hasEnglish || !hasPersian) missingLocalizedTitleIds.add(id);
}

void _auditCategoryAndLanguage({
  required String id,
  required Map<String, dynamic> rawMetadata,
  required List<String> invalidCategoryOrLanguageIds,
}) {
  final category = rawMetadata['category'];
  final language = rawMetadata['contentLanguage'];
  final categoryValid =
      category is String &&
      TemplateCategory.values.any((value) => value.name == category);
  final languageValid =
      language is String &&
      TemplateLanguage.values.any((value) => value.name == language);
  if (!categoryValid || !languageValid) invalidCategoryOrLanguageIds.add(id);
}

EditorDocument? _decodeDocument({
  required TemplateAssetMetadata metadata,
  required List<String> documentDecodeFailureIds,
}) {
  try {
    return DocumentCodec.decode(_assetText(metadata.documentPath));
  } catch (_) {
    documentDecodeFailureIds.add(metadata.id);
    return null;
  }
}

img.Image? _decodeThumbnail({
  required TemplateAssetMetadata metadata,
  required List<String> missingThumbnailIds,
  required List<String> invalidThumbnailIds,
}) {
  final file = File(metadata.thumbnailPath);
  if (!file.existsSync()) {
    missingThumbnailIds.add(metadata.id);
    return null;
  }
  final extension = metadata.thumbnailPath.split('.').last.toLowerCase();
  if (!{'png', 'jpg', 'jpeg', 'webp'}.contains(extension)) {
    invalidThumbnailIds.add(metadata.id);
    return null;
  }
  final image = img.decodeImage(file.readAsBytesSync());
  if (image == null) {
    invalidThumbnailIds.add(metadata.id);
    return null;
  }
  return image;
}

List<String> _duplicates(List<String> values) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final value in values) {
    if (!seen.add(value)) duplicates.add(value);
  }
  return duplicates.toList(growable: false);
}

String _formatMarkdownReport(_TemplateSystemAudit audit) {
  final buffer = StringBuffer()
    ..writeln('# Template System Audit')
    ..writeln()
    ..writeln(
      'This report is generated from `TemplateCatalog.all` and `assets/templates/manifest.json`.',
    )
    ..writeln(
      'Run `flutter test test/editor/templates/template_system_audit_test.dart` after template changes.',
    )
    ..writeln()
    ..writeln('## Counts')
    ..writeln()
    ..writeln('| Metric | Count |')
    ..writeln('|---|---:|')
    ..writeln(
      '| Legacy TemplateCatalog templates | ${audit.legacyTemplateCount} |',
    )
    ..writeln('| Asset JSON templates | ${audit.assetTemplateCount} |')
    ..writeln('| Combined templates | ${audit.combinedTemplateCount} |')
    ..writeln(
      '| Asset replacements of legacy IDs | ${audit.replacedByAssetIds.length} |',
    )
    ..writeln(
      '| Legacy-only templates remaining | ${audit.legacyOnlyIds.length} |',
    )
    ..writeln('| Asset-only templates | ${audit.assetOnlyIds.length} |')
    ..writeln()
    ..writeln('## Migrated JSON Templates')
    ..writeln()
    ..write(_templateList(audit, audit.replacedByAssetIds))
    ..writeln()
    ..writeln('## Asset-Only Templates')
    ..writeln()
    ..write(_templateList(audit, audit.assetOnlyIds))
    ..writeln()
    ..writeln('## Remaining Legacy Templates')
    ..writeln()
    ..write(_legacyList(audit, audit.legacyOnlyIds))
    ..writeln()
    ..writeln('## Recommended Next Migration Batch')
    ..writeln()
    ..write(_legacyList(audit, _recommendedNextBatch(audit)))
    ..writeln()
    ..writeln('## Validation Summary')
    ..writeln()
    ..writeln(
      '- Duplicate asset IDs in manifest: ${_noneOrIds(audit.assetManifestDuplicateIds)}',
    )
    ..writeln(
      '- Duplicate legacy/asset IDs replaced intentionally: ${_noneOrIds(audit.replacedByAssetIds)}',
    )
    ..writeln(
      '- Templates missing thumbnail: ${_noneOrIds(audit.missingThumbnailIds)}',
    )
    ..writeln(
      '- Templates with invalid thumbnail image/type: ${_noneOrIds(audit.invalidThumbnailIds)}',
    )
    ..writeln(
      '- Templates missing localized title: ${_noneOrIds(audit.missingLocalizedTitleIds)}',
    )
    ..writeln(
      '- Templates with invalid category/language: ${_noneOrIds(audit.invalidCategoryOrLanguageIds)}',
    )
    ..writeln(
      '- Templates whose document.json fails to decode: ${_noneOrIds(audit.documentDecodeFailureIds)}',
    )
    ..writeln(
      '- Templates whose thumbnail aspect ratio does not match document: ${_noneOrIds(audit.thumbnailAspectMismatchIds)}',
    );
  return buffer.toString();
}

String _templateList(_TemplateSystemAudit audit, List<String> ids) {
  if (ids.isEmpty) return '- None\n';
  final buffer = StringBuffer();
  for (final id in ids) {
    final metadata = audit.metadataById[id];
    if (metadata == null) {
      buffer.writeln('- `$id`');
      continue;
    }
    buffer.writeln(
      '- `$id` — ${metadata.categoryId}, ${metadata.contentLanguageId}',
    );
  }
  return buffer.toString();
}

String _legacyList(_TemplateSystemAudit audit, List<String> ids) {
  if (ids.isEmpty) return '- None\n';
  final buffer = StringBuffer();
  for (final id in ids) {
    final template = audit.legacyById[id];
    if (template == null) {
      buffer.writeln('- `$id`');
      continue;
    }
    buffer.writeln(
      '- `$id` — ${template.category.name}, ${template.language.name}',
    );
  }
  return buffer.toString();
}

List<String> _recommendedNextBatch(_TemplateSystemAudit audit) {
  final remaining = audit.legacyOnlyIds.toSet();
  return [
    for (final id in _recommendedNextBatchIds)
      if (remaining.contains(id)) id,
  ];
}

String _noneOrIds(List<String> ids) {
  if (ids.isEmpty) return 'none';
  return ids.map((id) => '`$id`').join(', ');
}

class _TemplateSystemAudit {
  const _TemplateSystemAudit({
    required this.manifest,
    required this.assetMetadata,
    required this.legacyTemplates,
    required this.combinedTemplates,
    required this.combinedWarnings,
    required this.assetManifestDuplicateIds,
    required this.replacedByAssetIds,
    required this.legacyOnlyIds,
    required this.assetOnlyIds,
    required this.missingThumbnailIds,
    required this.invalidThumbnailIds,
    required this.missingLocalizedTitleIds,
    required this.invalidCategoryOrLanguageIds,
    required this.documentDecodeFailureIds,
    required this.thumbnailAspectMismatchIds,
    required this.documentsById,
    required this.thumbnailsById,
  });

  final TemplateAssetManifest manifest;
  final List<TemplateAssetMetadata> assetMetadata;
  final List<Template> legacyTemplates;
  final List<Template> combinedTemplates;
  final List<String> combinedWarnings;
  final List<String> assetManifestDuplicateIds;
  final List<String> replacedByAssetIds;
  final List<String> legacyOnlyIds;
  final List<String> assetOnlyIds;
  final List<String> missingThumbnailIds;
  final List<String> invalidThumbnailIds;
  final List<String> missingLocalizedTitleIds;
  final List<String> invalidCategoryOrLanguageIds;
  final List<String> documentDecodeFailureIds;
  final List<String> thumbnailAspectMismatchIds;
  final Map<String, EditorDocument> documentsById;
  final Map<String, img.Image> thumbnailsById;

  int get legacyTemplateCount => legacyTemplates.length;
  int get assetTemplateCount => manifest.templates.length;
  int get combinedTemplateCount => combinedTemplates.length;

  Map<String, TemplateAssetMetadata> get metadataById => {
    for (final metadata in assetMetadata) metadata.id: metadata,
  };

  Map<String, Template> get legacyById => {
    for (final template in legacyTemplates) template.id: template,
  };
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final source = assets[key];
    if (source == null) {
      throw StateError('Missing test asset $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final source = assets[key];
    if (source == null) {
      throw StateError('Missing test asset $key');
    }
    return source;
  }
}

class _FailingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    throw StateError('Asset bundle is unavailable');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    throw StateError('Asset bundle is unavailable');
  }
}

_MemoryAssetBundle _assetBundle() {
  final manifestSource = _assetText(
    AssetTemplateRepository.defaultManifestPath,
  );
  final manifest = TemplateAssetManifest.fromJson(_jsonObject(manifestSource));
  final assets = <String, String>{
    AssetTemplateRepository.defaultManifestPath: manifestSource,
  };

  for (final metadataPath in manifest.templates) {
    final metadataSource = _assetText(metadataPath);
    final metadata = TemplateAssetMetadata.fromJson(
      _jsonObject(metadataSource),
    );
    assets[metadataPath] = metadataSource;
    assets[metadata.documentPath] = _assetText(metadata.documentPath);
  }

  return _MemoryAssetBundle(assets);
}

String _assetText(String path) => File(path).readAsStringSync();

Map<String, dynamic> _jsonObject(String source) {
  return Map<String, dynamic>.from(jsonDecode(source) as Map);
}
