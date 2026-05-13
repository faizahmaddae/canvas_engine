import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/rendering/background_fill_box.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_thumbnail.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/data/template_manifest.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/presentation/template_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Central thumbnail-renderer contract.
///
/// Both Home template thumbnails (live `DocumentThumbnail` widgets)
/// and Recent project thumbnails (PNGs captured at save time via
/// `DocumentPngExporter` with `background:
/// DocumentThumbnail.backgroundFor(doc)`) must funnel through the
/// same source of truth so that what shows on Home is always what
/// opens in the editor.
void main() {
  late List<Template> assetTemplates;

  setUpAll(() async {
    assetTemplates = await AssetTemplateRepository(
      bundle: _MemoryTemplateBundle(),
    ).loadTemplates();
  });

  group('DocumentThumbnail', () {
    testWidgets('paints document.backgroundColor (not white)', (tester) async {
      const yellow = Color(0xFFFFEB3B);
      final doc = EditorDocument(
        width: 400,
        height: 400,
        layers: const [],
        backgroundColor: yellow,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: DocumentThumbnail(document: doc)),
          ),
        ),
      );
      await tester.pump();
      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(DocumentThumbnail),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(box.color, yellow);
    });

    testWidgets('paints no backdrop when canvas is transparent', (
      tester,
    ) async {
      final doc = EditorDocument(
        width: 200,
        height: 200,
        layers: const [],
        backgroundMode: CanvasBackgroundMode.transparent,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: DocumentThumbnail(document: doc)),
          ),
        ),
      );
      await tester.pump();
      // Transparent mode + honorTransparentMode=true => zero
      // ColoredBoxes inside the thumbnail (the layer list is empty
      // in this fixture).
      expect(
        find.descendant(
          of: find.byType(DocumentThumbnail),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
    });

    test('backgroundFor() mirrors document.backgroundColor', () {
      const teal = Color(0xFF008080);
      final doc = EditorDocument(
        width: 100,
        height: 100,
        layers: const [],
        backgroundColor: teal,
      );
      expect(DocumentThumbnail.backgroundFor(doc), teal);
    });
  });

  group('TemplatePreview', () {
    testWidgets('routes through DocumentThumbnail', (tester) async {
      final template = Template(
        id: 'pink-card',
        name: 'Pink',
        category: TemplateCategory.sale,
        language: TemplateLanguage.english,
        build: () => EditorDocument(
          width: 300,
          height: 300,
          layers: const [],
          backgroundColor: const Color(0xFFFF4081),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: TemplatePreview(template: template),
            ),
          ),
        ),
      );
      await tester.pump();
      // Single source of truth: the preview must contain a
      // DocumentThumbnail, not a hand-rolled DocumentView.
      expect(
        find.descendant(
          of: find.byType(TemplatePreview),
          matching: find.byType(DocumentThumbnail),
        ),
        findsOneWidget,
      );
      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(TemplatePreview),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(box.color, const Color(0xFFFF4081));
    });

    testWidgets('asset-backed templates use raster thumbnail images', (
      tester,
    ) async {
      final template = Template(
        id: 'asset-card',
        name: 'Asset card',
        category: TemplateCategory.youtubeThumbnail,
        language: TemplateLanguage.english,
        thumbnailPath: _assetThumbnailPath,
        build: () => EditorDocument(width: 1280, height: 720, layers: const []),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DefaultAssetBundle(
            bundle: _MemoryImageBundle(),
            child: Scaffold(
              body: SizedBox(
                width: 200,
                height: 240,
                child: TemplatePreview(template: template),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(TemplatePreview),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(TemplatePreview),
          matching: find.byType(DocumentThumbnail),
        ),
        findsNothing,
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(
        image.image,
        isA<AssetImage>().having(
          (provider) => provider.assetName,
          'assetName',
          _assetThumbnailPath,
        ),
      );
    });

    testWidgets('every asset template paints its own background live', (
      tester,
    ) async {
      for (final template in assetTemplates) {
        final doc = template.build();
        if (doc.backgroundMode == CanvasBackgroundMode.transparent) {
          continue;
        }
        final liveTemplate = Template(
          id: template.id,
          name: template.name,
          category: template.category,
          language: template.language,
          build: template.build,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 160,
                height: 200,
                child: TemplatePreview(template: liveTemplate),
              ),
            ),
          ),
        );
        await tester.pump();
        // Backdrop is now rendered by [BackgroundFillBox] regardless
        // of fill variant (solid / linear / radial). The widget is
        // the contract; its child decides whether to use a flat
        // [ColoredBox] or a gradient-bearing [DecoratedBox].
        final fillBoxes = tester
            .widgetList<BackgroundFillBox>(
              find.descendant(
                of: find.byType(TemplatePreview),
                matching: find.byType(BackgroundFillBox),
              ),
            )
            .toList();
        expect(
          fillBoxes.isNotEmpty,
          isTrue,
          reason: 'Template ${template.id} produced no background fill',
        );
        // Solid-only templates must still match the doc's resolved
        // backgroundColor — gradient templates only need the box.
        if (doc.background is SolidBackground) {
          final box = tester.widget<ColoredBox>(
            find.descendant(
              of: find.byType(BackgroundFillBox),
              matching: find.byType(ColoredBox),
            ),
          );
          expect(
            box.color,
            doc.backgroundColor,
            reason:
                'Template ${template.id} thumbnail background drifted from doc',
          );
        }
      }
    });
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

class _MemoryImageBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final manifest = <String, List<Map<String, Object>>>{
        _assetThumbnailPath: <Map<String, Object>>[
          <String, Object>{'asset': _assetThumbnailPath},
        ],
      };
      return const StandardMessageCodec().encodeMessage(manifest)!;
    }
    if (key == _assetThumbnailPath) {
      return ByteData.sublistView(_transparentPngBytes);
    }
    throw FlutterError('Unexpected test asset key $key');
  }
}

const _assetThumbnailPath = 'assets/templates/en_yt_thumb_v1/thumbnail.png';

final Uint8List _transparentPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lK3Q6wAAAABJRU5ErkJggg==',
);
