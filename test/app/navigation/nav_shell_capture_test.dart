// Visual capture of the NavShell (Home tab) — the non-editor proof
// screen for theme-level changes. Writes light + dark PNGs (fa
// locale) to build/test_exports/home_{light,dark}.png for design
// review. Not a regression test — the only assertion is that the
// shell rendered.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/app/navigation/nav_shell.dart';
import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:canvas_engine/features/editor/application/autosave_controller.dart';
import 'package:canvas_engine/features/editor/application/edit_journal.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_path_provider.dart';
import '../../support/temp_projects_dir.dart';

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

void main() {
  final outputDir = Directory('build/test_exports');

  setUpAll(() async {
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);
    await _loadAppFonts();
    await _loadMaterialIcons();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A never-saved session's leftover journal, so the capture shows
  /// the resume offer that only appears when one exists.
  Future<void> seedDraft(WidgetTester tester) async {
    installFakeDocumentsDir();
    await tester.runAsync(() async {
      final journal = await EditJournal.open(AutosaveController.draftJournalId);
      await journal.flushNow(
        EditorDocument(
          layers: [
            ShapeLayer(
              id: 'draft-preview',
              transform: LayerTransform(
                position: Offset.zero,
                size: const Size(80, 80),
              ),
              kind: ShapeKind.rectangle,
              fillColor: const Color(0xFF112233),
            ),
          ],
          width: 1080,
          height: 1080,
        ),
      );
      await journal.writeMeta(name: 'پوستر نوروز');
    });
  }

  /// A saved-project set for the desk variant: the newest becomes the
  /// continue hero, the rest fill the rail. Distinct timestamps keep
  /// the newest-first order deterministic; distinct canvas ratios show
  /// the hero's honest-ratio pane doing its job.
  Future<void> seedProjects(WidgetTester tester, ProviderContainer c) async {
    EditorDocument doc(double w, double h, Color fill) => EditorDocument(
      layers: [
        ShapeLayer(
          id: 'seed-$w-$h',
          transform: LayerTransform(
            position: Offset(w * 0.25, h * 0.25),
            size: Size(w * 0.5, h * 0.5),
          ),
          kind: ShapeKind.circle,
          fillColor: fill,
        ),
      ],
      width: w,
      height: h,
    );
    final now = DateTime.now();
    final seeds = [
      ('پوستر نوروز', 1080.0, 1350.0, const Color(0xFFE5A044)),
      ('استوری فروش', 1080.0, 1920.0, const Color(0xFFC96A72)),
      ('بنر یوتیوب', 1920.0, 1080.0, const Color(0xFF3E8D87)),
    ];
    await tester.runAsync(() async {
      await c.read(projectStoreProvider.future);
      for (final (i, (name, w, h, fill)) in seeds.indexed) {
        await c
            .read(projectStoreProvider.notifier)
            .upsert(
              Project(
                id: 'seed-$i',
                name: name,
                width: w,
                height: h,
                createdAt: now.subtract(Duration(hours: i + 1)),
                lastModified: now.subtract(Duration(hours: i + 1)),
                documentJson: DocumentCodec.encode(doc(w, h, fill)),
              ),
            );
      }
    });
  }

  Future<void> capture(
    WidgetTester tester, {
    required Brightness brightness,
    required String fileName,
    bool withDraft = false,
    bool withProjects = false,
  }) async {
    if (withDraft) await seedDraft(tester);
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final dir = tempProjectsDir();
    final container = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(container.dispose);
    if (withProjects) await seedProjects(tester, container);
    final boundaryKey = GlobalKey();
    // The draft offer resolves in a post-frame callback that reads the
    // journal off disk. Real IO never completes in the fake-async zone,
    // so for that variant the FIRST pump has to happen inside
    // `runAsync` — draining afterwards is too late, the read was
    // already started in the wrong zone.
    Future<void> pumpTree() => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('fa'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(locale: const Locale('fa')),
            darkTheme: AppTheme.dark(locale: const Locale('fa')),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: const NavShell(),
          ),
        ),
      ),
    );
    if (withDraft) {
      await tester.runAsync(() async {
        await pumpTree();
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
    } else {
      await pumpTree();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavShell), findsOneWidget);
    if (withDraft) {
      // A capture that quietly lost its subject is worse than no
      // capture: it looks like proof.
      expect(
        find.byKey(const ValueKey('home-resume-draft')),
        findsOneWidget,
        reason: 'the draft offer never rendered — capture would be a lie',
      );
    }

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await tester.runAsync(
      () => boundary.toImage(pixelRatio: 2.0),
    );
    final byteData = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );
    final bytes = byteData!.buffer.asUint8List();
    final file = File('${outputDir.path}/$fileName');
    file.writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('  → wrote ${file.path} (${bytes.length} bytes)');
    image!.dispose();
  }

  testWidgets('NavShell visual capture — light', (tester) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'home_light.png',
    );
  });

  testWidgets('NavShell visual capture — dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'home_dark.png',
    );
  });

  testWidgets('NavShell visual capture — resume-draft offer, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'home_draft_light.png',
      withDraft: true,
    );
  });

  testWidgets('NavShell visual capture — resume-draft offer, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'home_draft_dark.png',
      withDraft: true,
    );
  });

  testWidgets('NavShell visual capture — populated desk, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'home_desk_light.png',
      withProjects: true,
    );
  });

  testWidgets('NavShell visual capture — populated desk, dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'home_desk_dark.png',
      withProjects: true,
    );
  });
}
