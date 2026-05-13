import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/home/presentation/widgets/templates_section.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/presentation/template_presentation_order.dart';
import 'package:canvas_engine/features/templates/presentation/templates_browse_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

late List<Template> _assetTemplatesEn;
late List<Template> _assetTemplatesFa;

Template _template({
  required String id,
  required String name,
  required TemplateCategory category,
  required TemplateLanguage language,
  required Size size,
}) {
  return Template(
    id: id,
    name: name,
    category: category,
    language: language,
    build: () => EditorDocument(
      width: size.width,
      height: size.height,
      layers: const [],
      backgroundColor: const Color(0xFFF5EFE6),
    ),
  );
}

List<Template> _focusedTemplates(TemplateLanguage language) => [
  _template(
    id: 'story',
    name: 'Story One',
    category: TemplateCategory.instagramStory,
    language: language,
    size: const Size(1080, 1920),
  ),
  _template(
    id: 'youtube',
    name: 'YouTube One',
    category: TemplateCategory.youtubeThumbnail,
    language: language,
    size: const Size(1280, 720),
  ),
  _template(
    id: 'poetry',
    name: 'Poetry One',
    category: TemplateCategory.poetryPost,
    language: language,
    size: const Size(1080, 1080),
  ),
  _template(
    id: 'promo',
    name: 'Promo One',
    category: TemplateCategory.promotionalPoster,
    language: language,
    size: const Size(1080, 1350),
  ),
];

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<Template> templates,
  TemplateLanguage? language,
  Locale? locale,
  void Function(Template)? onOpen,
  void Function(TemplateCategory)? onSeeAllCategory,
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: TemplatesSection(
            templates: templates,
            language: language,
            onOpen: onOpen ?? (_) {},
            onSeeAllCategory: onSeeAllCategory,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    final repository = AssetTemplateRepository(bundle: _assetBundle());
    _assetTemplatesEn = await repository.loadTemplates();
    _assetTemplatesFa = await repository.loadTemplates(titleLocale: 'fa');
  });

  group('TemplatesSection focused home rows', () {
    testWidgets('renders all four strips when focused categories exist', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        templates: _focusedTemplates(TemplateLanguage.persian),
      );

      expect(find.text('Recommended to start'), findsOneWidget);
      expect(find.text('Instagram stories'), findsOneWidget);
      expect(find.text('Advertising posts'), findsOneWidget);
      expect(find.text('YouTube thumbnails'), findsOneWidget);
      expect(find.text('Quotes and poems'), findsOneWidget);
    });

    testWidgets('omits a focused category when it has no templates', (
      tester,
    ) async {
      final templates = _focusedTemplates(TemplateLanguage.persian)
          .where((t) => t.category != TemplateCategory.promotionalPoster)
          .toList(growable: false);

      await _pumpSection(tester, templates: templates);

      expect(find.text('Recommended to start'), findsOneWidget);
      expect(find.text('Instagram stories'), findsOneWidget);
      expect(find.text('YouTube thumbnails'), findsOneWidget);
      expect(find.text('Quotes and poems'), findsOneWidget);
      expect(find.text('Advertising posts'), findsNothing);
    });

    testWidgets('tapping a template card invokes onOpen with that template', (
      tester,
    ) async {
      Template? opened;
      final templates = _focusedTemplates(TemplateLanguage.persian);

      await _pumpSection(
        tester,
        templates: templates,
        onOpen: (template) => opened = template,
      );

      await tester.tap(
        find.byKey(const ValueKey('template-card-size-story')).first,
      );
      await tester.pump();

      expect(opened?.id, 'story');
    });

    testWidgets('see all reports the category used for browse pre-filter', (
      tester,
    ) async {
      TemplateCategory? category;

      await _pumpSection(
        tester,
        templates: _focusedTemplates(TemplateLanguage.persian),
        onSeeAllCategory: (value) => category = value,
      );

      await tester.tap(find.text('See all').first);
      await tester.pumpAndSettle();

      expect(category, TemplateCategory.instagramStory);
      expect(find.byType(TemplatesBrowseScreen), findsOneWidget);
      expect(find.text('Instagram stories'), findsAtLeastNWidgets(1));
      expect(
        find.text('Choose a template and start designing.'),
        findsOneWidget,
      );
    });

    testWidgets('labels follow UI locale instead of template language', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        templates: _focusedTemplates(TemplateLanguage.persian),
      );
      expect(find.text('Instagram stories'), findsOneWidget);
      expect(find.text('استوری اینستاگرام'), findsNothing);

      await _pumpSection(
        tester,
        templates: _focusedTemplates(TemplateLanguage.english),
        locale: const Locale('fa'),
      );
      expect(find.text('استوری اینستاگرام'), findsOneWidget);
      expect(find.text('تامبنیل یوتیوب'), findsOneWidget);
      expect(find.text('شعر و نقل‌قول'), findsOneWidget);
      expect(find.text('پست تبلیغاتی'), findsOneWidget);
    });

    testWidgets('focused rows preserve category-specific thumbnail ratios', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        templates: _focusedTemplates(TemplateLanguage.persian),
      );

      expect(
        tester.getSize(
          find.byKey(const ValueKey('template-card-thumbnail-story')).last,
        ),
        const Size(94.5, 168),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('template-card-thumbnail-youtube')).last,
        ),
        const Size(195.55555555555554, 110),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('template-card-thumbnail-poetry')).last,
        ),
        const Size(138, 138),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('template-card-thumbnail-promo')).last,
        ),
        const Size(131.20000000000002, 164),
      );
    });

    testWidgets(
      'recommended row starts with curated first-start templates in RTL',
      (tester) async {
        await _pumpSection(
          tester,
          templates: _assetTemplatesFa,
          locale: const Locale('fa'),
        );

        final story = tester.getCenter(
          find
              .byKey(const ValueKey('template-card-size-fa_story_fashion_drop'))
              .first,
        );
        final promo = tester.getCenter(
          find
              .byKey(const ValueKey('template-card-size-fa_promo_app_launch'))
              .first,
        );
        final poetry = tester.getCenter(
          find
              .byKey(
                const ValueKey(
                  'template-card-size-fa_poetry_black_gold_nastaliq',
                ),
              )
              .first,
        );
        final youtube = tester.getCenter(
          find
              .byKey(
                const ValueKey('template-card-size-en_yt_tutorial_blueprint'),
              )
              .first,
        );
        final quote = tester.getCenter(
          find
              .byKey(
                const ValueKey('template-card-size-fa_story_product_reveal'),
              )
              .first,
        );

        expect(story.dx, greaterThan(promo.dx));
        expect(promo.dx, greaterThan(poetry.dx));
        expect(poetry.dx, greaterThan(youtube.dx));
        expect(youtube.dx, greaterThan(quote.dx));
      },
    );

    testWidgets('RTL first recommended card starts from the right gutter', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        templates: _assetTemplatesFa,
        locale: const Locale('fa'),
      );

      final firstCard = find
          .byKey(const ValueKey('template-card-size-fa_story_fashion_drop'))
          .first;

      expect(tester.getTopRight(firstCard).dx, closeTo(1180, 0.1));
    });

    testWidgets('LTR first recommended card starts from the left gutter', (
      tester,
    ) async {
      await _pumpSection(tester, templates: _assetTemplatesEn);

      final firstCard = find
          .byKey(const ValueKey('template-card-size-fa_story_fashion_drop'))
          .first;

      expect(tester.getTopLeft(firstCard).dx, closeTo(20, 0.1));
    });

    testWidgets('recommended row promotes fresh designs before fallbacks', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        templates: [
          _template(
            id: 'fa_insta_story_v1',
            name: 'Legacy story',
            category: TemplateCategory.instagramStory,
            language: TemplateLanguage.persian,
            size: const Size(1080, 1920),
          ),
          _template(
            id: 'fa_story_fashion_drop',
            name: 'Fresh story',
            category: TemplateCategory.instagramStory,
            language: TemplateLanguage.persian,
            size: const Size(1080, 1920),
          ),
        ],
      );

      final fresh = tester.getCenter(
        find
            .byKey(const ValueKey('template-card-size-fa_story_fashion_drop'))
            .first,
      );
      final fallback = tester.getCenter(
        find
            .byKey(const ValueKey('template-card-size-fa_insta_story_v1'))
            .first,
      );

      expect(fresh.dx, lessThan(fallback.dx));
    });

    testWidgets('template header action stays on the same row in LTR', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        templates: _focusedTemplates(TemplateLanguage.persian),
      );

      final title = find.text('Recommended to start').first;
      final actionText = find.text('See all').first;
      final actionButton = find
          .ancestor(of: actionText, matching: find.byType(TextButton))
          .first;

      expect(
        tester.getCenter(title).dx,
        lessThan(tester.getCenter(actionText).dx),
      );
      expect(
        tester.getCenter(title).dy,
        closeTo(tester.getCenter(actionText).dy, 3),
      );
      expect(tester.getTopRight(actionButton).dx, closeTo(1180, 1));
    });

    testWidgets('template header action mirrors to the left in RTL', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        templates: _focusedTemplates(TemplateLanguage.persian),
        locale: const Locale('fa'),
      );

      final title = find.text('پیشنهادی برای شروع').first;
      final actionText = find.text('مشاهده همه').first;
      final actionButton = find
          .ancestor(of: actionText, matching: find.byType(TextButton))
          .first;

      expect(
        tester.getCenter(actionText).dx,
        lessThan(tester.getCenter(title).dx),
      );
      expect(
        tester.getCenter(title).dy,
        closeTo(tester.getCenter(actionText).dy, 3),
      );
      expect(tester.getTopLeft(actionButton).dx, closeTo(20, 1));
    });

    testWidgets('production catalog uses localized focused home labels', (
      tester,
    ) async {
      await _pumpSection(tester, templates: _assetTemplatesEn);

      expect(find.text('Recommended to start'), findsOneWidget);
      expect(find.text('Instagram stories'), findsOneWidget);
      expect(find.text('Text and typography'), findsOneWidget);
      expect(find.text('Advertising posts'), findsOneWidget);
      expect(find.text('YouTube thumbnails'), findsOneWidget);
      expect(find.text('Quotes and poems'), findsOneWidget);
    });
  });

  group('TemplatesBrowseScreen initialCategory', () {
    testWidgets('opens with the matching category title selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TemplatesBrowseScreen(
            onOpen: (_) {},
            initialLanguage: TemplateLanguage.persian,
            initialCategory: TemplateCategory.instagramStory,
            templates: _assetTemplatesFa,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Instagram stories'), findsAtLeastNWidgets(1));
      expect(
        find.text('Choose a template and start designing.'),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('browse-template-tile-fa_story_fashion_drop'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(find.text('شعر مینیمال'), findsNothing);
    });

    testWidgets('language filter changes content without changing locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TemplatesBrowseScreen(
            onOpen: (_) {},
            initialLanguage: TemplateLanguage.persian,
            templates: _assetTemplatesFa,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('قالب‌ها'), findsOneWidget);
      expect(
        find.text('قالب مناسب را بر اساس زبان و دسته‌بندی پیدا کن.'),
        findsOneWidget,
      );
      expect(find.text('زبان: فارسی'), findsOneWidget);

      await tester.tap(find.text('زبان: فارسی'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('انگلیسی').last);
      await tester.pumpAndSettle();

      expect(find.text('قالب‌ها'), findsOneWidget);
      expect(
        find.text('قالب مناسب را بر اساس زبان و دسته‌بندی پیدا کن.'),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('browse-template-tile-en_yt_tutorial_blueprint'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('browse-template-tile-fa_story_fashion_drop'),
          skipOffstage: false,
        ),
        findsNothing,
      );
    });

    testWidgets('search filters templates locally', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TemplatesBrowseScreen(
            onOpen: (_) {},
            initialLanguage: TemplateLanguage.english,
            templates: _assetTemplatesEn,
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'sale');
      await tester.pumpAndSettle();

      expect(find.text('Bold sale'), findsAtLeastNWidgets(1));
      expect(find.text('Minimal quote'), findsNothing);
    });

    testWidgets('search includes product use-case keywords', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TemplatesBrowseScreen(
            onOpen: (_) {},
            initialLanguage: TemplateLanguage.persian,
            templates: _assetTemplatesEn,
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'education');
      await tester.pumpAndSettle();

      expect(find.text('Persian Webinar Story'), findsAtLeastNWidgets(1));
      expect(find.text('Persian Fashion Drop Story'), findsNothing);
    });
  });

  group('template presentation ordering', () {
    test('keeps every browse template while promoting fresh designs', () {
      final templates = [
        _template(
          id: 'generic-story',
          name: 'Generic story',
          category: TemplateCategory.instagramStory,
          language: TemplateLanguage.persian,
          size: const Size(1080, 1920),
        ),
        _template(
          id: 'fa_story_fashion_drop',
          name: 'Fresh story',
          category: TemplateCategory.instagramStory,
          language: TemplateLanguage.persian,
          size: const Size(1080, 1920),
        ),
        _template(
          id: 'generic-promo',
          name: 'Generic promo',
          category: TemplateCategory.promotionalPoster,
          language: TemplateLanguage.persian,
          size: const Size(1080, 1350),
        ),
      ];

      final ordered = orderTemplatesForBrowse(
        templates: templates,
        preferredLanguage: TemplateLanguage.persian,
      );

      expect(ordered.map((template) => template.id), [
        'fa_story_fashion_drop',
        'generic-story',
        'generic-promo',
      ]);
      expect(
        ordered.map((template) => template.id),
        unorderedEquals(templates.map((template) => template.id)),
      );
    });

    test('prioritizes the active locale language when Browse shows all', () {
      final templates = [
        _template(
          id: 'en_yt_tutorial_blueprint',
          name: 'English featured',
          category: TemplateCategory.youtubeThumbnail,
          language: TemplateLanguage.english,
          size: const Size(1280, 720),
        ),
        _template(
          id: 'fa_story_fashion_drop',
          name: 'Persian featured',
          category: TemplateCategory.instagramStory,
          language: TemplateLanguage.persian,
          size: const Size(1080, 1920),
        ),
      ];

      final ordered = orderTemplatesForBrowse(
        templates: templates,
        preferredLanguage: TemplateLanguage.persian,
      );

      expect(ordered.first.id, 'fa_story_fashion_drop');
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
