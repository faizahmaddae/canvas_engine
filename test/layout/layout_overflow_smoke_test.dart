// Deterministic runtime layout sweep: pumps every major surface at a
// matrix of viewport sizes — narrow (320w), short (480h), up to tablet
// — and fails on ANY captured layout exception (RenderFlex overflow,
// unbounded-constraint assertions, mis-parented ParentData). The full
// suite otherwise only exercises the repo-default 440×956, so real
// off-nominal-size overflows hide until a device that small renders
// them. Real app fonts are loaded so Persian/Latin text measures at
// production width (the test-fallback font would fake every glyph to a
// square and mask or invent overflow).
//
// fa locale on purpose: the app is Persian-first / RTL-default.

import 'dart:io';
import 'dart:typed_data';

import 'package:canvas_engine/app/navigation/nav_shell.dart';
import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_session.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:canvas_engine/features/editor/sticker/application/sticker_tool_controller.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/onboarding/presentation/screens/goal_screen.dart';
import 'package:canvas_engine/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:canvas_engine/features/settings/presentation/settings_screen.dart';
import 'package:canvas_engine/features/templates/presentation/templates_browse_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/temp_projects_dir.dart';

Future<void> _loadAppFonts() async {
  const families = <String, List<String>>{
    'Hanken_Grotesk': [
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Regular.ttf',
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Bold.ttf',
    ],
    'Vazir_Regular': ['assets/fonts/farsi/Vazir_Regular.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

Future<void> _loadMaterialIcons() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final file = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// Realistic device viewports. Narrow width (320) exercises Row
/// overflow; short height (480) exercises Column overflow / bottom
/// sheets; the tablet width guards the responsive high end.
const _sizes = <Size>[
  Size(320, 568), // small phone (narrowest common — iPhone SE gen1)
  Size(320, 480), // short — landscape-ish / large text scale
  Size(360, 690), // common small Android
  Size(375, 667), // iPhone SE2 / 8
  Size(440, 956), // repo-default large phone
  Size(834, 1112), // tablet
];

Widget _app({required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('fa'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.light(locale: const Locale('fa')),
    darkTheme: AppTheme.dark(locale: const Locale('fa')),
    home: home,
  );
}

void main() {
  setUpAll(() async {
    await _loadAppFonts();
    await _loadMaterialIcons();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  void applyView(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  // ─── Editor ────────────────────────────────────────────────────────
  // A sample document carrying a shape + a long-ish Persian text + an
  // image layer, so every tool panel has real content to lay out.
  ProviderContainer editorContainer({
    String? select,
    String? textSheet,
    ImageToolSlot? imageSlot,
    ShapeToolSlot? shapeSlot,
    StickerToolSlot? stickerSlot,
  }) {
    final c = ProviderContainer();
    c.read(editorSessionProvider.notifier).state = const EditorSession(
      name: 'نمونهٔ طرح با نامی نسبتاً بلند برای آزمون سرریز چیدمان',
    );
    final ctrl = c.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 1080, height: 1080);
    ctrl.execute(
      AddLayerCommand(
        ShapeLayer(
          id: 'shape-1',
          transform: const LayerTransform(
            position: Offset(120, 620),
            size: Size(840, 300),
          ),
          kind: ShapeKind.rectangle,
          fillColor: const Color(0xFFC0872A),
        ),
      ),
    );
    ctrl.execute(
      AddLayerCommand(
        TextLayer(
          id: 'text-1',
          transform: const LayerTransform(
            position: Offset(140, 220),
            size: Size(800, 240),
          ),
          content: 'نوروزتان پیروز و همیشه شادکام باشید',
          style: const TextStyleSpec(
            fontFamily: 'Vazir_Regular',
            fontSize: 96,
            color: Color(0xFF1F1B16),
          ),
        ),
      ),
    );
    ctrl.execute(
      AddLayerCommand(
        ImageLayer(
          id: 'img-1',
          transform: const LayerTransform(
            position: Offset(140, 140),
            size: Size(800, 500),
          ),
          source: const ImageSource.file('/nonexistent-smoke-image.png'),
        ),
      ),
    );
    if (select != null) {
      c.read(selectionControllerProvider.notifier).select(select);
    }
    if (textSheet != null) {
      c.read(textToolControllerProvider.notifier).openSheet(textSheet);
    }
    if (imageSlot != null) {
      c.read(imageToolControllerProvider.notifier).toggleSlot(imageSlot);
    }
    if (shapeSlot != null) {
      c.read(shapeToolControllerProvider.notifier).toggleSlot(shapeSlot);
    }
    if (stickerSlot != null) {
      c.read(stickerToolControllerProvider.notifier).toggleSlot(stickerSlot);
    }
    return c;
  }

  Future<void> pumpEditor(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: _app(home: const EditorScreen()),
      ),
    );
    // Canvas hides itself until the first auto-fit lands.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Every editor state worth sweeping: base, per-type selection, and
  /// each inline tool panel/sheet.
  final editorStates = <String, ProviderContainer Function()>{
    'base': () => editorContainer(),
    'text-selected': () => editorContainer(select: 'text-1'),
    'text-sheet:size': () =>
        editorContainer(select: 'text-1', textSheet: 'size'),
    'text-sheet:font': () =>
        editorContainer(select: 'text-1', textSheet: 'font'),
    'text-sheet:styles': () =>
        editorContainer(select: 'text-1', textSheet: 'styles'),
    'text-sheet:layout': () =>
        editorContainer(select: 'text-1', textSheet: 'layout'),
    'text-sheet:color': () =>
        editorContainer(select: 'text-1', textSheet: 'color'),
    'text-sheet:more': () =>
        editorContainer(select: 'text-1', textSheet: 'more'),
    'image-selected': () => editorContainer(select: 'img-1'),
    'image-slot:look': () =>
        editorContainer(select: 'img-1', imageSlot: ImageToolSlot.look),
    'image-slot:shape': () =>
        editorContainer(select: 'img-1', imageSlot: ImageToolSlot.shape),
    'image-slot:border': () =>
        editorContainer(select: 'img-1', imageSlot: ImageToolSlot.border),
    'image-slot:shadow': () =>
        editorContainer(select: 'img-1', imageSlot: ImageToolSlot.shadow),
    'shape-selected': () => editorContainer(select: 'shape-1'),
    'shape-slot:style': () =>
        editorContainer(select: 'shape-1', shapeSlot: ShapeToolSlot.style),
    'shape-slot:border': () =>
        editorContainer(select: 'shape-1', shapeSlot: ShapeToolSlot.border),
    'shape-slot:shadow': () =>
        editorContainer(select: 'shape-1', shapeSlot: ShapeToolSlot.shadow),
  };

  for (final entry in editorStates.entries) {
    testWidgets('editor layout — ${entry.key}', (tester) async {
      final failures = <String>[];
      for (final size in _sizes) {
        applyView(tester, size);
        final container = entry.value();
        addTearDown(container.dispose);
        await pumpEditor(tester, container);
        final ex = tester.takeException();
        if (ex != null) failures.add('${entry.key} @ $size → $ex');
      }
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });
  }

  // ─── App shell / Home / Templates / Settings / Onboarding ──────────
  Future<void> pumpShell(WidgetTester tester, Widget home) async {
    final dir = tempProjectsDir();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
        child: _app(home: home),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  final shellStates = <String, Widget>{
    'nav-shell-home': const NavShell(),
    'templates-browse': TemplatesBrowseScreen(onOpen: (_) {}),
    'settings': const SettingsScreen(),
    'onboarding-welcome': WelcomeScreen(onGetStarted: () {}, onSkip: () {}),
    'onboarding-goal': GoalScreen(onContinue: () {}, onSkip: () {}),
  };

  for (final entry in shellStates.entries) {
    testWidgets('shell layout — ${entry.key}', (tester) async {
      final failures = <String>[];
      for (final size in _sizes) {
        applyView(tester, size);
        await pumpShell(tester, entry.value);
        final ex = tester.takeException();
        if (ex != null) failures.add('${entry.key} @ $size → $ex');
      }
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });
  }
}
