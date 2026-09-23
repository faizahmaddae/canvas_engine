import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/app/app.dart';
import 'package:canvas_engine/app/ui/template_thumb.dart';
import 'package:canvas_engine/features/home/presentation/home_screen.dart';
import 'package:canvas_engine/features/onboarding/application/onboarding_controller.dart';
import 'package:canvas_engine/features/onboarding/presentation/onboarding_flow.dart';
import 'package:canvas_engine/features/onboarding/presentation/screens/goal_screen.dart';
import 'package:canvas_engine/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:canvas_engine/features/settings/application/settings_controller.dart';
import 'package:canvas_engine/features/templates/application/template_repository_provider.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/combined_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'production template UI does not reference TemplateCatalog directly',
    () {
      const screenPaths = [
        'lib/features/home/presentation/home_screen.dart',
        'lib/features/home/presentation/widgets/suggested_templates_rail.dart',
        'lib/features/templates/presentation/templates_browse_screen.dart',
        'lib/features/onboarding/presentation/screens/welcome_screen.dart',
        'lib/features/onboarding/presentation/screens/goal_screen.dart',
      ];

      for (final path in screenPaths) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('TemplateCatalog')), reason: path);
        expect(source, isNot(contains('template_catalog.dart')), reason: path);
      }
    },
  );

  Future<void> pumpFirstLaunch(WidgetTester tester) async {
    // Phone-sized viewport keeps the 2x2 goal grid and Ready preview
    // compositions fully on-screen. The default 800x600 test surface
    // is wide and short, which does not resemble the target phone UI.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          combinedTemplateRepositoryProvider.overrideWithValue(
            CombinedTemplateRepository(
              assetRepository: AssetTemplateRepository(
                bundle: _MemoryTemplateBundle(),
              ),
            ),
          ),
        ],
        child: const CanvasEngineApp(),
      ),
    );
    // Use a short fixed pump. The screens have small entrance
    // animations, and tests should not depend on their final frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> tapAndPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> goToGoal(WidgetTester tester) async {
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('onboarding-get-started')),
    );
  }

  Future<Map<String, Object?>> settingsJson() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app.settings.v1');
    expect(raw, isNotNull);
    return Map<String, Object?>.from(jsonDecode(raw!) as Map);
  }

  Future<void> expectStandalonePreferences({
    required LocalePreference locale,
    required Set<TemplateLanguage> languages,
    required Set<TemplateCategory> categories,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsController.localeStorageKey), locale.name);
    expect(
      prefs.getStringList(SettingsController.contentLanguagesStorageKey),
      unorderedEquals(languages.map((l) => l.name)),
    );
    expect(
      prefs.getStringList(SettingsController.enabledCategoriesStorageKey),
      unorderedEquals(categories.map((c) => c.name)),
    );
  }

  testWidgets('first launch lands on the Welcome screen', (tester) async {
    await pumpFirstLaunch(tester);

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-get-started')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('onboarding-welcome-skip')),
      findsOneWidget,
    );
  });

  testWidgets('welcome skip writes defaults and lands on Home', (tester) async {
    await pumpFirstLaunch(tester);

    await tapAndPump(
      tester,
      find.byKey(const ValueKey('onboarding-welcome-skip')),
    );
    // Settle the AnimatedSwitcher transition without using
    // pumpAndSettle (looping animations never settle).
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(HomeScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding.complete'), isTrue);

    final json = await settingsJson();
    // Locale is Persian by default — onboarding never sets it.
    expect(json['localePreference'], 'persian');
    expect(json['contentLanguages'], unorderedEquals(['english', 'persian']));
    expect(
      json['enabledCategories'],
      unorderedEquals(kDefaultEnabledTemplateCategories.map((c) => c.name)),
    );
    await expectStandalonePreferences(
      locale: LocalePreference.persian,
      languages: kDefaultContentLanguages,
      categories: kDefaultEnabledTemplateCategories,
    );
  });

  testWidgets('Welcome → Goal advances after Get Started', (tester) async {
    await pumpFirstLaunch(tester);
    await goToGoal(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(GoalScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-goal-instagramStory')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('onboarding-goal-youtubeThumbnail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('onboarding-goal-poetryPost')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('onboarding-goal-promotionalPoster')),
      findsOneWidget,
    );
  });

  testWidgets('goal skip enables every category and lands in Persian Home', (
    tester,
  ) async {
    await pumpFirstLaunch(tester);
    await goToGoal(tester);
    await tester.pump(const Duration(milliseconds: 500));

    await tapAndPump(
      tester,
      find.byKey(const ValueKey('onboarding-goal-skip')),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(HomeScreen))),
      TextDirection.rtl,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding.complete'), isTrue);
    final json = await settingsJson();
    expect(
      json['enabledCategories'],
      unorderedEquals(kDefaultEnabledTemplateCategories.map((c) => c.name)),
    );
  });

  testWidgets('goal continue writes the user selection and completes '
      'onboarding', (tester) async {
    await pumpFirstLaunch(tester);
    await goToGoal(tester);
    await tester.pump(const Duration(milliseconds: 500));

    await tapAndPump(
      tester,
      find.byKey(const ValueKey('onboarding-goal-instagramStory')),
    );
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('onboarding-goal-poetryPost')),
    );
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('onboarding-goal-continue')),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(HomeScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding.complete'), isTrue);
    final json = await settingsJson();
    expect(
      json['enabledCategories'],
      unorderedEquals(['instagramStory', 'poetryPost']),
    );
  });

  testWidgets(
    'partial goal selection filters Home category strips (Persian labels)',
    (tester) async {
      await pumpFirstLaunch(tester);
      await goToGoal(tester);
      await tester.pump(const Duration(milliseconds: 500));

      await tapAndPump(
        tester,
        find.byKey(const ValueKey('onboarding-goal-instagramStory')),
      );
      await tapAndPump(
        tester,
        find.byKey(const ValueKey('onboarding-goal-youtubeThumbnail')),
      );
      await tapAndPump(
        tester,
        find.byKey(const ValueKey('onboarding-goal-continue')),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(390, 2200));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The shelf's selection is date-seeded, so WHICH enabled
      // template shows varies by day — the goal filter's contract is
      // pinned from both sides without naming a winner: the enabled
      // categories put SOMETHING on the rail, and the disabled
      // categories' templates never appear, on any day, even
      // offstage.
      expect(find.byType(TemplateThumb), findsWidgets);
      expect(
        find.byKey(
          const ValueKey('home-template-fa_poetry_black_gold_nastaliq'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('home-template-fa_promo_app_launch'),
          skipOffstage: false,
        ),
        findsNothing,
      );
    },
  );

  testWidgets('completed onboarding persists across a restart', (tester) async {
    await pumpFirstLaunch(tester);
    await tapAndPump(
      tester,
      find.byKey(const ValueKey('onboarding-welcome-skip')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const ProviderScope(child: CanvasEngineApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingFlow), findsNothing);
  });

  testWidgets('settings reset onboarding shows onboarding again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding.complete': true});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: CanvasEngineApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.settings));
    await tester.pumpAndSettle();
    final resetLabel = find.text('بازنشانی شروع اولیه');
    await tester.scrollUntilVisible(
      resetLabel,
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(resetLabel);
    await tester.pumpAndSettle();
    // The reset confirms first (ux-audit P2-17) — accept it.
    await tester.tap(find.text('بازنشانی'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding.complete'), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const ProviderScope(child: CanvasEngineApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  test('OnboardingChoices defaults to no categories selected', () {
    const choices = OnboardingChoices();
    expect(choices.selectedCategories, isEmpty);
    expect(
      choices.effectiveCategories,
      equals(kDefaultEnabledTemplateCategories),
    );
  });
}

class _MemoryTemplateBundle extends CachingAssetBundle {
  late final Map<String, String> _assets = _loadTemplateAssets();

  @override
  Future<ByteData> load(String key) async {
    final source = _assets[key];
    if (source == null) {
      throw StateError('Missing test asset $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final source = _assets[key];
    if (source == null) {
      throw StateError('Missing test asset $key');
    }
    return source;
  }
}

Map<String, String> _loadTemplateAssets() {
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

  return assets;
}

String _assetText(String path) => File(path).readAsStringSync();

Map<String, dynamic> _jsonObject(String source) {
  return Map<String, dynamic>.from(jsonDecode(source) as Map);
}
