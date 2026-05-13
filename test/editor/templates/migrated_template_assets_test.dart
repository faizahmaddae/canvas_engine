import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/combined_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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
  group('migrated template assets', () {
    test('all migrated metadata files load from the manifest', () async {
      final repository = AssetTemplateRepository(bundle: _assetBundle());

      final metadata = await repository.loadTemplateMetadata();
      final migrated = metadata
          .where((template) => _migratedTemplateIds.contains(template.id))
          .toList(growable: false);

      expect(
        migrated.map((template) => template.id).toSet(),
        _migratedTemplateIds,
      );
      for (final template in migrated) {
        expect(template.schemaVersion, kTemplateMetadataSchemaVersion);
        expect(
          template.documentPath,
          'assets/templates/${template.id}/document.json',
        );
        expect(
          template.thumbnailPath,
          'assets/templates/${template.id}/thumbnail.png',
        );
        expect(template.tags, contains('migrated'));
      }
    });

    test('all migrated document JSON files decode through DocumentCodec', () {
      for (final id in _migratedTemplateIds) {
        final source = _assetText('assets/templates/$id/document.json');
        final document = DocumentCodec.decode(source);

        expect(document.width, greaterThan(0), reason: id);
        expect(document.height, greaterThan(0), reason: id);
        expect(document.layers, isNotEmpty, reason: id);
        expect(
          DocumentCodec.decode(DocumentCodec.encode(document)).layers.length,
          document.layers.length,
        );
      }
    });

    test(
      'manifest thumbnails exist and match document aspect ratios',
      () async {
        final repository = AssetTemplateRepository(bundle: _assetBundle());
        final metadata = await repository.loadTemplateMetadata();

        for (final template in metadata) {
          final file = File(template.thumbnailPath);
          expect(file.existsSync(), isTrue, reason: template.id);
          final image = img.decodePng(file.readAsBytesSync());
          expect(image, isNotNull, reason: template.id);
          expect(image!.width, greaterThan(0), reason: template.id);
          expect(image.height, greaterThan(0), reason: template.id);

          final document = DocumentCodec.decode(
            _assetText(template.documentPath),
          );
          final documentAspect = document.width / document.height;
          final thumbnailAspect = image.width / image.height;
          expect(
            thumbnailAspect,
            closeTo(documentAspect, 0.02),
            reason: template.id,
          );
        }
      },
    );

    test(
      'duplicate ids prefer migrated JSON templates over legacy objects',
      () async {
        final repository = CombinedTemplateRepository(
          assetRepository: AssetTemplateRepository(bundle: _assetBundle()),
          legacyTemplates: TemplateCatalog.all,
        );

        final result = await repository.loadTemplateResult();

        for (final id in _migratedTemplateIds) {
          final legacy = TemplateCatalog.all.firstWhere(
            (template) => template.id == id,
          );
          final selected = result.templates.singleWhere(
            (template) => template.id == id,
          );

          expect(identical(selected, legacy), isFalse, reason: id);
          expect(
            result.warnings,
            contains(contains('Duplicate template id "$id"')),
          );
        }
      },
    );

    test(
      'building each migrated template returns fresh EditorDocuments',
      () async {
        final repository = AssetTemplateRepository(bundle: _assetBundle());
        final templates = await repository.loadTemplates();
        final migrated = templates.where(
          (template) => _migratedTemplateIds.contains(template.id),
        );

        expect(migrated.length, _migratedTemplateIds.length);
        for (final template in migrated) {
          final first = template.build();
          final second = template.build();

          expect(identical(first, second), isFalse, reason: template.id);
          expect(first.width, greaterThan(0), reason: template.id);
          expect(first.height, greaterThan(0), reason: template.id);
          expect(first.layers, isNotEmpty, reason: template.id);
        }
      },
    );
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
