import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/combined_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _migratedTemplateIds = <String>{
  'fa_insta_story_v1',
  'fa_promo_v1',
  'fa_poetry_overlay_v1',
  'en_yt_thumb_v1',
  'en_announcement',
  'fa_quote_minimal',
  'en_quote_editorial_gradient',
  'fa_poetry_v1',
  'en_quote_minimal',
  'fa_story_warm_pastel',
  'fa_insta_story_bold_word_v1',
  'fa_poetry_minimal_v1',
  'fa_promo_sale_v1',
  'fa_insta_story_announcement_v1',
  'fa_insta_story_frame_v1',
  'fa_poetry_traditional_v1',
  'fa_promo_event_v1',
  'fa_promo_launch_v1',
  'en_sale_modern_gradient',
  'en_story_quote',
  'fa_sale_bold',
  'fa_insta_story_minimal_v1',
  'en_yt_question_v1',
  'en_yt_list_v1',
  'en_sale_bold',
  'en_birthday_confetti',
  'fa_story_quote',
  'fa_announcement',
  'en_quote_editorial',
  'fa_quote_editorial',
  'en_story_motivation',
  'en_event_market',
  'en_motivation_sunrise',
  'en_business_card_post',
  'fa_birthday',
  'fa_event',
  'fa_motivation_sunrise',
  'en_yt_reaction_v1',
  'en_yt_tutorial_v1',
  'fa_business_hiring',
  'fa_food_menu',
  'en_food_menu',
  'en_food_coffee',
  'en_sale_flash',
  'en_greeting_thanks',
  'en_business_quote',
  'en_event_concert',
  'fa_food_coffee',
  'fa_sale_flash',
  'fa_thanks',
  'fa_concert',
};

void main() {
  group('CombinedTemplateRepository', () {
    test('returns asset templates by default', () async {
      final repository = CombinedTemplateRepository(
        assetRepository: AssetTemplateRepository(bundle: _sampleBundle()),
      );

      final result = await repository.loadTemplateResult();
      final ids = result.templates.map((template) => template.id).toSet();
      final manifest = TemplateAssetManifest.fromJson(
        _jsonObject(_assetText(AssetTemplateRepository.defaultManifestPath)),
      );

      expect(result.warnings, isEmpty);
      expect(result.templates.length, manifest.templates.length);
      expect(ids, containsAll(_migratedTemplateIds));
      expect(ids, contains('fa_story_today'));
      expect(ids, contains('en_youtube_watch_this'));
    });

    test('explicit legacy fixtures merge behind asset templates', () async {
      final legacyTemplates = _legacyFixtures();
      final repository = CombinedTemplateRepository(
        assetRepository: AssetTemplateRepository(bundle: _sampleBundle()),
        legacyTemplates: legacyTemplates,
      );

      final result = await repository.loadTemplateResult();
      final ids = result.templates.map((template) => template.id).toSet();
      final manifest = TemplateAssetManifest.fromJson(
        _jsonObject(_assetText(AssetTemplateRepository.defaultManifestPath)),
      );

      expect(result.warnings, hasLength(2));
      for (final id in const ['en_quote_minimal', 'fa_insta_story_v1']) {
        expect(
          result.warnings,
          contains(contains('Duplicate template id "$id"')),
        );
      }
      expect(ids, contains('fa_story_today'));
      expect(ids, contains('en_youtube_watch_this'));
      expect(ids, contains('legacy_only_fixture'));
      expect(result.templates.length, manifest.templates.length + 1);
      expect(result.templates.take(3).map((template) => template.id), [
        'en_quote_minimal',
        'legacy_only_fixture',
        'fa_insta_story_v1',
      ]);
    });

    test('duplicate ids prefer asset templates and expose a warning', () async {
      final warnings = <String>[];
      final repository = CombinedTemplateRepository(
        assetRepository: AssetTemplateRepository(bundle: _duplicateIdBundle()),
        legacyTemplates: [_legacyFixture(id: 'en_quote_minimal')],
        onWarning: warnings.add,
      );

      final result = await repository.loadTemplateResult();
      final templatesWithDuplicateId = result.templates
          .where((template) => template.id == 'en_quote_minimal')
          .toList();
      final selected = templatesWithDuplicateId.single;

      expect(selected.name, 'Asset override');
      expect(selected.category, TemplateCategory.youtubeThumbnail);
      expect(selected.language, TemplateLanguage.english);
      expect(selected.build().width, 1280);
      expect(
        result.warnings,
        contains(contains('Duplicate template id "en_quote_minimal"')),
      );
      expect(warnings, result.warnings);
    });

    test('asset load failure falls back to legacy templates', () async {
      final legacyTemplates = _legacyFixtures();
      final warnings = <String>[];
      final repository = CombinedTemplateRepository(
        assetRepository: AssetTemplateRepository(bundle: _FailingAssetBundle()),
        legacyTemplates: legacyTemplates,
        onWarning: warnings.add,
      );

      final result = await repository.loadTemplateResult();

      expect(result.templates.map((template) => template.id), [
        for (final template in legacyTemplates) template.id,
      ]);
      expect(
        result.warnings.single,
        contains('Asset template loading failed; using legacy templates only'),
      );
      expect(warnings, result.warnings);
    });

    test('asset load failure without legacy fallback returns empty', () async {
      final warnings = <String>[];
      final repository = CombinedTemplateRepository(
        assetRepository: AssetTemplateRepository(bundle: _FailingAssetBundle()),
        onWarning: warnings.add,
      );

      final result = await repository.loadTemplateResult();

      expect(result.templates, isEmpty);
      expect(
        result.warnings.single,
        contains(
          'Asset template loading failed; no fallback templates available',
        ),
      );
      expect(warnings, result.warnings);
    });

    test('build returns a fresh EditorDocument', () async {
      final repository = CombinedTemplateRepository(
        assetRepository: AssetTemplateRepository(bundle: _sampleBundle()),
      );

      final templates = await repository.loadTemplates();
      final assetTemplate = templates.firstWhere(
        (template) => template.id == 'fa_story_today',
      );

      final firstBuild = assetTemplate.build();
      final secondBuild = assetTemplate.build();

      expect(identical(firstBuild, secondBuild), isFalse);
      expect(firstBuild.width, 1080);
      expect(firstBuild.height, 1920);
    });

    test('content language remains independent from app locale', () async {
      final repository = CombinedTemplateRepository(
        assetRepository: AssetTemplateRepository(bundle: _sampleBundle()),
      );

      final templates = await repository.loadTemplates(titleLocale: 'fa');
      final englishTemplate = templates.firstWhere(
        (template) => template.id == 'en_youtube_watch_this',
      );

      expect(englishTemplate.name, 'این ویدئو را ببینید');
      expect(englishTemplate.language, TemplateLanguage.english);
    });

    test(
      'invalid asset schema does not fall back to legacy templates',
      () async {
        final repository = CombinedTemplateRepository(
          assetRepository: AssetTemplateRepository(
            bundle: _invalidMetadataSchemaBundle(),
          ),
        );

        expect(
          () => repository.loadTemplateResult(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('unsupported template metadata schemaVersion 99'),
            ),
          ),
        );
      },
    );
  });
}

List<Template> _legacyFixtures() => [
  _legacyFixture(id: 'en_quote_minimal', name: 'Legacy quote'),
  _legacyFixture(id: 'legacy_only_fixture', name: 'Legacy only fixture'),
  _legacyFixture(
    id: 'fa_insta_story_v1',
    name: 'Legacy story',
    language: TemplateLanguage.persian,
    category: TemplateCategory.instagramStory,
    width: 1080,
    height: 1920,
  ),
];

Template _legacyFixture({
  required String id,
  String name = 'Legacy fixture',
  TemplateCategory category = TemplateCategory.quote,
  TemplateLanguage language = TemplateLanguage.english,
  double width = 1080,
  double height = 1080,
}) {
  return Template(
    id: id,
    name: name,
    category: category,
    language: language,
    build: () => EditorDocument(width: width, height: height, layers: const []),
  );
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

_MemoryAssetBundle _sampleBundle({Map<String, String> overrides = const {}}) {
  final manifestSource = _assetText(
    AssetTemplateRepository.defaultManifestPath,
  );
  final manifest = TemplateAssetManifest.fromJson(_jsonObject(manifestSource));
  final assets = <String, String>{
    AssetTemplateRepository.defaultManifestPath: manifestSource,
  };

  for (final metadataPath in manifest.templates) {
    final originalMetadataSource = _assetText(metadataPath);
    final metadataSource = overrides[metadataPath] ?? originalMetadataSource;
    final metadata = TemplateAssetMetadata.fromJson(
      _jsonObject(originalMetadataSource),
    );
    assets[metadataPath] = metadataSource;
    assets[metadata.documentPath] = _assetText(metadata.documentPath);
  }

  return _MemoryAssetBundle(assets);
}

_MemoryAssetBundle _duplicateIdBundle() {
  const metadataPath = 'assets/templates/en_quote_minimal/template.json';
  final json = _jsonObject(_assetText(metadataPath));
  json['title'] = <String, String>{
    'en': 'Asset override',
    'fa': 'جایگزین دارایی',
  };
  json['category'] = 'youtubeThumbnail';
  json['document'] =
      'assets/templates/samples/en_youtube_watch_this/document.json';
  return _sampleBundle(overrides: {metadataPath: _prettyJson(json)});
}

_MemoryAssetBundle _invalidMetadataSchemaBundle() {
  const metadataPath = 'assets/templates/samples/fa_story_today/template.json';
  final json = _jsonObject(_assetText(metadataPath));
  json['schemaVersion'] = 99;
  return _sampleBundle(overrides: {metadataPath: _prettyJson(json)});
}

String _assetText(String path) => File(path).readAsStringSync();

Map<String, dynamic> _jsonObject(String source) {
  return Map<String, dynamic>.from(jsonDecode(source) as Map);
}

String _prettyJson(Map<String, dynamic> json) {
  return const JsonEncoder.withIndent('  ').convert(json);
}
