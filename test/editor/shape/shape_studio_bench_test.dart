import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:canvas_engine/features/editor/shape/presentation/shape_studio_bench.dart';
import 'package:canvas_engine/features/editor/shape/presentation/shape_style_body.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget-level coverage for the Shape Studio bench
/// (docs/shape-studio-redesign-2026-08.md §4):
///   * identity row renders the specimen (kind name) and the two
///     fact-cluster zones; aspect row renders رنگ/کادر/سایه/بیشتر.
///   * the سایه segment opens the `shadow` slot; the opacity zone
///     opens the shared context panel and closes any dock panel.
///   * the size zone toggles the resize mode with one undoable
///     command.
///   * Style panel labels its colour section "Color" for line /
///     arrow (stroked kinds) and "Fill" otherwise.
void main() {
  ShapeLayer makeLayer({
    String id = 'shape1',
    ShapeKind kind = ShapeKind.rectangle,
  }) {
    return ShapeLayer(
      id: id,
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(200, 200),
      ),
      kind: kind,
    );
  }

  ProviderContainer makeContainer(ShapeLayer layer) {
    final c = ProviderContainer();
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pumpBench(
    WidgetTester tester,
    ProviderContainer container,
    ShapeLayer layer, {
    Locale locale = const Locale('en'),
    VoidCallback? onReplaceTap,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 124,
              child: ShapeStudioBench(
                layer: layer,
                onReplaceTap: onReplaceTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('bench renders specimen, fact cluster and aspect track', (
    tester,
  ) async {
    final layer = makeLayer();
    final container = makeContainer(layer);
    await pumpBench(tester, container, layer);

    expect(find.byKey(const ValueKey('shape-studio-bench')), findsOneWidget);
    expect(find.byKey(const ValueKey('shape-specimen')), findsOneWidget);
    // The specimen names the kind — the picture plus its noun.
    expect(find.text('Rectangle'), findsOneWidget);
    expect(find.byKey(const ValueKey('shape-pill-size')), findsOneWidget);
    expect(find.byKey(const ValueKey('shape-pill-opacity')), findsOneWidget);
    expect(find.byKey(const ValueKey('shape-aspect-style')), findsOneWidget);
    expect(find.byKey(const ValueKey('shape-aspect-border')), findsOneWidget);
    expect(find.byKey(const ValueKey('shape-aspect-shadow')), findsOneWidget);
    expect(find.byKey(const ValueKey('shape-aspect-more')), findsOneWidget);
  });

  testWidgets('specimen tap fires the Replace door', (tester) async {
    final layer = makeLayer();
    final container = makeContainer(layer);
    var replaceTaps = 0;
    await pumpBench(
      tester,
      container,
      layer,
      onReplaceTap: () => replaceTaps++,
    );

    await tester.tap(find.byKey(const ValueKey('shape-specimen')));
    await tester.pump();

    expect(replaceTaps, 1);
  });

  testWidgets('the سایه segment opens the shadow slot', (tester) async {
    final layer = makeLayer();
    final container = makeContainer(layer);
    await pumpBench(tester, container, layer);

    expect(container.read(shapeToolControllerProvider).openSlot, isNull);

    await tester.tap(find.byKey(const ValueKey('shape-aspect-shadow')));
    await tester.pump();

    expect(
      container.read(shapeToolControllerProvider).openSlot,
      ShapeToolSlot.shadow,
    );
  });

  testWidgets('bench uses short Persian labels — no شفافیت chip', (
    tester,
  ) async {
    final layer = makeLayer();
    final container = makeContainer(layer);
    await pumpBench(tester, container, layer, locale: const Locale('fa'));

    expect(find.text('رنگ'), findsOneWidget);
    expect(find.text('کادر'), findsOneWidget);
    expect(find.text('سایه'), findsOneWidget);
    expect(find.text('بیشتر'), findsOneWidget);
    // Opacity is the fact cluster's percentage now, not a labelled
    // chip; Replace is the specimen chip, not a labelled chip.
    expect(find.text('شفافیت'), findsNothing);
    expect(find.text('جایگزینی'), findsNothing);
    expect(find.text('۱۰۰٪'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the opacity zone opens the context panel, closes the slot', (
    tester,
  ) async {
    final layer = makeLayer();
    final container = makeContainer(layer);
    await pumpBench(tester, container, layer);

    container
        .read(shapeToolControllerProvider.notifier)
        .toggleSlot(ShapeToolSlot.style);
    await tester.tap(find.byKey(const ValueKey('shape-pill-opacity')));
    await tester.pump();

    expect(
      container.read(contextToolbarControllerProvider),
      ContextToolPanel.opacity,
    );
    expect(container.read(shapeToolControllerProvider).openSlot, isNull);
  });

  testWidgets('the size zone toggles resize mode with one undo entry', (
    tester,
  ) async {
    // A rectangle defaults to free resize; the size-zone tap flips it
    // to scale (aspect-locked) — the toggle that decides what
    // corner-drag does to the numbers the zone shows.
    final layer = makeLayer();
    final container = makeContainer(layer);
    // setResizeMode resolves the layer through the SELECTION, the
    // same way the floating toolbar does.
    container.read(selectionControllerProvider.notifier).select(layer.id);
    await pumpBench(tester, container, layer);

    ShapeLayer current() =>
        container.read(documentControllerProvider).layerById(layer.id)!
            as ShapeLayer;
    expect(current().effectiveResizeMode, ShapeResizeMode.free);

    await tester.tap(find.byKey(const ValueKey('shape-pill-size')));
    await tester.pump();

    expect(current().effectiveResizeMode, ShapeResizeMode.scale);

    container.read(documentControllerProvider.notifier).undo();
    expect(current().effectiveResizeMode, ShapeResizeMode.free);
  });

  testWidgets('ShapeStyleBody labels colour section "Color" for line', (
    tester,
  ) async {
    final layer = makeLayer(kind: ShapeKind.line);
    final container = makeContainer(layer);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ShapeStyleBody(layer: layer),
            ),
          ),
        ),
      ),
    );

    // Two 'Color's: the panel header (the door's name — رنگ) and the
    // stroked-kind section label.
    expect(find.text('Color'), findsNWidgets(2));
    expect(find.text('Fill'), findsNothing);
  });

  testWidgets('ShapeStyleBody labels colour section "Fill" for rectangle', (
    tester,
  ) async {
    final layer = makeLayer();
    final container = makeContainer(layer);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ShapeStyleBody(layer: layer),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Fill'), findsOneWidget);
  });
}
