import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _batch1Ids = <String>[
  'fa_story_product_reveal',
  'fa_story_daily_offer',
  'fa_story_cafe_mood',
  'fa_story_course_signup',
  'fa_post_brand_intro',
  'fa_post_minimal_tip',
  'fa_post_event_countdown',
  'fa_post_culture_seasonal',
  'fa_sale_luxury_drop',
  'fa_sale_market_weekend',
  'fa_promo_restaurant_special',
  'fa_promo_course_launch',
  'fa_poetry_nastaliq_evening',
  'fa_quote_modern_dark',
  'fa_poetry_gallery_card',
  'en_yt_ai_tools_2026',
  'en_yt_before_after_design',
  'en_social_launch_checklist',
];

void main() {
  group('Template Product Quality Batch 1', () {
    test('all batch templates are registered exactly once in manifest', () {
      final manifest = _manifest();
      final manifestIds = <String>[];

      for (final metadataPath in manifest.templates) {
        final metadata = _metadata(metadataPath);
        manifestIds.add(metadata.id);
      }

      expect(manifestIds.toSet(), hasLength(manifestIds.length));
      expect(manifestIds.toSet(), containsAll(_batch1Ids));
      for (final id in _batch1Ids) {
        expect(manifestIds.where((value) => value == id), hasLength(1));
      }
    });

    test('batch metadata uses valid categories and language balance', () {
      final metadata = _batchMetadata();

      expect(metadata, hasLength(_batch1Ids.length));
      expect(
        metadata.where((template) => template.contentLanguageId == 'persian'),
        hasLength(15),
      );
      expect(
        metadata.where((template) => template.contentLanguageId == 'english'),
        hasLength(3),
      );

      for (final template in metadata) {
        expect(template.tags, contains('product-quality-batch-1'));
        expect(
          TemplateCategory.values.any(
            (category) => category.name == template.categoryId,
          ),
          isTrue,
          reason: template.id,
        );
        expect(
          TemplateLanguage.values.any(
            (language) => language.name == template.contentLanguageId,
          ),
          isTrue,
          reason: template.id,
        );
      }
    });

    test('batch documents decode and thumbnails match document aspect', () {
      for (final metadata in _batchMetadata()) {
        final document = DocumentCodec.decode(
          File(metadata.documentPath).readAsStringSync(),
        );
        expect(document.layers, isNotEmpty, reason: metadata.id);
        expect(
          document.layers.map((layer) => layer.id).toSet(),
          hasLength(document.layers.length),
          reason: '${metadata.id} layer ids must be unique',
        );

        final thumbnailFile = File(metadata.thumbnailPath);
        expect(thumbnailFile.existsSync(), isTrue, reason: metadata.id);
        final thumbnail = img.decodeImage(thumbnailFile.readAsBytesSync());
        expect(thumbnail, isNotNull, reason: metadata.id);

        final documentAspect = document.width / document.height;
        final thumbnailAspect = thumbnail!.width / thumbnail.height;
        expect(
          thumbnailAspect,
          closeTo(documentAspect, 0.02),
          reason: metadata.id,
        );
      }
    });
  });
}

TemplateAssetManifest _manifest() {
  return TemplateAssetManifest.fromJson(
    _jsonObject(_assetText(AssetTemplateRepository.defaultManifestPath)),
  );
}

List<TemplateAssetMetadata> _batchMetadata() {
  final metadataById = <String, TemplateAssetMetadata>{};
  for (final metadataPath in _manifest().templates) {
    final metadata = _metadata(metadataPath);
    metadataById[metadata.id] = metadata;
  }
  return [for (final id in _batch1Ids) metadataById[id]!];
}

TemplateAssetMetadata _metadata(String path) {
  return TemplateAssetMetadata.fromJson(_jsonObject(_assetText(path)));
}

String _assetText(String path) => File(path).readAsStringSync();

Map<String, dynamic> _jsonObject(String source) {
  return Map<String, dynamic>.from(jsonDecode(source) as Map);
}
