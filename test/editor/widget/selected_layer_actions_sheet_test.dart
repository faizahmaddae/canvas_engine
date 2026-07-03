import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/selected_layer_actions_sheet.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ShapeLayer _shape(String id) => ShapeLayer(
  id: id,
  transform: const LayerTransform(
    position: Offset(40, 40),
    size: Size(120, 80),
  ),
  kind: ShapeKind.rectangle,
);

ProviderContainer _containerWith(List<EditorLayer> layers) {
  final container = ProviderContainer();
  container
      .read(documentControllerProvider.notifier)
      .newDocument(width: 400, height: 400);
  for (final layer in layers) {
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
  }
  return container;
}

Widget _host(
  ProviderContainer container,
  EditorLayer layer, {
  List<EditorLayer>? selectedLayers,
  VoidCallback? onOpenLayers,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => FilledButton(
              onPressed: () => showSelectedLayerActionsSheet(
                context,
                ref,
                layer,
                selectedLayers: selectedLayers,
                onOpenLayers: onOpenLayers,
              ),
              child: const Text('Open actions'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('selected layer sheet exposes compact structural actions', (
    tester,
  ) async {
    var openedLayers = false;
    final bottom = _shape('bottom');
    final top = _shape('top');
    final container = _containerWith([bottom, top]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(container, bottom, onOpenLayers: () => openedLayers = true),
    );
    await tester.tap(find.text('Open actions'));
    await tester.pumpAndSettle();

    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Lock layer'), findsOneWidget);
    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('Bring forward'), findsOneWidget);
    expect(find.text('Send backward'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Align'), findsNothing);
    expect(find.text('Opacity'), findsNothing);
    expect(find.text('Edit text'), findsNothing);
    expect(find.text('Replace image'), findsNothing);
    expect(find.text('Relink image'), findsNothing);
    expect(find.text('Crop image'), findsNothing);

    await tester.tap(find.text('Layers'));
    await tester.pump();
    expect(openedLayers, isTrue);
  });

  testWidgets('multi-select More sheet stays compact and structural', (
    tester,
  ) async {
    var openedLayers = false;
    final a = _shape('a');
    final b = _shape('b');
    final c = _shape('c');
    final container = _containerWith([a, b, c]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(
        container,
        c,
        selectedLayers: [a, b, c],
        onOpenLayers: () => openedLayers = true,
      ),
    );
    await tester.tap(find.text('Open actions'));
    await tester.pumpAndSettle();

    expect(find.text('Multi-select · 3'), findsOneWidget);
    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('Align'), findsNothing);
    expect(find.text('Opacity'), findsNothing);
    expect(find.text('Duplicate'), findsNothing);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Delete'), findsNothing);

    await tester.tap(find.text('Layers'));
    await tester.pump();
    expect(openedLayers, isTrue);
  });

  testWidgets('rename action commits a custom layer name', (tester) async {
    final layer = _shape('shape-1');
    final container = _containerWith([layer]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, layer));
    await tester.tap(find.text('Open actions'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hero card');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final updated = container
        .read(documentControllerProvider)
        .layerById('shape-1');
    expect(updated!.name, 'Hero card');
  });

  testWidgets('layer order actions still reorder the selected layer', (
    tester,
  ) async {
    final bottom = _shape('bottom');
    final top = _shape('top');
    final container = _containerWith([bottom, top]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, bottom));
    await tester.tap(find.text('Open actions'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bring forward'));
    await tester.pumpAndSettle();

    expect(container.read(documentControllerProvider).layers.map((l) => l.id), [
      'top',
      'bottom',
    ]);
  });
}
