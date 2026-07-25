// The Canvas panel's readability pass.
//
// Three things were wrong with it, all visible in one screenshot:
// the four size presets drew glyphs that did not convey the one fact
// separating them (Portrait and Landscape were literally the SAME
// rectangle icon); the dimensions cost a whole row to restate one
// short value; and Solid|Gradient — a CHILD of colour mode — was
// greyed out rather than collapsed when the background went
// transparent, leaving a dead half-panel that still claimed the space.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_commands.dart';
import 'package:canvas_engine/features/editor/canvas/presentation/aspect_thumb.dart';
import 'package:canvas_engine/features/editor/canvas/presentation/canvas_panel_body.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/section_label.dart';
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

  group('size readout', () {
    testWidgets('rides on the Size label rather than owning a row', (
      tester,
    ) async {
      await pump(tester, width: 1080, height: 1350);
      final label = tester
          .widgetList<SectionLabel>(find.byType(SectionLabel))
          .first;
      expect(label.trailing, isNotNull);

      final text = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(SectionLabel),
              matching: find.byType(Text),
            ),
          )
          .map((t) => stripBidi(t.data ?? ''))
          .join('|');
      expect(text, contains('1080 × 1350'));
    });
  });

  group('background', () {
    testWidgets('colour mode shows the fill controls', (tester) async {
      await pump(tester);
      expect(find.byType(FillModeSection), findsOneWidget);
    });

    testWidgets('transparent COLLAPSES them instead of dimming', (
      tester,
    ) async {
      await pump(tester, mode: CanvasBackgroundMode.transparent);
      expect(
        find.byType(FillModeSection),
        findsNothing,
        reason:
            'a greyed-out Solid|Gradient still claimed the space and '
            'read as broken',
      );
      // And nothing is left dimmed-but-present in its place.
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('the swatch is on the Background label in both modes', (
      tester,
    ) async {
      for (final mode in CanvasBackgroundMode.values) {
        await pump(tester, mode: mode);
        final labels = tester
            .widgetList<SectionLabel>(find.byType(SectionLabel))
            .toList();
        expect(labels.length, greaterThanOrEqualTo(2));
        expect(
          labels[1].trailing,
          isNotNull,
          reason:
              'the panel could say "solid colour" without ever showing '
              'WHICH colour',
        );
      }
    });
  });
}
