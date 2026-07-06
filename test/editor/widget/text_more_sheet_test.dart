// The text More sheet — reached from the one text bar's «بیشتر»
// tile (the floating pill was removed in text-tool redesign step 1;
// these tests moved from text_floating_toolbar_test.dart).
import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/panels/text/more_sheet.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets('text More sheet exposes direction mode control', (tester) async {
    const layer = TextLayer(
      id: 'text-1',
      transform: LayerTransform(
        position: Offset(100, 100),
        size: Size(160, 80),
      ),
      content: 'Hello سلام',
      style: TextStyleSpec(fontSize: 24),
      textDirectionMode: TextDirectionMode.rtl,
    );

    await tester.pumpWidget(
      wrap(
        Consumer(
          builder: (context, ref, _) => Center(
            child: ElevatedButton(
              onPressed: () => showTextMoreSheet(context, ref, layer),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Text direction'), findsOneWidget);
    expect(find.text('Right to left'), findsOneWidget);
    expect(find.text('Align'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('text More routes Align and Opacity to compact panels', (
    tester,
  ) async {
    const layer = TextLayer(
      id: 'text-1',
      transform: LayerTransform(
        position: Offset(100, 100),
        size: Size(160, 80),
      ),
      content: 'Hello',
      style: TextStyleSpec(fontSize: 24),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () => showTextMoreSheet(context, ref, layer),
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
    await tester.tap(find.text('Align'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      container.read(contextToolbarControllerProvider),
      ContextToolPanel.align,
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opacity'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      container.read(contextToolbarControllerProvider),
      ContextToolPanel.opacity,
    );
  });
}
