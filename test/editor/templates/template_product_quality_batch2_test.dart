import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _batch2Ids = <String>[
  'fa_business_recruitment_story',
  'fa_business_agency_intro',
  'fa_business_service_offer',
  'fa_business_job_fair',
  'fa_business_team_hiring',
  'fa_business_consulting_post',
  'fa_food_modern_menu_board',
  'fa_food_delivery_story',
  'fa_cafe_breakfast_special',
  'fa_restaurant_live_night',
  'fa_food_dessert_launch',
  'fa_edu_webinar_story',
  'fa_edu_workshop_poster',
  'fa_edu_exam_prep_post',
  'fa_edu_course_tip_carousel',
  'fa_season_nowruz_greeting',
  'fa_season_iftar_invite',
  'fa_cultural_book_night',
  'en_business_product_update',
  'en_webinar_growth_masterclass',
  'en_event_startup_pitch',
  'en_social_case_study',
  'en_yt_explainer_framework',
];

void main() {
  group('Template Product Quality Batch 2', () {
    test('all batch templates are registered exactly once in manifest', () {
      final manifestIds = _manifestIds();

      expect(manifestIds.toSet(), hasLength(manifestIds.length));
      expect(manifestIds.toSet(), containsAll(_batch2Ids));
      for (final id in _batch2Ids) {
        expect(manifestIds.where((value) => value == id), hasLength(1));
      }
    });

    test('batch metadata uses valid categories and language balance', () {
      final metadata = _batchMetadata();

      expect(metadata, hasLength(_batch2Ids.length));
      expect(
        metadata.where((template) => template.contentLanguageId == 'persian'),
        hasLength(18),
      );
      expect(
        metadata.where((template) => template.contentLanguageId == 'english'),
        hasLength(5),
      );

      for (final template in metadata) {
        expect(template.tags, contains('product-quality-batch-2'));
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
  return [for (final id in _batch2Ids) metadataById[id]!];
}

TemplateAssetMetadata _metadata(String path) {
  return TemplateAssetMetadata.fromJson(_jsonObject(_assetText(path)));
}

String _assetText(String path) => File(path).readAsStringSync();

Map<String, dynamic> _jsonObject(String source) {
  return Map<String, dynamic>.from(jsonDecode(source) as Map);
}
