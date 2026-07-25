// Visual capture of the history browser (tb5 follow-up). Pumps the
// browser view with the production theme and a seeded timeline —
// applied steps, the current position, and an undone tail — and
// writes light + dark PNGs (fa) to build/test_exports/ for review.
// Not a regression test; the assertion only confirms it rendered.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/shape_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/history_browser_sheet.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

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

  ShapeLayer shape(String id) => ShapeLayer(
    id: id,
    kind: ShapeKind.rectangle,
    transform: const LayerTransform(
      position: Offset.zero,
      size: Size(100, 100),
    ),
  );

  /// History with three applied steps and one undone tail, so the
  /// capture shows all three row states at once.
  ProviderContainer seeded() {
    final container = ProviderContainer();
    final c = container.read(documentControllerProvider.notifier);
    c.newDocument(width: 1080, height: 1080);
    c.execute(AddLayerCommand(shape('s1')));
    c.execute(
      const SetShapeFillCommand(layerId: 's1', color: Color(0xFF3366FF)),
    );
    c.execute(AddLayerCommand(shape('s2')));
    c.execute(const SetShapeRadiusCommand(layerId: 's2', radius: 24));
    c.undo(); // the radius step becomes the undone tail
    return container;
  }

  Future<void> capture(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = const Size(440, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = seeded();
    addTearDown(container.dispose);
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light(),
          home: Builder(
            builder: (context) {
              final tokens = AppTokens.of(context);
              return Scaffold(
                backgroundColor: tokens.pageBg,
                body: SafeArea(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    // Framed like the modal host frames it: rounded
                    // surface card, title, then the timeline.
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Row(
                              children: [
                                Icon(
                                  AppIcons.history,
                                  color: tokens.textPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppLocalizations.of(context).historyTitle,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Flexible(child: HistoryBrowserView()),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

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
    final name = brightness == Brightness.dark
        ? 'editor_history_dark.png'
        : 'editor_history_light.png';
    File('${outputDir.path}/$name').writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('  → wrote ${outputDir.path}/$name (${bytes.length} bytes)');
    image!.dispose();

    expect(find.text('تاریخچه'), findsWidgets);
    expect(find.text('افزودن شکل'), findsWidgets); // Add shape, fa
  }

  testWidgets('history browser capture — light', (tester) async {
    await capture(tester, Brightness.light);
  });

  testWidgets('history browser capture — dark', (tester) async {
    await capture(tester, Brightness.dark);
  });
}
