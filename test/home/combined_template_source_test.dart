import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/home/presentation/home_screen.dart';
import 'package:canvas_engine/features/home/presentation/widgets/templates_section.dart';
import 'package:canvas_engine/features/templates/application/template_repository_provider.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/combined_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/presentation/templates_browse_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('combined template source in Home and Browse', () {
    testWidgets('Home section can render asset templates', (tester) async {
      final templates = await _sampleCombinedRepository().loadTemplates();

      await _pumpHomeSection(tester, templates: templates);

      // v2 grid: the curated leads (kHomeRecommendedTemplateIds order)
      // fill the 2-col teaser.
      expect(
        find.byKey(const ValueKey('home-template-fa_story_fashion_drop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-template-fa_promo_app_launch')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('home-template-fa_poetry_black_gold_nastaliq'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('HomeScreen renders effective provider templates', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            combinedTemplateRepositoryProvider.overrideWithValue(
              _sampleCombinedRepository(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Templates'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('home-template-fa_story_fashion_drop'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    });

    testWidgets('Browse can search and filter combined asset templates', (
      tester,
    ) async {
      await _pumpBrowse(
        tester,
        repository: _sampleCombinedRepository(),
        initialLanguage: TemplateLanguage.english,
        initialCategory: TemplateCategory.youtubeThumbnail,
      );
      await tester.pumpAndSettle();

      expect(find.text('YouTube thumbnails'), findsAtLeastNWidgets(1));

      await tester.enterText(find.byType(TextField), 'watch');
      await tester.pumpAndSettle();

      final watchPreviewFinder = find.byKey(
        const ValueKey('browse-template-preview-en_youtube_watch_this'),
        skipOffstage: false,
      );
      expect(watchPreviewFinder, findsOneWidget);
      expect(find.text('Minimal quote'), findsNothing);

      await tester.ensureVisible(watchPreviewFinder);
      await tester.pumpAndSettle();

      expect(find.text('Watch This'), findsOneWidget);
      final watchPreviewSize = tester.getSize(watchPreviewFinder);
      expect(
        watchPreviewSize.width / watchPreviewSize.height,
        closeTo(16 / 9, 0.01),
      );
    });

    testWidgets('Browse uses compact portrait rows and wide landscape cards', (
      tester,
    ) async {
      await _pumpBrowseWithTemplates(
        tester,
        templates: [
          _layoutTemplate(
            id: 'story-layout',
            name: 'Story layout',
            category: TemplateCategory.instagramStory,
            size: const Size(1080, 1920),
          ),
          _layoutTemplate(
            id: 'promo-layout',
            name: 'Promo layout',
            category: TemplateCategory.promotionalPoster,
            size: const Size(1080, 1350),
          ),
          _layoutTemplate(
            id: 'youtube-layout',
            name: 'YouTube layout',
            category: TemplateCategory.youtubeThumbnail,
            size: const Size(1280, 720),
          ),
        ],
      );
      await tester.pumpAndSettle();

      final storyFinder = find.byKey(
        const ValueKey('browse-template-preview-story-layout'),
      );
      final promoFinder = find.byKey(
        const ValueKey('browse-template-preview-promo-layout'),
      );
      final youtubeFinder = find.byKey(
        const ValueKey('browse-template-preview-youtube-layout'),
      );

      final storyTopLeft = tester.getTopLeft(storyFinder);
      final promoTopLeft = tester.getTopLeft(promoFinder);
      expect(storyTopLeft.dy, closeTo(promoTopLeft.dy, 0.1));
      expect(promoTopLeft.dx, greaterThan(storyTopLeft.dx));

      final storySize = tester.getSize(storyFinder);
      final promoSize = tester.getSize(promoFinder);
      final youtubeSize = tester.getSize(youtubeFinder);
      expect(storySize.width, closeTo(promoSize.width, 0.1));
      expect(youtubeSize.width, greaterThan(storySize.width * 1.8));
      expect(youtubeSize.width / youtubeSize.height, closeTo(16 / 9, 0.01));
    });

    testWidgets('Browse shows an empty state when asset loading fails', (
      tester,
    ) async {
      await _pumpBrowse(
        tester,
        repository: CombinedTemplateRepository(
          assetRepository: AssetTemplateRepository(
            bundle: _FailingAssetBundle(),
          ),
        ),
        initialLanguage: TemplateLanguage.english,
      );
      await tester.pumpAndSettle();

      expect(find.text('No templates found'), findsOneWidget);
      expect(
        find.text('Try changing filters or view all templates.'),
        findsOneWidget,
      );
      expect(find.text('Minimal quote'), findsNothing);
      expect(find.text('Watch This'), findsNothing);
    });

    testWidgets('opening a JSON template builds a valid EditorDocument', (
      tester,
    ) async {
      Template? opened;
      await _pumpBrowse(
        tester,
        repository: _sampleCombinedRepository(),
        initialLanguage: TemplateLanguage.english,
        onOpen: (template) => opened = template,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'watch');
      await tester.pumpAndSettle();
      final watchTileFinder = find.byKey(
        const ValueKey('browse-template-tile-en_youtube_watch_this'),
        skipOffstage: false,
      );
      expect(watchTileFinder, findsOneWidget);
      await tester.ensureVisible(watchTileFinder);
      await tester.pumpAndSettle();
      await tester.tap(watchTileFinder);
      await tester.pump();

      expect(opened?.id, 'en_youtube_watch_this');
      final document = opened!.build();
      expect(document, isA<EditorDocument>());
      expect(document.width, 1280);
      expect(document.height, 720);
      expect(document.layers, isNotEmpty);
    });
  });
}

Future<void> _pumpHomeSection(
  WidgetTester tester, {
  required List<Template> templates,
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: TemplatesSection(onOpen: (_) {}, templates: templates),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpBrowse(
  WidgetTester tester, {
  required CombinedTemplateRepository repository,
  TemplateLanguage initialLanguage = TemplateLanguage.english,
  TemplateCategory? initialCategory,
  void Function(Template)? onOpen,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        combinedTemplateRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TemplatesBrowseScreen(
          onOpen: onOpen ?? (_) {},
          initialLanguage: initialLanguage,
          initialCategory: initialCategory,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpBrowseWithTemplates(
  WidgetTester tester, {
  required List<Template> templates,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TemplatesBrowseScreen(
          onOpen: (_) {},
          initialLanguage: TemplateLanguage.english,
          templates: templates,
        ),
      ),
    ),
  );
  await tester.pump();
}

Template _layoutTemplate({
  required String id,
  required String name,
  required TemplateCategory category,
  required Size size,
}) {
  return Template(
    id: id,
    name: name,
    category: category,
    language: TemplateLanguage.english,
    build: () => EditorDocument(
      width: size.width,
      height: size.height,
      layers: const [],
      backgroundColor: const Color(0xFFF5EFE6),
    ),
  );
}

CombinedTemplateRepository _sampleCombinedRepository() {
  return CombinedTemplateRepository(
    assetRepository: AssetTemplateRepository(bundle: _sampleBundle()),
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
