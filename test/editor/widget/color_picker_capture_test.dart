// Design-review captures for the shared colour picker's level-1
// shelf. Writes PNGs to build/test_exports/color_picker_*.png.
//
// The shelf's whole argument is that its height and shape are the
// same in every state, so the variants are the states: an empty
// store, the two-of-six case that motivated the redesign, and a full
// row. Each renders in both themes, in `fa` — RTL is the product
// default and the heading, hint and leading edge all mirror.
//
// Mechanics mirror `editor_screen_capture_test.dart`: 440x956 at
// DPR 1.0, `toImage(pixelRatio: 2.0)` inside `runAsync`, app fonts
// plus MaterialIcons from the SDK cache.
//
// Known harness limitation, shared with every other capture in this
// repo: `AppIcons` glyphs are Phosphor, shipped inside the
// `phosphor_flutter` package and not registered in the test bundle,
// so they render as tofu boxes. The swatch tick is therefore visible
// as a mark but not as its final shape — colour, layout, grouping,
// RTL mirroring and the selection halo are what these PNGs verify.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/color_picker/presentation/color_picker_body.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/recent_colors_controller.dart';
import 'package:canvas_engine/features/editor/text/presentation/text_input_flow_sheet.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  final outputDir = Directory('build/test_exports');
  final boundaryKey = GlobalKey();

  setUpAll(() async {
    await _loadAppFonts();
    await _loadMaterialIcons();
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);
  });

  /// Colours that read as "mixed by hand" — deliberately unlike the
  /// twelve palette hues, so a reviewer can tell the two groups apart
  /// in the PNG without counting rows.
  const mixed = <Color>[
    Color(0xFF2F6F6A),
    Color(0xFFC77B7B),
    Color(0xFFB8873A),
    Color(0xFF5B3A57),
    Color(0xFF7C8B6B),
    Color(0xFF4A6382),
  ];

  Future<void> capture(
    WidgetTester tester, {
    required Brightness brightness,
    required int recentCount,
    required String fileName,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(recentColorsControllerProvider.notifier);
    // Seeded oldest-first so the MRU order in the shelf runs the same
    // way the list literal reads.
    for (final c in mixed.take(recentCount).toList().reversed) {
      store.remember(c);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(locale: const Locale('fa')),
          darkTheme: AppTheme.dark(locale: const Locale('fa')),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          locale: const Locale('fa'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: Builder(
                  builder: (ctx) => ColoredBox(
                    // The boundary must carry the sheet's own surface:
                    // the picker paints no background of its own, so a
                    // bare boundary composites onto transparent and the
                    // dark capture reads as cream text on white.
                    color: Theme.of(ctx).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: ColorPickerBody(
                        initial: const Color(0xFFFFFFFF),
                        title: 'بوم',
                        onChanged: (_) {},
                        onClose: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The shelf must be present and reserving its full row — a PNG
    // of a collapsed section would silently pass the gate.
    expect(
      find.byKey(const ValueKey('color-picker-level-swatches')),
      findsOneWidget,
    );

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
    image!.dispose();
    File('${outputDir.path}/$fileName').writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('  → wrote ${outputDir.path}/$fileName (${bytes.length} bytes)');
  }

  /// The Studio Composer's style rail (Text Studio redesign): the
  /// quick-ink row shares the palette head with the paint bench, and
  /// the ink dot opens the SAME shared picker sheet — captured so a
  /// reviewer can hold this PNG next to `color_picker_partial_*` and
  /// see one colour grammar across surfaces.
  Future<void> captureComposer(
    WidgetTester tester, {
    required Brightness brightness,
    required String fileName,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1080, height: 1080);
    final store = container.read(recentColorsControllerProvider.notifier);
    for (final c in mixed.take(2).toList().reversed) {
      store.remember(c);
    }

    late BuildContext ctx;
    final composerKey = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // The sheet renders inside MaterialApp's own Overlay, so the
        // boundary has to sit ABOVE the app, not inside `home`.
        child: RepaintBoundary(
          key: composerKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(locale: const Locale('fa')),
            darkTheme: AppTheme.dark(locale: const Locale('fa')),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            locale: const Locale('fa'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (c) {
                ctx = c;
                return const Scaffold(body: SizedBox.expand());
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    unawaited(Future.sync(() => showTextInputFlowSheet(ctx, initial: 'نمونه')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('composer-ink-dot')),
      findsOneWidget,
      reason: 'the rail is the composer colour surface now',
    );

    final boundary =
        composerKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await tester.runAsync(
      () => boundary.toImage(pixelRatio: 2.0),
    );
    final byteData = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );
    final bytes = byteData!.buffer.asUint8List();
    image!.dispose();
    File('${outputDir.path}/$fileName').writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('  → wrote ${outputDir.path}/$fileName (${bytes.length} bytes)');
  }

  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('add-text composer style rail — $name', (tester) async {
      await captureComposer(
        tester,
        brightness: brightness,
        fileName: 'color_picker_composer_$name.png',
      );
    });

    for (final entry in const {'empty': 0, 'partial': 2, 'full': 6}.entries) {
      testWidgets('colour picker shelf — ${entry.key}, $name', (tester) async {
        await capture(
          tester,
          brightness: brightness,
          recentCount: entry.value,
          fileName: 'color_picker_${entry.key}_$name.png',
        );
      });
    }
  }
}
