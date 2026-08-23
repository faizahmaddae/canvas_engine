// Contract tests for the shared two-level colour picker, driven
// through the public `showColorPickerSheet` entry — the same code
// path every editor call site uses.
//
// Pinned contracts:
//   * HEX/alpha: the hex display is `#RRGGBB`; editing it must NOT
//     silently reset the user's chosen opacity — only an explicit
//     8-char hex is an alpha edit.
//   * Swatch taps are hue choices: current alpha survives.
//   * «Custom» expands to the HSV level in place; back returns.
//   * The hex field stays editable/pasteable on BOTH levels.
//   * Copy puts the current hex on the clipboard.
//   * Exactly ONE close action and NO barrier dim — the colour is
//     live on the canvas, and the old duplicate "Done" is a bug.
//   * The final colour lands in the app-wide recents store when the
//     sheet closes.

import 'package:canvas_engine/features/color_picker/presentation/color_picker_sheet.dart';
import 'package:canvas_engine/features/editor/application/recent_colors_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _openSheet(
  WidgetTester tester, {
  required Color initial,
  ValueChanged<Color>? onLiveChange,
  void Function(Color?)? onResult,
}) async {
  SharedPreferences.setMockInitialValues({});
  // Tall test surface so the full sheet is on screen without scroll
  // plumbing.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final picked = await showColorPickerSheet(
                    ctx,
                    initial: initial,
                    onLiveChange: onLiveChange,
                    title: 'Text color',
                  );
                  onResult?.call(picked);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hex/alpha contract', () {
    testWidgets(
      'editing the 6-char hex preserves the current alpha (no silent opacity reset)',
      (tester) async {
        Color? lastLive;
        await _openSheet(
          tester,
          // 50%-opaque red. Hex display shows `#FF0000` by design.
          initial: const Color(0x80FF0000),
          onLiveChange: (c) => lastLive = c,
        );

        final hex = find.byType(TextField);
        expect(
          hex,
          findsOneWidget,
          reason: 'level 1 has exactly one text field — the hex',
        );
        await tester.enterText(hex, '#00FF00');
        await tester.pump();

        expect(lastLive, isNotNull);
        expect(
          lastLive!.toARGB32() & 0x00FFFFFF,
          0x00FF00,
          reason: 'RGB must reflect the typed value',
        );
        expect(
          lastLive!.a,
          closeTo(0x80 / 255.0, 0.005),
          reason: 'alpha must survive a 6-char hex edit',
        );
      },
    );

    testWidgets('editing an 8-char hex is treated as an explicit alpha edit', (
      tester,
    ) async {
      Color? lastLive;
      await _openSheet(
        tester,
        initial: const Color(0x80FF0000),
        onLiveChange: (c) => lastLive = c,
      );

      // 8-char #AARRGGBB — user explicitly typed the alpha byte.
      await tester.enterText(find.byType(TextField), '#3300FF00');
      await tester.pump();

      expect(lastLive, isNotNull);
      expect(lastLive!.toARGB32() & 0x00FFFFFF, 0x00FF00);
      expect(
        lastLive!.a,
        closeTo(0x33 / 255.0, 0.005),
        reason: 'explicit 8-char alpha must be honoured',
      );
    });
  });

  group('level 1 — swatches', () {
    testWidgets('preset swatch tap applies live and preserves alpha', (
      tester,
    ) async {
      Color? lastLive;
      await _openSheet(
        tester,
        initial: const Color(0x80FF0000),
        onLiveChange: (c) => lastLive = c,
      );

      await tester.tap(
        find.byKey(const ValueKey('color-picker-swatch-EF4444')),
      );
      await tester.pump();

      expect(lastLive, isNotNull);
      expect(lastLive!.toARGB32() & 0x00FFFFFF, 0xEF4444);
      expect(
        lastLive!.a,
        closeTo(0x80 / 255.0, 0.005),
        reason: 'a swatch tap is a hue choice, not an alpha reset',
      );
    });

    testWidgets('preset grid renders all 12 palette colours', (tester) async {
      await _openSheet(tester, initial: const Color(0xFF000000));
      for (final c in kColorPickerPalette) {
        final rgb = (c.toARGB32() & 0x00FFFFFF)
            .toRadixString(16)
            .padLeft(6, '0')
            .toUpperCase();
        expect(
          find.byKey(ValueKey('color-picker-swatch-$rgb')),
          findsOneWidget,
        );
      }
    });

    testWidgets('the shelf costs zero rows empty, six slots once mixing', (
      tester,
    ) async {
      final container = await _openSheet(
        tester,
        initial: const Color(0xFF000000),
      );

      // Empty store: NO reserved row at all — six inert rings were
      // ~70dp of dead vertical in every panel embedding the picker.
      // The heading's hint line alone says what will appear here.
      for (var i = 0; i < 6; i++) {
        expect(
          find.byKey(ValueKey('color-picker-slot-$i')),
          findsNothing,
          reason: 'an empty store must not reserve visible slots',
        );
      }
      expect(find.text('Colors you mix land here'), findsOneWidget);

      // Two mixed colours: they take the LEADING slots and exactly
      // four reserved slots remain. This is the state the redesign
      // exists for — two swatches must read as "two of six", not as
      // two dots adrift in a full-width track.
      final store = container.read(recentColorsControllerProvider.notifier);
      store.remember(const Color(0xFF123456));
      store.remember(const Color(0xFF654321));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('color-picker-recent-123456')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('color-picker-recent-654321')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('color-picker-slot-0')), findsNothing);
      expect(find.byKey(const ValueKey('color-picker-slot-1')), findsNothing);
      for (var i = 2; i < 6; i++) {
        expect(find.byKey(ValueKey('color-picker-slot-$i')), findsOneWidget);
      }
      expect(
        find.text('Colors you mix land here'),
        findsNothing,
        reason: 'the hint belongs to the empty state only',
      );
    });

    testWidgets('a mixed colour reaches the shelf without closing the sheet', (
      tester,
    ) async {
      // The defect this redesign targets: the store used to be
      // written only in dispose(), so nothing the user did in front
      // of the shelf could ever fill it — the row they were meant to
      // populate was already gone by the time it was written.
      final container = await _openSheet(
        tester,
        initial: const Color(0xFFFF0000),
      );

      await tester.enterText(find.byType(TextField), '#123456');
      await tester.pump();

      expect(
        container.read(recentColorsControllerProvider).map((c) => c.toARGB32()),
        contains(0xFF123456),
        reason: 'a hex entry lands in the MRU at its commit fence',
      );
      expect(
        find.byKey(const ValueKey('color-picker-recent-123456')),
        findsOneWidget,
        reason: 'and is visible in the shelf while the sheet is still open',
      );
    });

    testWidgets('recent colour from the store is offered and tappable', (
      tester,
    ) async {
      Color? lastLive;
      final container = await _openSheet(
        tester,
        initial: const Color(0xFF000000),
        onLiveChange: (c) => lastLive = c,
      );
      // Seed a custom (non-palette) recent after opening — the row
      // watches the provider, so it appears live.
      container
          .read(recentColorsControllerProvider.notifier)
          .remember(const Color(0xFF123456));
      await tester.pump();

      final recent = find.byKey(const ValueKey('color-picker-recent-123456'));
      expect(recent, findsOneWidget);
      await tester.tap(recent);
      await tester.pump();
      expect(lastLive!.toARGB32() & 0x00FFFFFF, 0x123456);
    });
  });

  group('level 2 — custom', () {
    testWidgets('Custom expands to the HSV level and back returns', (
      tester,
    ) async {
      await _openSheet(tester, initial: const Color(0xFFFF0000));

      expect(
        find.byKey(const ValueKey('color-picker-level-swatches')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('color-picker-custom')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('color-picker-level-custom')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('color-picker-level-swatches')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('color-picker-back')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('color-picker-level-swatches')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('color-picker-level-custom')),
        findsNothing,
      );
    });

    testWidgets('hex stays editable/pasteable on the custom level', (
      tester,
    ) async {
      Color? lastLive;
      await _openSheet(
        tester,
        initial: const Color(0x80FF0000),
        onLiveChange: (c) => lastLive = c,
      );
      await tester.tap(find.byKey(const ValueKey('color-picker-custom')));
      await tester.pumpAndSettle();

      final hex = find.byType(TextField);
      expect(
        hex,
        findsOneWidget,
        reason: 'level 2 has exactly one text field — the hex',
      );
      // Simulates a paste: enterText replaces the whole field value.
      await tester.enterText(hex, '#00AABB');
      await tester.pump();

      expect(lastLive, isNotNull);
      expect(lastLive!.toARGB32() & 0x00FFFFFF, 0x00AABB);
      expect(
        lastLive!.a,
        closeTo(0x80 / 255.0, 0.005),
        reason: 'alpha rule holds on the custom level too',
      );
    });

    testWidgets('copy puts the current #RRGGBB on the clipboard', (
      tester,
    ) async {
      final clipboardCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          clipboardCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _openSheet(tester, initial: const Color(0xFF12AB34));
      await tester.tap(find.byKey(const ValueKey('color-picker-custom')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('color-picker-copy')));
      await tester.pump();

      final setData = clipboardCalls
          .where((c) => c.method == 'Clipboard.setData')
          .toList();
      expect(setData, hasLength(1));
      expect((setData.single.arguments as Map)['text'], '#12AB34');
    });
  });

  group('chrome contract', () {
    testWidgets('exactly one close action, no Done button, no barrier dim', (
      tester,
    ) async {
      await _openSheet(tester, initial: const Color(0xFFFF0000));

      expect(find.byKey(const ValueKey('color-picker-close')), findsOneWidget);
      expect(
        find.text('Done'),
        findsNothing,
        reason: 'the duplicate Done affordance was a bug',
      );

      // The modal barrier must be fully transparent — the colour is
      // live on the design and the canvas must stay visible. Flutter
      // only builds an AnimatedModalBarrier (the colour-fading dim)
      // when the barrier colour is non-transparent, so its absence
      // IS the no-dim proof; the plain ModalBarrier that remains
      // keeps tap-outside-to-dismiss working.
      expect(
        find.byType(AnimatedModalBarrier),
        findsNothing,
        reason: 'colour picker must never dim the canvas',
      );
      expect(find.byType(ModalBarrier), findsWidgets);
    });

    testWidgets('× closes and the future resolves with the last pick', (
      tester,
    ) async {
      Color? result = const Color(0xFF000001); // sentinel
      await _openSheet(
        tester,
        initial: const Color(0xFFFF0000),
        onResult: (c) => result = c,
      );
      await tester.tap(
        find.byKey(const ValueKey('color-picker-swatch-3B82F6')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('color-picker-close')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('color-picker-level-swatches')),
        findsNothing,
      );
      expect(result, isNotNull);
      expect(result!.toARGB32() & 0x00FFFFFF, 0x3B82F6);
    });

    testWidgets('dismissing untouched resolves null and remembers nothing', (
      tester,
    ) async {
      Color? result = const Color(0xFF000001); // sentinel
      final container = await _openSheet(
        tester,
        initial: const Color(0xFFFF0000),
        onResult: (c) => result = c,
      );
      await tester.tap(find.byKey(const ValueKey('color-picker-close')));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(container.read(recentColorsControllerProvider), isEmpty);
    });

    testWidgets('closing after a pick records it in the recents store', (
      tester,
    ) async {
      final container = await _openSheet(
        tester,
        initial: const Color(0xFFFF0000),
      );
      await tester.enterText(find.byType(TextField), '#123456');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('color-picker-close')));
      await tester.pumpAndSettle();

      final recents = container.read(recentColorsControllerProvider);
      expect(recents, hasLength(1));
      expect(recents.single.toARGB32() & 0x00FFFFFF, 0x123456);
    });
  });
}
