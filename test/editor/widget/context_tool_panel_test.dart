import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/context_tool_panel.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/widgets/preset_chip.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ShapeLayer _shape(
  String id,
  Offset position, {
  Size size = const Size(80, 80),
  double opacity = 1,
  bool locked = false,
}) => ShapeLayer(
  id: id,
  transform: LayerTransform(position: position, size: size),
  kind: ShapeKind.rectangle,
  opacity: opacity,
  locked: locked,
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

  // Audit P2-7: the panel used to open with live-looking tiles for a
  // locked layer and silently no-op every tap. The tiles must render
  // from the SAME eligibility rule the controller refuses by
  // (contract §10.3: unavailable, never present-inert-and-silent).
  testWidgets('locked layer: every align tile disabled, taps commit nothing', (
    tester,
  ) async {
    final layer = _shape('frozen', const Offset(20, 30), locked: true);
    final container = _containerWith([layer], selectedIds: [layer.id]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, ContextToolPanel.align, [layer]));
    await tester.pumpAndSettle();

    for (final label in [
      'Align left',
      'Align center',
      'Align right',
      'Align top',
      'Align middle',
      'Align bottom',
    ]) {
      final chip = tester.widget<PresetChip>(
        find.widgetWithText(PresetChip, label),
      );
      expect(chip.enabled, isFalse, reason: '$label must render disabled');
    }

    await tester.tap(find.text('Align right'));
    await tester.pumpAndSettle();

    final updated = container
        .read(documentControllerProvider)
        .layerById('frozen');
    expect(updated!.transform.position.dx, 20);
    expect(updated.transform.position.dy, 30);
  });

  testWidgets('mixed group: align tiles live and move only eligible members, '
      'distribute tiles disabled below three eligible', (tester) async {
    final a = _shape('a', const Offset(20, 20));
    final b = _shape('b', const Offset(140, 20));
    final frozen = _shape('frozen', const Offset(260, 20), locked: true);
    final container = _containerWith(
      [a, b, frozen],
      selectedIds: ['a', 'b', 'frozen'],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(container, ContextToolPanel.align, [a, b, frozen]),
    );
    await tester.pumpAndSettle();

    // Two of three members are movable: align qualifies (`>= 2`),
    // distribute does not (`>= 3`) — the tile gates must agree with
    // the controller's own bails, the audit's exact drift complaint.
    final alignChip = tester.widget<PresetChip>(
      find.widgetWithText(PresetChip, 'Align left'),
    );
    expect(alignChip.enabled, isTrue);
    for (final label in ['Horizontal', 'Vertical']) {
      final chip = tester.widget<PresetChip>(
        find.widgetWithText(PresetChip, label),
      );
      expect(chip.enabled, isFalse, reason: '$label must render disabled');
    }

    await tester.tap(find.text('Align left'));
    await tester.pumpAndSettle();

    final doc = container.read(documentControllerProvider);
    expect(doc.layerById('a')!.transform.position.dx, 20);
    expect(doc.layerById('b')!.transform.position.dx, 20);
    expect(
      doc.layerById('frozen')!.transform.position.dx,
      260,
      reason: 'locked member never moves',
    );

    // The distribute section can sit below the panel's clamped fold —
    // scroll it into view before tapping (chrome scrolls internally).
    await tester.ensureVisible(find.text('Horizontal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Horizontal'));
    await tester.pumpAndSettle();

    final after = container.read(documentControllerProvider);
    expect(after.layerById('a')!.transform.position.dx, 20);
    expect(after.layerById('b')!.transform.position.dx, 20);
    expect(after.layerById('frozen')!.transform.position.dx, 260);
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
