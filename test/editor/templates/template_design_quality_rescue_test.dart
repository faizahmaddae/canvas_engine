import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _rescuedTemplateIds = <String>[
  'fa_story_product_reveal',
  'fa_promo_app_launch',
  'fa_story_fashion_drop',
  'fa_post_product_carousel_cover',
  'fa_story_today',
  'fa_story_beauty_booking',
  'fa_post_service_announcement',
  'fa_business_service_launch_story',
];

const _rescuePass2TemplateIds = <String>[
  'fa_story_beauty_booking',
  'fa_story_product_reveal',
  'fa_post_service_announcement',
  'fa_story_today',
];

const _microPolishTemplateIds = <String>[
  'fa_story_beauty_booking',
  'fa_post_service_announcement',
  'fa_story_today',
];

const _requiredTextById = <String, List<String>>{
  'fa_story_product_reveal': [
    'محصول تازه',
    'محصول تازه\nبرای امروز',
    'ویژگی اصلی و مزیت محصول',
    'مشاهده محصول',
  ],
  'fa_promo_app_launch': ['اپلیکیشن', 'دانلود کنید', 'شروع رایگان'],
  'fa_story_fashion_drop': ['کالکشن', 'مشاهده کالکشن'],
  'fa_post_product_carousel_cover': ['۳ دلیل', 'کاور کاروسل محصول', '۱ / ۵'],
  'fa_story_today': [
    'امروز',
    '٪۳۰ تخفیف',
    'پیشنهاد امروز',
    'متن محصول، قیمت و زمان پایان را ویرایش کنید',
    'فقط تا امشب',
  ],
  'fa_story_beauty_booking': [
    'رزرو نوبت',
    'رزرو سریع سالن',
    'زیبایی آماده است',
    'نوبت زیبایی را سریع رزرو کنید',
    'رزرو آنلاین',
  ],
  'fa_post_service_announcement': [
    'معرفی محصول',
    'نسخه تازه از راه رسید',
    'مدیریت سفارش‌ها سریع‌تر و ساده‌تر شد',
    'بیشتر بدانید',
  ],
  'fa_business_service_launch_story': ['خدمت تازه', 'شروع شد', 'جزئیات بیشتر'],
};

void main() {
  group('Template Design Quality Rescue Pass', () {
    test('rescued templates are registered exactly once', () {
      final manifestIds = _manifestIds();

      expect(manifestIds.toSet(), hasLength(manifestIds.length));
      expect(manifestIds.toSet(), containsAll(_rescuedTemplateIds));
      for (final id in _rescuedTemplateIds) {
        expect(manifestIds.where((value) => value == id), hasLength(1));
      }
    });

    test('rescued documents decode with unique layer ids', () {
      for (final metadata in _rescuedMetadata()) {
        final document = DocumentCodec.decode(
          File(metadata.documentPath).readAsStringSync(),
        );

        expect(document.layers, isNotEmpty, reason: metadata.id);
        expect(
          document.layers.map((layer) => layer.id).toSet(),
          hasLength(document.layers.length),
          reason: '${metadata.id} layer ids must be unique',
        );
      }
    });

    test('rescued templates keep purpose-defining editable text', () {
      for (final metadata in _rescuedMetadata()) {
        final documentJson = _jsonObject(_assetText(metadata.documentPath));
        final text = _textLayerContent(documentJson).join('\n');

        for (final requiredText in _requiredTextById[metadata.id]!) {
          expect(text, contains(requiredText), reason: metadata.id);
        }
      }
    });

    test('pass 2 templates are exactly the manually confirmed weak set', () {
      expect(_rescuePass2TemplateIds, hasLength(4));
      expect(_rescuedTemplateIds.toSet(), containsAll(_rescuePass2TemplateIds));
    });

    test('micro polish templates are exactly the final manual QA set', () {
      expect(_microPolishTemplateIds, hasLength(3));
      expect(_rescuedTemplateIds.toSet(), containsAll(_microPolishTemplateIds));
    });

    test('rescued thumbnails exist, decode, and match document aspect', () {
      for (final metadata in _rescuedMetadata()) {
        final document = DocumentCodec.decode(
          File(metadata.documentPath).readAsStringSync(),
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

    test('temporary rescue thumbnail generator is not checked in', () {
      const generatorPaths = <String>[
        'test/widget/template_design_quality_rescue_thumbnail_generator_test.dart',
        'test/widget/template_design_quality_rescue_pass2_thumbnail_generator_test.dart',
        'test/widget/template_design_micro_polish_thumbnail_generator_test.dart',
      ];

      for (final path in generatorPaths) {
        expect(File(path).existsSync(), isFalse, reason: path);
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

List<TemplateAssetMetadata> _rescuedMetadata() {
  final metadataById = <String, TemplateAssetMetadata>{};
  for (final metadataPath in _manifest().templates) {
    final metadata = _metadata(metadataPath);
    metadataById[metadata.id] = metadata;
  }
  return [for (final id in _rescuedTemplateIds) metadataById[id]!];
}

TemplateAssetMetadata _metadata(String path) {
  return TemplateAssetMetadata.fromJson(_jsonObject(_assetText(path)));
}

List<String> _textLayerContent(Map<String, dynamic> documentJson) {
  final layers = documentJson['layers'];
  if (layers is! List) return const [];
  return [
    for (final rawLayer in layers)
      if (rawLayer is Map && rawLayer['type'] == 'text')
        rawLayer['content'] as String,
  ];
}

String _assetText(String path) => File(path).readAsStringSync();

Map<String, dynamic> _jsonObject(String source) {
  return Map<String, dynamic>.from(jsonDecode(source) as Map);
}
