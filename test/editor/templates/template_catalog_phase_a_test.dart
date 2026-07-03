import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/domain/template_catalog.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class _TemplateSpec {
  const _TemplateSpec({
    required this.id,
    required this.category,
    required this.language,
    required this.width,
    required this.height,
  });

  final String id;
  final TemplateCategory category;
  final TemplateLanguage language;
  final double width;
  final double height;
}

void main() {
  const specs = <_TemplateSpec>[
    _TemplateSpec(
      id: 'fa_insta_story_v1',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1920,
    ),
    _TemplateSpec(
      id: 'en_yt_thumb_v1',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      width: 1280,
      height: 720,
    ),
    _TemplateSpec(
      id: 'fa_poetry_v1',
      category: TemplateCategory.poetryPost,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1080,
    ),
    _TemplateSpec(
      id: 'fa_promo_v1',
      category: TemplateCategory.promotionalPoster,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1350,
    ),
    _TemplateSpec(
      id: 'fa_insta_story_bold_word_v1',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1920,
    ),
    _TemplateSpec(
      id: 'fa_insta_story_announcement_v1',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1920,
    ),
    _TemplateSpec(
      id: 'fa_insta_story_frame_v1',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1920,
    ),
    _TemplateSpec(
      id: 'fa_insta_story_minimal_v1',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1920,
    ),
    _TemplateSpec(
      id: 'en_yt_question_v1',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      width: 1280,
      height: 720,
    ),
    _TemplateSpec(
      id: 'en_yt_list_v1',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      width: 1280,
      height: 720,
    ),
    _TemplateSpec(
      id: 'en_yt_reaction_v1',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      width: 1280,
      height: 720,
    ),
    _TemplateSpec(
      id: 'en_yt_tutorial_v1',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      width: 1280,
      height: 720,
    ),
    _TemplateSpec(
      id: 'fa_poetry_minimal_v1',
      category: TemplateCategory.poetryPost,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1080,
    ),
    _TemplateSpec(
      id: 'fa_poetry_traditional_v1',
      category: TemplateCategory.poetryPost,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1080,
    ),
    _TemplateSpec(
      id: 'fa_poetry_overlay_v1',
      category: TemplateCategory.poetryPost,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1080,
    ),
    _TemplateSpec(
      id: 'fa_promo_sale_v1',
      category: TemplateCategory.promotionalPoster,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1350,
    ),
    _TemplateSpec(
      id: 'fa_promo_event_v1',
      category: TemplateCategory.promotionalPoster,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1350,
    ),
    _TemplateSpec(
      id: 'fa_promo_launch_v1',
      category: TemplateCategory.promotionalPoster,
      language: TemplateLanguage.persian,
      width: 1080,
      height: 1350,
    ),
  ];

  Template findTemplate(String id) => TemplateCatalog.all.firstWhere(
    (t) => t.id == id,
    orElse: () => throw StateError('Template $id missing from catalog'),
  );

  group('focused use-case templates', () {
    test('surface under the new browse categories with target depth', () {
      final english = TemplateCatalog.byLanguage(TemplateLanguage.english);
      final persian = TemplateCatalog.byLanguage(TemplateLanguage.persian);

      expect(
        english.any(
          (t) =>
              t.id == 'en_yt_thumb_v1' &&
              t.category == TemplateCategory.youtubeThumbnail,
        ),
        isTrue,
      );
      expect(
        persian.any(
          (t) =>
              t.id == 'fa_insta_story_v1' &&
              t.category == TemplateCategory.instagramStory,
        ),
        isTrue,
      );
      expect(
        persian.any(
          (t) =>
              t.id == 'fa_poetry_v1' &&
              t.category == TemplateCategory.poetryPost,
        ),
        isTrue,
      );
      expect(
        persian.any(
          (t) =>
              t.id == 'fa_promo_v1' &&
              t.category == TemplateCategory.promotionalPoster,
        ),
        isTrue,
      );
      expect(
        persian
            .where((t) => t.category == TemplateCategory.instagramStory)
            .length,
        5,
      );
      expect(
        english
            .where((t) => t.category == TemplateCategory.youtubeThumbnail)
            .length,
        5,
      );
      expect(
        persian.where((t) => t.category == TemplateCategory.poetryPost).length,
        4,
      );
      expect(
        persian
            .where((t) => t.category == TemplateCategory.promotionalPoster)
            .length,
        4,
      );
    });

    for (final spec in specs) {
      test('${spec.id} builds, sizes, and round-trips byte-identically', () {
        final template = findTemplate(spec.id);

        expect(template.category, spec.category);
        expect(template.language, spec.language);

        final doc = template.build();
        expect(doc.width, spec.width);
        expect(doc.height, spec.height);
        expect(doc.layers, isNotEmpty);

        final encoded = DocumentCodec.encode(doc);
        final decoded = DocumentCodec.decode(encoded);
        expect(DocumentCodec.encode(decoded), encoded);

        if (spec.language == TemplateLanguage.persian) {
          final textLayers = doc.layers.whereType<TextLayer>().toList();
          expect(textLayers, isNotEmpty);
          expect(
            textLayers.any(
              (layer) => layer.style.fontFamily == 'Vazir_Regular',
            ),
            isTrue,
            reason: '${spec.id} should use the shipped Persian default font',
          );
          for (final layer in textLayers) {
            expect(
              textDirectionForContent(layer.content),
              TextDirection.rtl,
              reason: '${spec.id}/${layer.id} must resolve to RTL',
            );
          }
        }
      });
    }
  });
}
