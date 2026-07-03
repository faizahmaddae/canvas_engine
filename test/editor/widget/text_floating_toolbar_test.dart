import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/text/presentation/text_floating_toolbar.dart';
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

  testWidgets('selected text floating toolbar exposes Edit text directly', (
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

    await tester.pumpWidget(
      wrap(
        const SizedBox.expand(
          child: Stack(
            children: [
              TextFloatingToolbar(
                layer: layer,
                viewport: ViewportState.identity,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Edit text',
      ),
      findsOneWidget,
    );
  });

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
