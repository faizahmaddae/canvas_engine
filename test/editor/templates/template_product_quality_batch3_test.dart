import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _batch3Ids = <String>[
  'fa_story_fashion_drop',
  'fa_story_beauty_booking',
  'fa_story_health_clinic_tip',
  'fa_post_product_carousel_cover',
  'fa_post_service_announcement',
  'fa_post_personal_brand_quote',
  'fa_sale_retail_clearance',
  'fa_promo_clinic_checkup',
  'fa_promo_travel_tour',
  'fa_sale_beauty_package',
  'fa_promo_app_launch',
  'fa_poetry_black_gold_nastaliq',
  'fa_quote_editorial_magazine',
  'fa_poetry_photo_frame_premium',
  'fa_quote_literary_column',
  'fa_event_gallery_opening',
  'fa_business_service_launch_story',
  'fa_event_workshop_announcement',
  'en_yt_tutorial_blueprint',
  'en_yt_reaction_hot_take',
  'en_yt_podcast_interview',
  'en_social_business_announcement',
];

void main() {
  group('Template Product Quality Batch 3', () {
    test('all batch templates are registered exactly once in manifest', () {
      final manifestIds = _manifestIds();

      expect(manifestIds.toSet(), hasLength(manifestIds.length));
      expect(manifestIds.toSet(), containsAll(_batch3Ids));
      for (final id in _batch3Ids) {
        expect(manifestIds.where((value) => value == id), hasLength(1));
      }
    });

    test('batch metadata uses valid categories and language balance', () {
      final metadata = _batchMetadata();

      expect(metadata, hasLength(_batch3Ids.length));
      expect(
        metadata.where((template) => template.contentLanguageId == 'persian'),
        hasLength(18),
      );
      expect(
        metadata.where((template) => template.contentLanguageId == 'english'),
        hasLength(4),
      );

      for (final template in metadata) {
        expect(template.tags, contains('product-quality-batch-3'));
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

    test('pubspec asset declarations cover every manifest template file', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      for (final metadataPath in _manifest().templates) {
        final metadata = _metadata(metadataPath);
        final directory = metadataPath.substring(
          0,
          metadataPath.lastIndexOf('/') + 1,
        );

        expect(pubspec, contains('- $directory'), reason: metadataPath);
        expect(File(metadataPath).existsSync(), isTrue, reason: metadataPath);
        expect(
          File(metadata.documentPath).existsSync(),
          isTrue,
          reason: metadata.documentPath,
        );
        expect(
          File(metadata.thumbnailPath).existsSync(),
          isTrue,
          reason: metadata.thumbnailPath,
        );
      }
    });

    test('temporary thumbnail generator test has been removed', () {
      expect(
        File(
          'test/widget/template_batch3_thumbnail_generator_test.dart',
        ).existsSync(),
        isFalse,
      );
    });
  });
}

TemplateAssetManifest _manifest() {
  return TemplateAssetManifest.fromJson(
    _jsonObject(_assetText(AssetTemplateRepository.defaultManifestPath)),
  );
}

List<String> _manifestIds() {
  return [
    for (final metadataPath in _manifest().templates)
      _metadata(metadataPath).id,
  ];
}

List<TemplateAssetMetadata> _batchMetadata() {
  final metadataById = <String, TemplateAssetMetadata>{};
  for (final metadataPath in _manifest().templates) {
    final metadata = _metadata(metadataPath);
    metadataById[metadata.id] = metadata;
  }
  return [for (final id in _batch3Ids) metadataById[id]!];
}

TemplateAssetMetadata _metadata(String path) {
  return TemplateAssetMetadata.fromJson(_jsonObject(_assetText(path)));
}

String _assetText(String path) => File(path).readAsStringSync();

Map<String, dynamic> _jsonObject(String source) {
  return Map<String, dynamic>.from(jsonDecode(source) as Map);
}
