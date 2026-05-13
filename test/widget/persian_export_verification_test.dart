// Sprint 1 / Task 1 — Persian PNG export verification.
//
// Renders representative Persian templates through the production
// PNG exporter and writes the output PNGs to `build/test_exports/`
// so a human can eyeball them for correct RTL glyph order, joining
// and bidi positioning.
//
// What this test proves automatically:
//   * The export pipeline does not crash on Persian content.
//   * The output is a valid, non-empty PNG with the expected pixel
//     dimensions (proves the render tree actually painted).
//
// What this test cannot prove without a human (or OCR):
//   * That individual glyphs joined correctly and that bidi flowed
//     right-to-left. That's why we save the PNGs to disk and ask
//     the reviewer to look.
//
// To inspect:
//   $ flutter test test/widget/persian_export_verification_test.dart
//   $ open build/test_exports/

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/engine/export/document_png_exporter.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show CachingAssetBundle, FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the actual TTFs the templates reference, so the exported
/// PNG shows real glyphs instead of Ahem placeholder boxes. Without
/// this, every character renders as a square block — useless for
/// visual verification of Persian shaping.
Future<void> _loadAppFonts() async {
  // Map of font family name (as declared in pubspec) to one or more
  // TTF asset paths. Includes every face the test templates use.
  const families = <String, List<String>>{
    'Hanken_Grotesk': [
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Regular.ttf',
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Bold.ttf',
    ],
    'Raleway': [
      'assets/fonts/english/Raleway/Raleway-Regular.ttf',
      'assets/fonts/english/Raleway/Raleway-Bold.ttf',
    ],
    'Dancing_Script': [
      'assets/fonts/english/Dancing_Script/DancingScript-Regular.ttf',
      'assets/fonts/english/Dancing_Script/DancingScript-Bold.ttf',
    ],
    'Chivo_Mono': [
      'assets/fonts/english/Chivo_Mono/ChivoMono-Regular.ttf',
      'assets/fonts/english/Chivo_Mono/ChivoMono-Bold.ttf',
    ],
    'BTitrBd': ['assets/fonts/farsi/BTitrBd.ttf'],
    'Vazir_Regular': ['assets/fonts/farsi/Vazir_Regular.ttf'],
    'Lalezar': ['assets/fonts/farsi/Lalezar.ttf'],
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
  // Templates we care about for the Persian launch. Mix of square
  // and story canvas, mix of short single-line + multi-line
  // paragraph text, and at least one with Persian numerals so we
  // can confirm digit ordering survives export.
  const persianIds = <String>[
    'fa_birthday',
    'fa_quote_minimal',
    'fa_event',
    'fa_announcement',
    'fa_insta_story_v1',
    'fa_insta_story_bold_word_v1',
    'fa_insta_story_announcement_v1',
    'fa_insta_story_frame_v1',
    'fa_insta_story_minimal_v1',
    'fa_poetry_v1',
    'fa_poetry_minimal_v1',
    'fa_poetry_traditional_v1',
    'fa_poetry_overlay_v1',
    'fa_promo_v1',
    'fa_promo_sale_v1',
    'fa_promo_event_v1',
    'fa_promo_launch_v1',
  ];

  // English controls, rendered the same way, so a reviewer can
  // diff the Latin baseline against the Persian output and rule
  // out unrelated rendering regressions.
  const englishControlIds = <String>[
    'en_birthday_confetti',
    'en_quote_minimal',
    'en_yt_thumb_v1',
  ];

  final outputDir = Directory('build/test_exports');
  late final Map<String, Template> templatesById;

  setUpAll(() async {
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }
    await _loadAppFonts();
    final templates = await AssetTemplateRepository(
      bundle: _assetBundle(),
    ).loadTemplates();
    templatesById = {for (final template in templates) template.id: template};
  });

  Future<Uint8List> exportTemplate(WidgetTester tester, Template t) async {
    final boundaryKey = GlobalKey();
    final doc = t.build();

    // Make the test surface large enough to host the document at
    // native pixel size — production uses an off-screen overlay
    // sized to the document, but here we just expand the viewport.
    tester.view.physicalSize = Size(doc.width, doc.height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        // Ambient LTR mirrors the production export host. Each
        // TextLayer self-directs based on its content via
        // `textDirectionForContent`, so this ambient should not
        // flip Persian glyphs — and that is exactly what this
        // test exists to verify.
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
    return bytes!;
  }

  Future<ui.Image> decodePng(WidgetTester tester, Uint8List bytes) async {
    final image = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    });
    return image!;
  }

  for (final id in [...persianIds, ...englishControlIds]) {
    testWidgets('exports $id to a valid PNG and writes it to disk', (
      tester,
    ) async {
      final template =
          templatesById[id] ??
          (throw StateError('Template $id missing from asset catalog'));
      final doc = template.build();

      final bytes = await exportTemplate(tester, template);

      // PNG magic number — proves the bytes are a real PNG, not a
      // truncated buffer or an empty surface.
      expect(
        bytes.sublist(0, 8),
        equals(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        reason: '$id did not produce valid PNG bytes',
      );

      final image = await decodePng(tester, bytes);
      expect(image.width, doc.width.round(), reason: '$id PNG width mismatch');
      expect(
        image.height,
        doc.height.round(),
        reason: '$id PNG height mismatch',
      );
      image.dispose();

      final file = File('${outputDir.path}/$id.png');
      file.writeAsBytesSync(bytes);
      // Print path so the reviewer can find the artefact even
      // when the test runs in CI.
      // ignore: avoid_print
      print(
        '  → wrote ${file.path} (${bytes.length} bytes, '
        '${doc.width.round()}×${doc.height.round()})',
      );
    });
  }
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
