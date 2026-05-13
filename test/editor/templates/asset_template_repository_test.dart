import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetTemplateRepository', () {
    test('loads manifest from bundled template assets', () async {
      final repository = AssetTemplateRepository(bundle: _sampleBundle());

      final manifest = await repository.loadManifest();

      expect(manifest.schemaVersion, kTemplateManifestSchemaVersion);
      expect(
        manifest.templates,
        contains('assets/templates/samples/fa_story_today/template.json'),
      );
      expect(
        manifest.templates,
        contains(
          'assets/templates/samples/en_youtube_watch_this/template.json',
        ),
      );
    });

    test(
      'manifest template assets are bundled for rootBundle loading',
      () async {
        final manifestSource = await rootBundle.loadString(
          AssetTemplateRepository.defaultManifestPath,
        );
        final manifest = TemplateAssetManifest.fromJson(
          _jsonObject(manifestSource),
        );

        for (final metadataPath in manifest.templates) {
          final metadataSource = await rootBundle.loadString(metadataPath);
          final metadata = TemplateAssetMetadata.fromJson(
            _jsonObject(metadataSource),
          );

          final documentBytes = await rootBundle.load(metadata.documentPath);
          expect(
            documentBytes.lengthInBytes,
            greaterThan(0),
            reason: metadata.documentPath,
          );

          final thumbnailBytes = await rootBundle.load(metadata.thumbnailPath);
          expect(
            thumbnailBytes.lengthInBytes,
            greaterThan(0),
            reason: metadata.thumbnailPath,
          );
        }
      },
    );

    test('parses sample template metadata', () async {
      final repository = AssetTemplateRepository(bundle: _sampleBundle());

      final metadata = await repository.loadTemplateMetadata();
      final persian = metadata.firstWhere(
        (template) => template.id == 'fa_story_today',
      );
      final english = metadata.firstWhere(
        (template) => template.id == 'en_youtube_watch_this',
      );

      expect(persian.title.fa, 'استوری امروز');
      expect(persian.title.en, 'Today Story');
      expect(persian.categoryId, 'instagramStory');
      expect(persian.contentLanguageId, 'persian');
      expect(persian.tags, containsAll(<String>['sample', 'story']));
      expect(persian.home?.sortOrder, 10);
      expect(File(persian.thumbnailPath).existsSync(), isTrue);

      expect(english.title.en, 'Watch This');
      expect(english.categoryId, 'youtubeThumbnail');
      expect(english.contentLanguageId, 'english');
      expect(File(english.thumbnailPath).existsSync(), isTrue);
    });

    test('decodes sample document JSON through DocumentCodec', () async {
      final repository = AssetTemplateRepository(bundle: _sampleBundle());
      final metadata = await repository.loadTemplateMetadata();

      for (final template in metadata) {
        final documentSource = _assetText(template.documentPath);
        final document = DocumentCodec.decode(documentSource);

        expect(document.width, greaterThan(0));
        expect(document.height, greaterThan(0));
        expect(document.layers, isNotEmpty);
      }
    });

    test('returns Template objects that build fresh EditorDocuments', () async {
      final repository = AssetTemplateRepository(bundle: _sampleBundle());

      final templates = await repository.loadTemplates(titleLocale: 'fa');
      final english = templates.firstWhere(
        (template) => template.id == 'en_youtube_watch_this',
      );

      expect(english, isA<Template>());
      expect(english.name, 'این ویدئو را ببینید');
      expect(english.category, TemplateCategory.youtubeThumbnail);
      expect(english.language, TemplateLanguage.english);

      final firstBuild = english.build();
      final secondBuild = english.build();
      expect(identical(firstBuild, secondBuild), isFalse);
      expect(firstBuild.width, 1280);
      expect(firstBuild.height, 720);
    });

    test('keeps contentLanguage independent from title locale', () async {
      final repository = AssetTemplateRepository(bundle: _sampleBundle());

      final records = await repository.loadAssetTemplates(titleLocale: 'fa');
      final english = records.firstWhere(
        (record) => record.metadata.id == 'en_youtube_watch_this',
      );

      expect(english.template.name, english.metadata.title.fa);
      expect(english.template.language, TemplateLanguage.english);
      expect(english.metadata.contentLanguageId, 'english');
    });

    test('invalid schemaVersion fails clearly', () {
      final json = _jsonObject(
        _assetText('assets/templates/samples/fa_story_today/template.json'),
      );
      json['schemaVersion'] = 99;

      expect(
        () => TemplateAssetMetadata.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('unsupported template metadata schemaVersion 99'),
          ),
        ),
      );
    });
  });
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

_MemoryAssetBundle _sampleBundle() {
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
