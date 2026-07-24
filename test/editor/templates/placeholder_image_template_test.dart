// Template photo slots (roadmap 4.11) end-to-end: a template ships an
// ImageLayer pointing at bundled placeholder pixels, those pixels
// survive the codec and actually paint, and the existing replace
// command turns the slot into an ordinary image layer in exactly one
// undo entry — after which the on-canvas affordance is gone.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/history_stack.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_view.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/templates/data/asset_template_repository.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/domain/template_placeholder.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _templateId = 'fa_story_photo_frame';
const _documentPath = 'assets/templates/$_templateId/document.json';

Future<Template> _loadTemplate() async {
  final templates = await AssetTemplateRepository().loadTemplates();
  return templates.firstWhere((t) => t.id == _templateId);
}

/// Same document, read straight off disk. `testWidgets` bodies run in a
/// fake-async zone where an `AssetBundle` read never settles, so the
/// widget tests below take this path; the plain tests above are what
/// prove the bundled/manifest route produces the same thing.
EditorDocument _documentFromDisk() =>
    DocumentCodec.decode(File(_documentPath).readAsStringSync());

ImageLayer _slotOf(EditorDocument doc) =>
    doc.layers.whereType<ImageLayer>().single;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('placeholder image templates', () {
    test(
      'the template builds a document with a resolvable asset slot',
      () async {
        final template = await _loadTemplate();
        final doc = template.build();

        final slot = _slotOf(doc);
        expect(isTemplatePlaceholderImage(slot), isTrue);
        expect(slot.source.assetName, kTemplatePhotoSlotAsset);
        expect(slot.source.filePath, isNull);
        expect(slot.source.networkUrl, isNull);

        // The predicate is worthless if the bytes are not bundled and
        // decodable: the bundle load proves the pubspec asset entry
        // exists, the codec proves the file is a real raster. Both live
        // in a plain `test` because neither completes inside a widget
        // test's fake-async zone.
        final bytes = await rootBundle.load(slot.source.assetName!);
        expect(bytes.lengthInBytes, greaterThan(0));
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(0));
        expect(frame.image.height, greaterThan(0));

        // Composed, not bare: text sits over the photo area.
        expect(doc.layers.length, greaterThan(1));
        expect(slot.transform.size.width, doc.width);
      },
    );

    test(
      'every template photo slot in the catalog uses a bundled asset',
      () async {
        final records = await AssetTemplateRepository().loadAssetTemplates();
        var slots = 0;
        for (final record in records) {
          for (final layer in record.buildDocument().layers) {
            if (!isTemplatePlaceholderImage(layer)) continue;
            slots++;
            final asset = (layer as ImageLayer).source.assetName!;
            expect(
              (await rootBundle.load(asset)).lengthInBytes,
              greaterThan(0),
              reason: '${record.metadata.id} → $asset',
            );
          }
        }
        expect(slots, greaterThan(0));
      },
    );

    test('the slot survives a codec round-trip', () async {
      final doc = (await _loadTemplate()).build();

      final decoded = DocumentCodec.decode(DocumentCodec.encode(doc));

      expect(decoded, doc);
      expect(decoded.layers, doc.layers);
      expect(_slotOf(decoded).source, _slotOf(doc).source);
      expect(isTemplatePlaceholderImage(_slotOf(decoded)), isTrue);
    });

    test(
      'replacing the slot clears the affordance in one undo entry',
      () async {
        final doc = (await _loadTemplate()).build();
        final slot = _slotOf(doc);
        final history = HistoryStack();

        final replaced = history.execute(
          doc,
          ReplaceImageSourceCommand(
            layerId: slot.id,
            source: const ImageSource.file('/tmp/user-photo.jpg'),
          ),
        );

        final filled = _slotOf(replaced);
        expect(isTemplatePlaceholderImage(filled), isFalse);
        expect(filled.source.filePath, '/tmp/user-photo.jpg');
        // Everything else about the layer is untouched — a filled slot is
        // an ordinary image layer, not a special one.
        expect(filled.id, slot.id);
        expect(filled.transform, slot.transform);
        expect(filled.fit, slot.fit);
        expect(history.undoDepth, 1);

        final undone = history.undo(replaced);
        expect(isTemplatePlaceholderImage(_slotOf(undone)), isTrue);
        expect(history.undoDepth, 0);
      },
    );
  });

  group('placeholder image rendering', () {
    testWidgets('the slot paints its bundled asset', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final doc = _documentFromDisk();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            width: doc.width,
            height: doc.height,
            child: DocumentView(document: doc, backgroundFill: doc.background),
          ),
        ),
      );

      // The renderer took the asset branch of `_loadableImage` (rather
      // than the missing-source placeholder) and wrapped it in the
      // decode-size cap every image layer gets.
      final image = tester.widget<Image>(
        find.byWidgetPredicate(
          (w) => w is Image && w.image is ResizeImage,
          description: 'decode-capped Image for the photo slot',
        ),
      );
      final provider = (image.image as ResizeImage).imageProvider;
      expect(provider, isA<AssetImage>());
      expect((provider as AssetImage).assetName, kTemplatePhotoSlotAsset);
      expect(image.fit, BoxFit.cover);
      // No `precacheImage` here on purpose — an asset stream cannot
      // settle inside this zone. The plain test above is what proves
      // the bytes behind this provider decode.
    });
  });

  group('photo slot badge', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('offers the replace hint until the slot is filled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final doc = _documentFromDisk();
      final slot = _slotOf(doc);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(documentControllerProvider.notifier);
      ctrl.loadDocument(doc);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const EditorScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final badge = find.byKey(ValueKey('photo-slot-badge-${slot.id}'));
      // Unselected on purpose: the cue must reach a user who has never
      // touched the slot.
      expect(container.read(selectionControllerProvider).hasSelection, isFalse);
      expect(badge, findsOneWidget);
      expect(find.text('Tap to add your photo'), findsOneWidget);

      ctrl.execute(
        ReplaceImageSourceCommand(
          layerId: slot.id,
          source: const ImageSource.file('/tmp/user-photo.jpg'),
        ),
      );
      await tester.pump();

      expect(badge, findsNothing);
      expect(find.text('Tap to add your photo'), findsNothing);
    });
  });
}
