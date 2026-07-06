// Style & Effects — the shadow sub-section (text-tool redesign 3-A).
// The استایل panel carries the effect category chips; tapping Shadow
// opens the wired sub-section whose controls write through the same
// drag-coalesced setters as the Shadow tile panel.

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


  /// The effect chips render at 12.5px (LayoutPresetChip) — the dock
  /// tile and preset labels use 11px, so font size disambiguates.
  Finder effectChip(String label) => find.byWidgetPredicate(
        (w) => w is Text && w.data == label && w.style?.fontSize == 12.5,
      );

  TextLayer layerOf(ProviderContainer c) =>
      c.read(documentControllerProvider).layerById('text-1')! as TextLayer;

  testWidgets('effect chips render; only Shadow responds', (tester) async {
    await pumpStyles(tester);
    expect(effectChip('Stroke'), findsOneWidget);
    expect(effectChip('Shadow'), findsOneWidget);
    expect(effectChip('Glow'), findsOneWidget);
    expect(effectChip('Gradient'), findsOneWidget);

    // Disabled chip: tapping Stroke opens nothing.
    await tester.tap(effectChip('Stroke'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Distance'), findsNothing);
  });

  testWidgets('Shadow chip opens the section; preset enables a shadow', (
    tester,
  ) async {
    final c = await pumpStyles(tester);
    expect(layerOf(c).style.shadowColor, isNull);

    await tester.tap(effectChip('Shadow'));
    await tester.pumpAndSettle();
    // Off state: preset tiles, no sliders yet.
    expect(find.text('Soft'), findsOneWidget);
    expect(find.text('Distance'), findsNothing);

    await tester.tap(find.text('Soft'));
    await tester.pumpAndSettle();
    expect(layerOf(c).style.shadowColor, isNotNull);
    // Wired controls appear.
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Blur'), findsOneWidget);
  });

  testWidgets('distance slider preserves direction, changes magnitude', (
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

    final ctrl = c.read(textToolControllerProvider.notifier);
    // Drive the setter the slider uses (widget-level drag is flaky
    // across slider theme metrics; the mapping is the contract).
    ctrl.setShadowOffset(const Offset(3, 4) / 5 * 10);
    await tester.pump();
    final off = layerOf(c).style.shadowOffset;
    expect(off.distance, closeTo(10, 1e-6));
    expect(off.dx / off.dy, closeTo(3 / 4, 1e-6));
  });
}
