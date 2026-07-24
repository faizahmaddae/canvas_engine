// THROWAWAY audit renderer for the Phase-2 template overhaul.
// Renders EVERY assets/templates/*/document.json through the production
// DocumentView and writes PNGs to build/test_exports/audit/. Delete
// before commit (house rule: generator tests never land).
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fontAssets = <String, List<String>>{
  'ARezvan': ['assets/fonts/farsi/ARezvan.ttf'],
  'BNazanin': ['assets/fonts/farsi/BNazanin.ttf'],
  'BTitrBd': ['assets/fonts/farsi/BTitrBd.ttf'],
  'DimaTahriri': ['assets/fonts/farsi/DimaTahriri.ttf'],
  'Dima_Shekaste': ['assets/fonts/farsi/Dima_Shekaste.ttf'],
  'Dirooz': ['assets/fonts/farsi/Dirooz.ttf'],
  'Eliya_Regular': ['assets/fonts/farsi/Eliya Regular.ttf'],
  'Far_Ferdowsi': ['assets/fonts/farsi/Far_Ferdowsi.ttf'],
  'Gandom': ['assets/fonts/farsi/Gandom.ttf'],
  'IranNastaliq': ['assets/fonts/farsi/IranNastaliq.ttf'],
  'IranianSans': ['assets/fonts/farsi/IranianSans.ttf'],
  'Lalezar': ['assets/fonts/farsi/Lalezar.ttf'],
  'Neirizi': ['assets/fonts/farsi/Neirizi.ttf'],
  'Samim_Bold': ['assets/fonts/farsi/Samim_Bold.ttf'],
  'Shabnam': ['assets/fonts/farsi/Shabnam.ttf'],
  'Vazir_Regular': ['assets/fonts/farsi/Vazir_Regular.ttf'],
  'Bungee_Shade': ['assets/fonts/english/Bungee_Shade/BungeeShade-Regular.ttf'],
  'Chivo_Mono': [
    'assets/fonts/english/Chivo_Mono/ChivoMono-Regular.ttf',
    'assets/fonts/english/Chivo_Mono/ChivoMono-Bold.ttf',
  ],
  'Dancing_Script': [
    'assets/fonts/english/Dancing_Script/DancingScript-Regular.ttf',
    'assets/fonts/english/Dancing_Script/DancingScript-Bold.ttf',
  ],
  'Hanken_Grotesk': [
    'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Regular.ttf',
    'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Bold.ttf',
  ],
  'Josefin_Sans': [
    'assets/fonts/english/Josefin_Sans/JosefinSans-Regular.ttf',
    'assets/fonts/english/Josefin_Sans/JosefinSans-Bold.ttf',
  ],
  'Playfair_Display': [
    'assets/fonts/english/Playfair_Display/PlayfairDisplay-VariableFont_wght.ttf',
  ],
  'Raleway': [
    'assets/fonts/english/Raleway/Raleway-Regular.ttf',
    'assets/fonts/english/Raleway/Raleway-Bold.ttf',
  ],
};

Future<void> _loadFonts() async {
  for (final entry in _fontAssets.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

List<Directory> _templateDirs() {
  final root = Directory('assets/templates');
  final dirs = <Directory>[
    ...root.listSync().whereType<Directory>(),
    ...Directory('assets/templates/samples').listSync().whereType<Directory>(),
  ];
  dirs.removeWhere(
    (d) =>
        d.path.endsWith('/samples') ||
        !File('${d.path}/document.json').existsSync(),
  );
  dirs.sort((a, b) => a.path.compareTo(b.path));
  return dirs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  testWidgets('render every template document to PNG', (tester) async {
    final outputDir = Directory('build/test_exports/audit')
      ..createSync(recursive: true);
    final failures = <String, Object>{};
    final missingFonts = <String, Set<String>>{};
    var rendered = 0;

    for (final dir in _templateDirs()) {
      final id = dir.path.split('/').last;
      late final EditorDocument doc;
      try {
        doc = DocumentCodec.decode(
          File('${dir.path}/document.json').readAsStringSync(),
        );
      } catch (e) {
        failures[id] = e;
        continue;
      }

      final source = File('${dir.path}/document.json').readAsStringSync();
      for (final match in RegExp(
        r'"fontFamily":\s*"([^"]+)"',
      ).allMatches(source)) {
        final family = match.group(1)!;
        if (!_fontAssets.containsKey(family)) {
          missingFonts.putIfAbsent(id, () => <String>{}).add(family);
        }
      }

      final boundaryKey = GlobalKey();
      tester.view.physicalSize = Size(doc.width, doc.height);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: Material(
                type: MaterialType.transparency,
                child: Center(
                  child: SizedBox(
                    width: doc.width,
                    height: doc.height,
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: DocumentView(
                        document: doc,
                        backgroundFill: doc.background,
                        honorTransparentMode: true,
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

      final bytes = await tester.runAsync(
        () => DocumentPngExporter.captureBoundary(
          boundaryKey: boundaryKey,
          pixelRatio: 1.0,
        ),
      );
      if (bytes == null) {
        failures[id] = 'captureBoundary returned null';
        continue;
      }
      File('${outputDir.path}/$id.png').writeAsBytesSync(bytes);
      rendered++;
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();

    // ignore: avoid_print
    print(
      'AUDIT: rendered=$rendered decodeFailures=${failures.length} '
      'fontGaps=${missingFonts.length}',
    );
    failures.forEach((id, e) {
      // ignore: avoid_print
      print('FAIL $id: $e');
    });
    missingFonts.forEach((id, fams) {
      // ignore: avoid_print
      print('FONT-GAP $id: ${fams.join(', ')} (family not in test font map)');
    });
    expect(failures, isEmpty);
    expect(
      missingFonts,
      isEmpty,
      reason: 'add families to _fontAssets so renders are font-accurate',
    );
  });
}
