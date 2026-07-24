// Sprint 1 / Task 2 — visual capture of SizePickerDialog.
//
// Pumps the dialog with the production app theme and saves a PNG of
// the rendered surface to build/test_exports/size_picker_dialog.png
// for design review. Not a regression test — the only assertion is
// that the dialog actually rendered.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/home/presentation/widgets/size_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadAppFonts() async {
  const families = <String, List<String>>{
    'Hanken_Grotesk': [
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Regular.ttf',
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Bold.ttf',
    ],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

void main() {
  final outputDir = Directory('build/test_exports');

  setUpAll(() async {
    if (!outputDir.existsSync()) outputDir.createSync(recursive: true);
    await _loadAppFonts();
  });

  testWidgets('SizePickerDialog visual capture', (tester) async {
    tester.view.physicalSize = const Size(440, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: const SizePickerDialog(),
            ),
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
    final file = File('${outputDir.path}/size_picker_dialog.png');
    file.writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('  → wrote ${file.path} (${bytes.length} bytes)');
    image!.dispose();

    expect(find.text('New design'), findsOneWidget);
    expect(find.text('SQUARE'), findsOneWidget);
    expect(find.text('PORTRAIT'), findsOneWidget);
    expect(find.text('LANDSCAPE'), findsOneWidget);
    expect(find.text('STORY'), findsOneWidget);
    expect(find.text('YouTube Thumbnail'), findsOneWidget);
    expect(find.text('LinkedIn Post'), findsOneWidget);
    expect(find.text('Portrait 4:5'), findsOneWidget);
  });
}
