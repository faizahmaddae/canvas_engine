// Panel-header grammar after the 2026-07 passes: headers are title +
// ✕ only. The last header value chip (Size px) moved into the size
// panel body as the tappable exact-size chip; Border / Background /
// Resize lost their standalone sheets entirely (decoration lives in
// the Styles panel's effect sections, resize behaviour under «بیشتر»).

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

  Future<ProviderContainer> pumpWithSheet(
    WidgetTester tester,
    String sheetId,
  ) async {
    tester.view.physicalSize = const Size(480, 900);
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
        const TextLayer(
          id: 'text-1',
          transform: LayerTransform(
            position: Offset(40, 40),
            size: Size(320, 120),
          ),
          content: 'Hello',
          style: TextStyleSpec(fontSize: 48),
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('text-1');
    container.read(textToolControllerProvider.notifier).openSheet(sheetId);
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

  testWidgets('Size sheet shows exactly one px readout (body chip), '
      'reporting VISUAL px', (tester) async {
    final container = await pumpWithSheet(tester, 'size');
    // The tappable body chip is the ONLY px readout — the header
    // no longer duplicates it.
    final pxText = find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d+px$').hasMatch(w.data ?? ''),
    );
    expect(pxText, findsOneWidget);
    // tb2 12/16: the readout reports VISUAL px. This layer's 120px
    // box up-scales the 48px natural metrics via FittedBox, so the
    // chip must show the magnified value the user actually sees,
    // not the raw fontSize (audit: size-readout-visual-scale-lie).
    final layer =
        container.read(documentControllerProvider).layerById('text-1')!
            as TextLayer;
    final visual = container
        .read(textToolControllerProvider.notifier)
        .visualFontSizeOf(layer);
    expect(visual, greaterThan(48), reason: 'harness layer is up-scaled');
    expect(find.text('${visual.round()}px'), findsOneWidget);
    expect(find.text('48px'), findsNothing, reason: 'raw px was the lie');
  });

  testWidgets('removed decoration sheet ids render no panel', (tester) async {
    // Stale persisted TextSession.openSheet ids from before the bar
    // consolidation must resolve to nothing instead of crashing.
    for (final staleId in ['border', 'background', 'shadow', 'behavior']) {
      final c = await pumpWithSheet(tester, staleId);
      expect(find.text('Off'), findsNothing);
      expect(
        c.read(textToolControllerProvider).openSheet,
        staleId,
        reason: 'session keeps the id; the sheet host just renders nothing',
      );
    }
  });
}
