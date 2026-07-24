// RTL pins for the dock strips (toolbar redesign roadmap tb1, Stage 1
// item 1.2). The skipped group below pins the INTENDED post-fix RTL
// behaviour — stable tile order with direction-aware placement,
// physical right-handed alignment, fade on the clipped side, mirrored
// sibling swipe, trailing-edge Done pill — ahead of the fixes that
// land in tb1 17/17 (EditorDockMetrics + RTL strip fixes), which
// unskips them. Several of these deliberately FAIL against today's
// code (that is the point): right-handed uses logical
// MainAxisAlignment.end (physical LEFT under RTL), the strip fades
// are physical Positioned left/right driven by scroll pixels (wrong
// side under RTL), sheet swipe maps physical-left→next in both
// directions, and the Done pill is hard Positioned right:8. The final
// non-skipped test pins that the LTR behaviour of the same surfaces
// must survive the RTL fix unchanged. NOTE: testWidgets only accepts
// a boolean `skip`, so the required reason string lives on the
// wrapping group().

import 'dart:math' as math;

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_sheet_chrome.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_strip.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/mode_done_button.dart';
import 'package:canvas_engine/features/settings/application/settings_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Main-toolbar tier-1 registry icons in registry order (image,
/// text, sticker, shape, paint) — mirrors `_buildToolbarItems` in
/// editor_screen.dart. Order pins use this prefix because a lazy
/// ListView only builds the tiles near the at-rest edge.
const List<IconData> _tier1Icons = [
  Icons.add_photo_alternate_outlined,
  Icons.text_fields_rounded,
  Icons.emoji_emotions_outlined,
  Icons.category_outlined,
  Icons.brush_outlined,
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps EditorScreen with a fresh 1080² document. [seed] runs
  /// against the container before the first pump (select a layer,
  /// open a sheet, …).
  Future<ProviderContainer> pumpEditor(
    WidgetTester tester, {
    Size viewport = const Size(440, 956),
    Locale locale = const Locale('fa'),
    AppSettings? settings,
    void Function(ProviderContainer container)? seed,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer(
      overrides: [
        if (settings != null) appSettingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1080, height: 1080);
    seed?.call(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const EditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  /// Seeds a selected text layer so the text-mode strip owns the dock.
  void seedSelectedTextLayer(ProviderContainer container) {
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            TextLayer(
              id: 'text-1',
              transform: const LayerTransform(
                position: Offset(140, 220),
                size: Size(800, 240),
              ),
              content: 'سلام',
              style: const TextStyleSpec(fontSize: 96),
            ),
          ),
        );
    container.read(selectionControllerProvider.notifier).select('text-1');
  }

  /// The strip's BUILT tiles as (spec icon, bounding rect), unsorted.
  /// Rect comes from the render box so cached off-viewport tiles are
  /// included with their true physical geometry.
  List<({IconData icon, Rect rect})> stripTiles(WidgetTester tester) {
    final tiles = find.descendant(
      of: find.byType(DockToolStrip),
      matching: find.byType(DockToolTile),
    );
    final result = <({IconData icon, Rect rect})>[];
    for (final el in tiles.evaluate()) {
      final widget = el.widget as DockToolTile;
      final box = el.renderObject! as RenderBox;
      result.add((
        icon: widget.icon,
        rect: box.localToGlobal(Offset.zero) & box.size,
      ));
    }
    return result;
  }

  /// The strip's edge-fade rects. Fades are the only gradient-
  /// decorated DecoratedBoxes inside DockToolStrip (24dp-wide
  /// IgnorePointer overlays; the tiles themselves use solid fills),
  /// so a gradient predicate is the robust finder — it survives the
  /// Positioned left/right → PositionedDirectional rewrite that
  /// 1.17 will make.
  List<Rect> fadeRects(WidgetTester tester) {
    final fades = find.descendant(
      of: find.byType(DockToolStrip),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient is LinearGradient,
      ),
    );
    final result = <Rect>[];
    for (final el in fades.evaluate()) {
      final box = el.renderObject! as RenderBox;
      result.add(box.localToGlobal(Offset.zero) & box.size);
    }
    return result;
  }

  group(
    'RTL strip pins (intended post-fix behavior)',
    () {
      testWidgets('main strip under RTL: first registry slot renders at the '
          'highest physical x, order stable', (tester) async {
        await pumpEditor(tester);

        // Sort the built tiles right→left; the prefix must be the
        // tier-1 registry order. Direction changes PLACEMENT only —
        // the sequence itself must never be reversed or reordered.
        final tiles = stripTiles(tester)
          ..sort((a, b) => b.rect.center.dx.compareTo(a.rect.center.dx));
        expect(tiles.length, greaterThanOrEqualTo(_tier1Icons.length));
        expect(
          tiles.take(_tier1Icons.length).map((t) => t.icon).toList(),
          _tier1Icons,
          reason:
              'under RTL the first slot (image) must sit at the visual '
              'right, followed leftwards by the registry order',
        );
      });

      testWidgets(
        'right-handed setting is PHYSICAL: text strip hugs the physical '
        'right edge under RTL',
        (tester) async {
          // 520dp wide so the 6 text tiles (~420dp) leave ~80dp of
          // slack for the alignment to act on.
          await pumpEditor(
            tester,
            viewport: const Size(520, 956),
            settings: const AppSettings(rightHandedToolbar: true),
            seed: seedSelectedTextLayer,
          );

          final stripRect = tester.getRect(find.byType(DockToolStrip));
          final tiles = stripTiles(tester);
          expect(tiles, isNotEmpty);
          final groupRight = tiles.map((t) => t.rect.right).reduce(math.max);
          final groupLeft = tiles.map((t) => t.rect.left).reduce(math.min);

          // Right-handed means the user's PHYSICAL right thumb,
          // regardless of text direction: the tile group must sit
          // flush against the right content edge (strip padding is
          // 10dp) with all the slack accumulating on the left.
          expect(
            stripRect.right - groupRight,
            lessThan(24),
            reason:
                'right-handed tiles must hug the PHYSICAL right edge '
                'under RTL (logical MainAxisAlignment.end resolves to '
                'physical left — the pre-fix bug)',
          );
          expect(
            groupLeft - stripRect.left,
            greaterThan(40),
            reason: 'the free slack must sit on the physical left',
          );
        },
      );

      testWidgets(
        'main strip fade sits on the CLIPPED side under RTL: physical '
        'left at rest, none on the right',
        (tester) async {
          // 340dp wide so the 9-slot main strip overflows. Under RTL
          // the list is anchored to the physical right at rest, so
          // the overflow is clipped at the physical LEFT — the fade
          // must telegraph "more content" on that side only.
          await pumpEditor(tester, viewport: const Size(340, 956));

          final stripRect = tester.getRect(find.byType(DockToolStrip));
          final fades = fadeRects(tester);
          expect(fades, hasLength(1), reason: 'exactly one fade at rest');
          expect(
            (fades.single.left - stripRect.left).abs(),
            lessThan(1),
            reason:
                'at rest under RTL the fade must sit on the physical '
                'LEFT edge (the clipped side)',
          );
          expect(
            (fades.single.right - stripRect.right).abs(),
            greaterThan(1),
            reason:
                'no fade on the physical right — that side shows the '
                'start of the content, fully visible',
          );
        },
      );

      testWidgets(
        'sibling swipe mirrors under RTL: physical RIGHT drag goes to '
        'the NEXT sheet',
        (tester) async {
          final container = await pumpEditor(
            tester,
            seed: (c) {
              seedSelectedTextLayer(c);
              c.read(textToolControllerProvider.notifier).openSheet('size');
            },
          );
          final chrome = tester.getRect(find.byType(DockSheetChrome));
          final handle = Offset(chrome.center.dx, chrome.top + 7);

          // "Next" is a LOGICAL direction: under RTL the reading flow
          // runs right→left, so advancing to the next sibling is a
          // physical drag to the RIGHT — the mirror of the LTR
          // mapping pinned by dock_sheet_gestures_test.dart.
          await tester.timedDragFrom(
            handle,
            const Offset(140, 0),
            const Duration(milliseconds: 400),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          expect(container.read(textToolControllerProvider).openSheet, 'color');
        },
      );

      testWidgets('sibling swipe mirrors under RTL: physical LEFT drag goes to '
          'the PREV sheet', (tester) async {
        final container = await pumpEditor(
          tester,
          seed: (c) {
            seedSelectedTextLayer(c);
            c.read(textToolControllerProvider.notifier).openSheet('size');
          },
        );
        final chrome = tester.getRect(find.byType(DockSheetChrome));
        final handle = Offset(chrome.center.dx, chrome.top + 7);

        await tester.timedDragFrom(
          handle,
          const Offset(-140, 0),
          const Duration(milliseconds: 400),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(container.read(textToolControllerProvider).openSheet, 'font');
      });

      testWidgets('exit pill anchors at the top TRAILING edge: physical left '
          'under RTL', (tester) async {
        await pumpEditor(
          tester,
          seed: (c) {
            c
                .read(documentControllerProvider.notifier)
                .execute(
                  AddLayerCommand(
                    ShapeLayer(
                      id: 'shape-1',
                      transform: const LayerTransform(
                        position: Offset(40, 40),
                        size: Size(200, 200),
                      ),
                      kind: ShapeKind.rectangle,
                    ),
                  ),
                );
            c.read(selectionControllerProvider.notifier).select('shape-1');
          },
        );

        final pill = find.byType(ModeDoneButton);
        expect(pill, findsOneWidget);
        expect(
          tester.getCenter(pill).dx,
          lessThan(440 / 2),
          reason:
              'the Done pill is trailing-edge chrome: physical LEFT '
              'half of the screen under RTL (today it is hard '
              'Positioned right:8 — the pre-fix bug)',
        );
      });
    },
    skip:
        'Pins intended RTL behavior — unskipped by tb1 17/17 '
        '(RTL strip fixes)',
  );

  // LTR guard: the RTL fixes in 1.17 must not disturb the LTR layout.
  // This test runs (and passes) TODAY and stays green through 1.17.
  testWidgets('LTR guard: main strip keeps first-slot-at-lowest-x and the '
      'at-rest fade on the right', (tester) async {
    await pumpEditor(
      tester,
      viewport: const Size(340, 956),
      locale: const Locale('en'),
    );

    // Order: first registry slot at the LOWEST physical x.
    final tiles = stripTiles(tester)
      ..sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));
    expect(tiles.length, greaterThanOrEqualTo(_tier1Icons.length));
    expect(
      tiles.take(_tier1Icons.length).map((t) => t.icon).toList(),
      _tier1Icons,
    );

    // Fade: at rest the strip is anchored left, clipped right —
    // exactly one fade, on the physical right edge.
    final stripRect = tester.getRect(find.byType(DockToolStrip));
    final fades = fadeRects(tester);
    expect(fades, hasLength(1));
    expect((fades.single.right - stripRect.right).abs(), lessThan(1));
    expect((fades.single.left - stripRect.left).abs(), greaterThan(1));
  });
}
