// Style & Effects — the effect sections (compactness pass 2026-07).
// The استایل panel carries the effect category chips; Stroke, Shadow
// and Background are wired (they are the ONLY home for decoration
// after the bar consolidation). The shadow section pairs a 2D offset
// pad (direction + distance in one drag) with a blur slider and a
// mini swatch row.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/ui/panel_offset_pad.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpStyles(
    WidgetTester tester, {
    TextStyleSpec style = const TextStyleSpec(fontSize: 48),
  }) async {
    tester.view.physicalSize = const Size(800, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 400, height: 300);
    ctrl.execute(
      AddLayerCommand(
        TextLayer(
          id: 'text-1',
          transform: const LayerTransform(
            position: Offset(40, 40),
            size: Size(320, 120),
          ),
          content: 'Hello',
          style: style,
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('text-1');
    container.read(textToolControllerProvider.notifier).openSheet('styles');
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
    return container;
  }

  /// The effect chips render at 12.5px (unified PresetChip pill —
  /// tb2 15/16, resized to the prototype's pill grammar in tb7 3/7).
  /// The dock tile and preset labels use 10-11px, so font size still
  /// disambiguates.
  Finder effectChip(String label) => find.byWidgetPredicate(
    (w) => w is Text && w.data == label && w.style?.fontSize == 12.5,
  );

  TextLayer layerOf(ProviderContainer c) =>
      c.read(documentControllerProvider).layerById('text-1')! as TextLayer;

  testWidgets('every effect chip opens a real section — no disabled '
      'vocabulary', (tester) async {
    // Glow/gradient shipped as permanently-dimmed chips and stayed
    // inert for a month (ux-audit P2-19) — a chip that can never do
    // anything is a lying control (§10.3). They return WITH their
    // sections, not before.
    await pumpStyles(tester);
    expect(effectChip('Stroke'), findsOneWidget);
    expect(effectChip('Shadow'), findsOneWidget);
    expect(effectChip('Glow'), findsNothing);
    expect(effectChip('Gradient'), findsNothing);
  });

  testWidgets('Shadow chip opens the section; preset enables a shadow', (
    tester,
  ) async {
    final c = await pumpStyles(tester);
    expect(layerOf(c).style.shadowColor, isNull);

    await tester.tap(effectChip('Shadow'));
    await tester.pumpAndSettle();
    // Off state: preset chips only — the pad/blur row appears once
    // a shadow exists.
    expect(find.text('Soft'), findsOneWidget);
    expect(find.byType(PanelOffsetPad), findsNothing);

    await tester.tap(find.text('Soft'));
    await tester.pumpAndSettle();
    expect(layerOf(c).style.shadowColor, isNotNull);
    // The compact control row appears: 2D offset pad + blur slider.
    expect(find.byType(PanelOffsetPad), findsOneWidget);
    expect(find.text('Blur'), findsOneWidget);
  });

  testWidgets('offset pad drag writes direction AND distance together', (
    tester,
  ) async {
    final c = await pumpStyles(
      tester,
      style: const TextStyleSpec(
        fontSize: 48,
        shadowColor: Color(0x80000000),
        shadowBlur: 8,
        shadowOffset: Offset(3, 4), // distance 5, direction 3:4
      ),
    );
    await tester.tap(effectChip('Shadow'));
    await tester.pumpAndSettle();

    final pad = find.byType(PanelOffsetPad);
    expect(pad, findsOneWidget);

    // Drag from the pad centre toward bottom-right: the emitted
    // offset must point the same way (dx>0, dy>0) with magnitude
    // clamped to the pad's 24px ceiling — one gesture, both facts.
    final center = tester.getCenter(pad);
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final off = layerOf(c).style.shadowOffset;
    expect(off.dx, greaterThan(0));
    expect(off.dy, greaterThan(0));
    expect(off.dx, closeTo(off.dy, 0.01)); // 45° drag → 45° offset
    expect(off.distance, lessThanOrEqualTo(24 + 1e-6));

    // A commit went through the drag-coalescing window: exactly one
    // extra undo step for the whole gesture.
    final ctrl = c.read(documentControllerProvider.notifier);
    ctrl.undo();
    expect(
      layerOf(c).style.shadowOffset,
      const Offset(3, 4),
      reason: 'whole pad drag must collapse into one undo entry',
    );
  });

  testWidgets('setShadowOffset preserves the pad contract (same setter)', (
    tester,
  ) async {
    final c = await pumpStyles(
      tester,
      style: const TextStyleSpec(
        fontSize: 48,
        shadowColor: Color(0x80000000),
        shadowBlur: 8,
        shadowOffset: Offset(3, 4),
      ),
    );
    final ctrl = c.read(textToolControllerProvider.notifier);
    ctrl.setShadowOffset(const Offset(3, 4) / 5 * 10);
    await tester.pump();
    final off = layerOf(c).style.shadowOffset;
    expect(off.distance, closeTo(10, 1e-6));
    expect(off.dx / off.dy, closeTo(3 / 4, 1e-6));
  });

  testWidgets('Background chip opens section; pill preset enables fill', (
    tester,
  ) async {
    final c = await pumpStyles(tester);
    expect(layerOf(c).style.backgroundColor, isNull);

    await tester.tap(effectChip('BG'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pill'));
    await tester.pumpAndSettle();

    final style = layerOf(c).style;
    expect(style.backgroundColor, isNotNull);
    expect(style.backgroundRadius, closeTo(1.0, 0.01));
  });

  testWidgets('Stroke chip opens section; solid preset enables outline', (
    tester,
  ) async {
    final c = await pumpStyles(tester);
    expect(layerOf(c).style.outlineColor, isNull);

    await tester.tap(effectChip('Stroke'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solid'));
    await tester.pumpAndSettle();

    final style = layerOf(c).style;
    expect(style.outlineColor, isNotNull);
    expect(style.outlineWidth, closeTo(2, 0.01));
  });
}
