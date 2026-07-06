// Editor redesign (Phase 1) — visual capture of the full EditorScreen.
//
// Pumps the editor with the production theme in BOTH brightnesses and
// writes PNGs to build/test_exports/editor_{light,dark}.png for design
// review after each redesign commit. Persian locale on purpose: the
// editor is Persian-first, so captures must show the RTL chrome and
// the app's Persian face. Not a regression test — the only assertions
// are that the chrome actually rendered.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_session.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The Material icon font isn't an app asset — widget tests render
/// every [Icon] as a tofu box without it. Pull it from the local
/// Flutter SDK cache so the captures show real glyphs; silently skip
/// if unavailable (captures still render, just with boxes).
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

ProviderContainer _sampleEditor({
  bool withSelection = false,
  bool withSizePanel = false,
}) {
  final container = ProviderContainer();
  container.read(editorSessionProvider.notifier).state =
      const EditorSession(name: 'پوستر نوروز');
  final ctrl = container.read(documentControllerProvider.notifier);
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
        // Document content colour (sample data, not UI chrome).
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
        content: 'نوروزتان پیروز',
        // Ink on the white doc so the sample text is visible; Vazir
        // like a real freshly-created layer (the Persian-first
        // default) so captures show the true content face.
        style: const TextStyleSpec(
          fontFamily: 'Vazir_Regular',
          fontSize: 96,
          color: Color(0xFF1F1B16),
        ),
      ),
    ),
  );
  if (withSelection || withSizePanel) {
    container.read(selectionControllerProvider.notifier).select('text-1');
  }
  if (withSizePanel) {
    // In-dock Size sheet open — exercises the elevated panel + the
    // canvas scrim behind it.
    container.read(textToolControllerProvider.notifier).openSheet('size');
  }
  return container;
}

void main() {
  final outputDir = Directory('build/test_exports');

  setUpAll(() async {
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);
    await _loadAppFonts();
    await _loadMaterialIcons();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> capture(
    WidgetTester tester, {
    required Brightness brightness,
    required String fileName,
    bool withSelection = false,
    bool withSizePanel = false,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = _sampleEditor(
      withSelection: withSelection,
      withSizePanel: withSizePanel,
    );
    addTearDown(container.dispose);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
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
            home: const EditorScreen(),
          ),
        ),
      ),
    );
    // Two extra pumps: the canvas hides itself until the first
    // auto-fit lands (see EditorCanvas `_fittedOnce`).
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AppBar), findsOneWidget);

    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2.0));
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

  testWidgets('EditorScreen visual capture — light', (tester) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_light.png',
    );
  });

  testWidgets('EditorScreen visual capture — dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_dark.png',
    );
  });

  testWidgets('EditorScreen visual capture — selection, light', (tester) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_selection_light.png',
      withSelection: true,
    );
  });

  testWidgets('EditorScreen visual capture — selection, dark', (tester) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_selection_dark.png',
      withSelection: true,
    );
  });

  testWidgets('EditorScreen visual capture — size panel, light', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.light,
      fileName: 'editor_panel_light.png',
      withSizePanel: true,
    );
  });

  testWidgets('EditorScreen visual capture — size panel, dark', (
    tester,
  ) async {
    await capture(
      tester,
      brightness: Brightness.dark,
      fileName: 'editor_panel_dark.png',
      withSizePanel: true,
    );
  });
}
