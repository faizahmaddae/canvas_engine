// The Canvas panel, as rebuilt by docs/canvas-tool-redesign-2026-08:
// a document card (name + dimensions + format word + live background
// frame + rotate) over two one-tap rows. These pins cover the card's
// state display, the one-row background grammar (transparent chip,
// ground swatches, gradient disclosure), and the composite that makes
// leaving transparency a single undo.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/canvas/presentation/aspect_thumb.dart';
import 'package:canvas_engine/features/editor/canvas/presentation/canvas_panel_body.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/ui/fill_mode_section.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/bidi_text.dart';

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    double width = 1080,
    double height = 1080,
    CanvasBackgroundMode mode = CanvasBackgroundMode.color,
    Locale locale = const Locale('en'),
  }) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: width, height: height);
    if (mode != CanvasBackgroundMode.color) {
      c
          .read(documentControllerProvider.notifier)
          .execute(SetCanvasBackgroundModeCommand(mode));
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: locale,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: CanvasPanelBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  group('aspect thumbs', () {
    testWidgets('every preset draws its own ratio — no two alike', (
      tester,
    ) async {
      await pump(tester);
      final thumbs = tester
          .widgetList<AspectThumb>(find.byType(AspectThumb))
          .toList();
      // Four presets plus Custom.
      expect(thumbs.length, 5);

      final ratios = <double>[
        for (final t in thumbs.take(4)) t.width / t.height,
      ];
      expect(
        ratios.toSet().length,
        4,
        reason: 'Portrait and Landscape used to draw an identical glyph',
      );
      // Square, then progressively taller, then wide.
      expect(ratios[0], 1.0);
      expect(ratios[1], lessThan(1.0));
      expect(ratios[2], lessThan(ratios[1]));
      expect(ratios[3], greaterThan(1.0));
    });

    testWidgets('the painted box IS the ratio, capped to one extent', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                AspectThumb(key: ValueKey('sq'), width: 100, height: 100),
                AspectThumb(key: ValueKey('tall'), width: 50, height: 100),
                AspectThumb(key: ValueKey('wide'), width: 200, height: 100),
              ],
            ),
          ),
        ),
      );
      // Each occupies the same optical square so the row keeps a flat
      // baseline, whatever shape it is drawing inside.
      for (final k in const ['sq', 'tall', 'wide']) {
        expect(tester.getSize(find.byKey(ValueKey(k))), const Size(22, 22));
      }

      Size painted(String k) => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(ValueKey(k)),
              matching: find.byType(CustomPaint),
            ),
          )
          .size;

      expect(painted('sq'), const Size(22, 22));
      expect(painted('tall'), const Size(11, 22));
      expect(painted('wide'), const Size(22, 11));
    });

    testWidgets('Custom is dashed — it has no ratio to show', (tester) async {
      await pump(tester);
      final thumbs = tester
          .widgetList<AspectThumb>(find.byType(AspectThumb))
          .toList();
      expect(thumbs.take(4).every((t) => !t.dashed), isTrue);
      expect(thumbs.last.dashed, isTrue);
    });
  });

  group('document card', () {
    testWidgets('states dimensions and format; rotate for non-square', (
      tester,
    ) async {
      await pump(tester, width: 1080, height: 1350);
      expect(find.byKey(const ValueKey('canvas-doc-card')), findsOneWidget);
      final cardText = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('canvas-doc-card')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => stripBidi(t.data ?? ''))
          .join('|');
      expect(cardText, contains('1080 × 1350'));
      expect(find.byKey(const ValueKey('canvas-rotate')), findsOneWidget);
    });

    testWidgets('a square document hides the rotate action (§10.3: a '
        'control that would no-op is not shown)', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('canvas-rotate')), findsNothing);
    });

    testWidgets('a resize that strands a layer wholly outside the canvas '
        'says so in a floating whisper', (tester) async {
      final c = await pump(tester);
      c
          .read(documentControllerProvider.notifier)
          .execute(
            AddLayerCommand(
              ShapeLayer(
                id: 'far',
                transform: const LayerTransform(
                  position: Offset(1500, 1500),
                  size: Size(100, 100),
                ),
                kind: ShapeKind.rectangle,
                fillColor: const Color(0xFF000000),
              ),
            ),
          );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey('canvas-size-preset-1280x720')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('canvas-size-preset-1280x720')),
      );
      await tester.pump();

      expect(
        find.text(
          'Some layers are outside the canvas now — '
          'drag them back in.',
        ),
        findsOneWidget,
        reason: 'the audit-documented silent consequence must be surfaced',
      );
    });

    testWidgets('rotate swaps the dimensions in ONE undoable step', (
      tester,
    ) async {
      final c = await pump(tester, width: 1080, height: 1350);
      final docCtrl = c.read(documentControllerProvider.notifier);
      final entries0 = docCtrl.historyTimeline.length;

      await tester.tap(find.byKey(const ValueKey('canvas-rotate')));
      await tester.pump();

      final doc = c.read(documentControllerProvider);
      expect(doc.width, 1350);
      expect(doc.height, 1080);
      expect(docCtrl.historyTimeline.length, entries0 + 1);
      docCtrl.undo();
      expect(c.read(documentControllerProvider).width, 1080);
    });
  });

  group('background row', () {
    testWidgets('one row: transparent chip, ground swatches, gradient '
        'chip, custom dot — no segmented controls, no embedded picker', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.byKey(const ValueKey('canvas-bg-transparent')),
        findsOneWidget,
      );
      for (final ground in CanvasPanelBody.groundSwatches) {
        final hex = ground.toARGB32().toRadixString(16).padLeft(8, '0');
        expect(
          find.byKey(ValueKey('canvas-bg-solid-$hex')),
          findsOneWidget,
          reason: 'ground $hex must be one tap away',
        );
      }
      expect(find.byKey(const ValueKey('canvas-bg-gradient')), findsOneWidget);
      expect(find.byKey(const ValueKey('canvas-bg-custom')), findsOneWidget);
      expect(
        find.byType(FillModeSection),
        findsNothing,
        reason: 'the two stacked segmented controls died with the redesign',
      );
    });

    testWidgets('transparent chip commits the mode; the colour pick '
        'survives for the return trip', (tester) async {
      final c = await pump(tester);
      final before = c.read(documentControllerProvider).background;

      await tester.ensureVisible(
        find.byKey(const ValueKey('canvas-bg-transparent')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('canvas-bg-transparent')));
      await tester.pump();

      final doc = c.read(documentControllerProvider);
      expect(doc.backgroundMode, CanvasBackgroundMode.transparent);
      expect(doc.background, before);
    });

    testWidgets('picking a ground while transparent is ONE undo back to '
        'transparent (composite: mode + fill)', (tester) async {
      final c = await pump(tester, mode: CanvasBackgroundMode.transparent);
      final docCtrl = c.read(documentControllerProvider.notifier);
      final entries0 = docCtrl.historyTimeline.length;

      await tester.ensureVisible(
        find.byKey(const ValueKey('canvas-bg-solid-ff000000')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('canvas-bg-solid-ff000000')));
      await tester.pump();

      final doc = c.read(documentControllerProvider);
      expect(doc.backgroundMode, CanvasBackgroundMode.color);
      expect((doc.background as SolidBackground).color.toARGB32(), 0xFF000000);
      expect(
        docCtrl.historyTimeline.length,
        entries0 + 1,
        reason: 'leaving transparency is one act, so it is one entry',
      );

      docCtrl.undo();
      final undone = c.read(documentControllerProvider);
      expect(undone.backgroundMode, CanvasBackgroundMode.transparent);
    });

    testWidgets('the gradient chip discloses presets; the angle appears '
        'only once a gradient is installed', (tester) async {
      final c = await pump(tester);
      expect(
        find.byKey(const ValueKey('canvas-gradient-preset-0')),
        findsNothing,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('canvas-bg-gradient')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('canvas-bg-gradient')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('canvas-gradient-preset-0')),
        findsOneWidget,
      );
      expect(
        find.byType(Slider),
        findsNothing,
        reason: 'no gradient installed yet — nothing for an angle to rotate',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('canvas-gradient-preset-0')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('canvas-gradient-preset-0')));
      await tester.pumpAndSettle();
      final doc = c.read(documentControllerProvider);
      expect(doc.background, isA<LinearGradientBackground>());
      expect(find.byType(Slider), findsOneWidget);
    });
  });
}
