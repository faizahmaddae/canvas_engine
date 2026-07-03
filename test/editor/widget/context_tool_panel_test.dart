import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/context_tool_panel.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ShapeLayer _shape(
  String id,
  Offset position, {
  Size size = const Size(80, 80),
  double opacity = 1,
}) => ShapeLayer(
  id: id,
  transform: LayerTransform(position: position, size: size),
  kind: ShapeKind.rectangle,
  opacity: opacity,
);

ProviderContainer _containerWith(
  List<EditorLayer> layers, {
  List<String> selectedIds = const <String>[],
}) {
  final container = ProviderContainer();
  container
      .read(documentControllerProvider.notifier)
      .newDocument(width: 400, height: 400);
  for (final layer in layers) {
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
  }
  if (selectedIds.length == 1) {
    container
        .read(selectionControllerProvider.notifier)
        .select(selectedIds.single);
  } else if (selectedIds.length > 1) {
    container
        .read(selectionControllerProvider.notifier)
        .selectMany(selectedIds);
  }
  return container;
}

Widget _host(
  ProviderContainer container,
  ContextToolPanel panel,
  List<EditorLayer> layers, {
  Locale locale = const Locale('en'),
  double width = 900,
  double height = 280,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: ContextToolPanelBody(panel: panel, layers: layers),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('compact align panel aligns a single layer to the canvas', (
    tester,
  ) async {
    final layer = _shape('shape-1', const Offset(20, 30));
    final container = _containerWith([layer], selectedIds: [layer.id]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, ContextToolPanel.align, [layer]));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('Align right'));
    await tester.pumpAndSettle();

    final updated = container
        .read(documentControllerProvider)
        .layerById('shape-1');
    expect(updated!.transform.position.dx, 320);
    expect(updated.transform.position.dy, 30);
  });

  testWidgets('Persian align panel groups short RTL labels', (tester) async {
    final a = _shape('a', const Offset(20, 20));
    final b = _shape('b', const Offset(140, 20));
    final c = _shape('c', const Offset(260, 20));
    final container = _containerWith([a, b, c], selectedIds: ['a', 'b', 'c']);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(
        container,
        ContextToolPanel.align,
        [a, b, c],
        locale: const Locale('fa'),
        width: 360,
        height: 300,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('تراز لایه‌ها'), findsOneWidget);
    expect(find.text('تراز افقی'), findsOneWidget);
    expect(find.text('تراز عمودی'), findsOneWidget);
    expect(find.text('توزیع'), findsOneWidget);
    expect(find.text('چپ'), findsOneWidget);
    expect(find.text('مرکز'), findsOneWidget);
    expect(find.text('راست'), findsOneWidget);
    expect(find.text('افقی'), findsOneWidget);
    expect(find.text('عمودی'), findsOneWidget);
    expect(find.text('Align right'), findsNothing);
    expect(find.text('Horizontal align'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact opacity panel commits shared multi-layer opacity', (
    tester,
  ) async {
    final a = _shape('a', const Offset(20, 20), opacity: 1);
    final b = _shape('b', const Offset(140, 20), opacity: 0.5);
    final container = _containerWith([a, b], selectedIds: ['a', 'b']);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, ContextToolPanel.opacity, [a, b]));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(0.35);
    slider.onChangeEnd!(0.35);
    await tester.pump();

    final doc = container.read(documentControllerProvider);
    expect(doc.layerById('a')!.opacity, closeTo(0.35, 1e-6));
    expect(doc.layerById('b')!.opacity, closeTo(0.35, 1e-6));
  });

  testWidgets('Persian opacity panel uses compact localized chrome', (
    tester,
  ) async {
    final layer = _shape('shape-1', const Offset(20, 30), opacity: 0.7);
    final container = _containerWith([layer], selectedIds: [layer.id]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(
        container,
        ContextToolPanel.opacity,
        [layer],
        locale: const Locale('fa'),
        width: 360,
        height: 240,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('شفافیت'), findsOneWidget);
    expect(find.text('Opacity'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
