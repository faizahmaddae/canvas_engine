// The custom wheel must NEVER scroll. Its HSV square and sliders
// are drag controls — inside a scroll view the finger drags colour,
// so the user can neither scroll nor discover hidden controls.
// Contract: the wheel lives only in the content-sized picker sheet
// (embedded panels hand off to it), has NO Scrollable ancestor, and
// on the smallest supported phone height every control is
// hit-testable without any scrolling.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smallest supported phone (iPhone SE class) — the height where
/// the capped dock panel is shortest and the old inline wheel
/// overflowed into a scroll view.
const Size _smallestPhone = Size(375, 667);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Editor at the smallest phone size with the text colour panel
  /// open, then سفارشی tapped → the custom wheel sheet.
  Future<ProviderContainer> openCustomWheel(WidgetTester tester) async {
    tester.view.physicalSize = _smallestPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 1080, height: 1080);
    ctrl.execute(
      AddLayerCommand(
        const TextLayer(
          id: 'text-1',
          transform: LayerTransform(
            position: Offset(140, 220),
            size: Size(480, 100),
          ),
          content: 'Hello',
          style: TextStyleSpec(fontSize: 48, color: Color(0xFFFF0000)),
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('text-1');
    container.read(textToolControllerProvider.notifier).openSheet('color');

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

    await tester.tap(find.byKey(const ValueKey('color-picker-custom')));
    await tester.pumpAndSettle();
    return container;
  }

  Color textColorOf(ProviderContainer c) =>
      (c.read(documentControllerProvider).layerById('text-1')! as TextLayer)
          .style
          .color;

  testWidgets('custom wheel has no scrollable viewport and every control is '
      'hit-testable on the smallest phone', (tester) async {
    await openCustomWheel(tester);

    final wheel = find.byKey(const ValueKey('color-picker-level-custom'));
    expect(wheel, findsOneWidget, reason: 'سفارشی opens the wheel sheet');

    // The broken pattern, pinned: drag controls must have no
    // Scrollable ancestor anywhere up the tree.
    expect(
      find.ancestor(of: wheel, matching: find.byType(Scrollable)),
      findsNothing,
      reason:
          'the wheel is all drag controls — a scroll view around '
          'it steals the finger and hides controls below the fold',
    );

    // Every control visible AND reachable without any scrolling.
    for (final key in const [
      'color-picker-back',
      'color-picker-close',
      'color-picker-sv',
      'color-picker-hue',
      'color-picker-opacity',
      'color-picker-hex',
      'color-picker-copy',
      'color-picker-eyedropper',
    ]) {
      expect(
        find.byKey(ValueKey(key)).hitTestable(),
        findsOneWidget,
        reason: '$key must be on screen and tappable with no scroll',
      );
    }
  });

  testWidgets(
    'dragging the HSV square changes the colour instead of scrolling',
    (tester) async {
      final container = await openCustomWheel(tester);
      final before = textColorOf(container);
      final sv = find.byKey(const ValueKey('color-picker-sv'));
      final svTopLeftBefore = tester.getTopLeft(sv);

      final gesture = await tester.startGesture(tester.getCenter(sv));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        textColorOf(container),
        isNot(before),
        reason: 'a drag on the square is a colour edit',
      );
      expect(
        tester.getTopLeft(sv),
        svTopLeftBefore,
        reason: 'nothing moved — the drag must not scroll anything',
      );
    },
  );

  testWidgets(
    'embedded panel never swaps to the wheel inline — the capped dock '
    'panel keeps only level 1',
    (tester) async {
      await openCustomWheel(tester);
      // Level 1 (the embedded panel) is still mounted behind the
      // sheet, unswapped.
      expect(
        find.byKey(const ValueKey('color-picker-level-swatches')),
        findsOneWidget,
      );
      // Close the wheel: back to exactly the compact panel.
      await tester.tap(find.byKey(const ValueKey('color-picker-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('color-picker-level-custom')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('color-picker-level-swatches')),
        findsOneWidget,
      );
    },
  );
}
