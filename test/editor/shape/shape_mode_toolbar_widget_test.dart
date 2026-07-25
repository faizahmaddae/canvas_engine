import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/shape/application/shape_tool_controller.dart';
import 'package:canvas_engine/features/editor/shape/presentation/shape_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/shape/presentation/shape_style_body.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

/// Widget-level coverage for the Shape sub-tool surface:
///   * Shape toolbar renders Style / Border / Shadow / Opacity / Replace / More tabs.
///   * Tapping Shadow opens the `shadow` slot.
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

  testWidgets(
    'ShapeModeToolbar shows Style Border Shadow Opacity Replace More',
    (tester) async {
      final layer = makeLayer();
      final container = makeContainer(layer);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 120,
                child: ShapeModeToolbar(layer: layer, onReplaceTap: () {}),
              ),
            ),
          ),
        ),
      );

      // Slot strip enters compact mode in landscape (test default), which
      // hides static labels — finding by icon is the stable signal that
      // each tab is mounted.
      expect(find.byIcon(AppIcons.colorTool), findsOneWidget);
      expect(find.byIcon(AppIcons.borderTool), findsOneWidget);
      // Shadow has its own glyph now. It used to borrow the BLUR
      // icon here and the LAYERS icon on the image toolbar — one tool
      // drawn three different ways, and one of those ways identical to
      // the layers-drawer button sitting beside it.
      expect(find.byIcon(AppIcons.shadowTool), findsOneWidget);
      expect(find.byIcon(AppIcons.opacity), findsOneWidget);
      expect(find.byIcon(AppIcons.replace), findsOneWidget);
      expect(find.byIcon(AppIcons.moreActions), findsOneWidget);
    },
  );

  testWidgets('Tapping Shadow tab opens the shadow slot', (tester) async {
    final layer = makeLayer();
    final container = makeContainer(layer);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 120,
              child: ShapeModeToolbar(layer: layer, onReplaceTap: () {}),
            ),
          ),
        ),
      ),
    );

    expect(container.read(shapeToolControllerProvider).openSlot, isNull);

    final shadowFinder = find.byIcon(AppIcons.shadowTool);
    await tester.scrollUntilVisible(shadowFinder, 80);
    await tester.tap(shadowFinder);
    await tester.pump();

    expect(
      container.read(shapeToolControllerProvider).openSlot,
      ShapeToolSlot.shadow,
    );
  });

  testWidgets('ShapeModeToolbar uses short Persian primary labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final layer = makeLayer();
    final container = makeContainer(layer);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 120,
              child: ShapeModeToolbar(layer: layer, onReplaceTap: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('رنگ'), findsOneWidget);
    expect(find.text('کادر'), findsOneWidget);
    expect(find.text('سایه'), findsOneWidget);
    expect(find.text('شفافیت'), findsOneWidget);
    expect(find.text('بیشتر'), findsOneWidget);
    expect(find.text('جایگزینی'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tapping Opacity tab opens compact context panel state', (
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
              height: 120,
              child: ShapeModeToolbar(layer: layer, onReplaceTap: () {}),
            ),
          ),
        ),
      ),
    );

    final opacityFinder = find.byIcon(AppIcons.opacity);
    await tester.scrollUntilVisible(opacityFinder, 80);
    await tester.tap(opacityFinder);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      container.read(contextToolbarControllerProvider),
      ContextToolPanel.opacity,
    );
    expect(container.read(shapeToolControllerProvider).openSlot, isNull);
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

    expect(find.text('Color'), findsOneWidget);
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
