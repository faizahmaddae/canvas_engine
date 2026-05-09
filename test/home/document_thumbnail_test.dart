import 'package:canvas_engine/features/editor/engine/core/background_fill.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/rendering/background_fill_box.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_thumbnail.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:canvas_engine/features/templates/domain/template_catalog.dart';
import 'package:canvas_engine/features/templates/presentation/template_preview.dart';
import 'package:flutter/material.dart';
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
  group('DocumentThumbnail', () {
    testWidgets('paints document.backgroundColor (not white)',
        (tester) async {
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

    testWidgets('paints no backdrop when canvas is transparent',
        (tester) async {
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

    testWidgets('every catalog template paints its own background',
        (tester) async {
      for (final t in TemplateCatalog.all) {
        final doc = t.build();
        if (doc.backgroundMode == CanvasBackgroundMode.transparent) {
          continue;
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 160,
                height: 200,
                child: TemplatePreview(template: t),
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
          reason: 'Template ${t.id} produced no background fill',
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
                'Template ${t.id} thumbnail background drifted from doc',
          );
        }
      }
    });
  });
}
