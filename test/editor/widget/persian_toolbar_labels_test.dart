import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/multi_select_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/text/presentation/text_mode_toolbar.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget localizedHost(ProviderContainer container, Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('multi-select toolbar uses short Persian labels', (tester) async {
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const transform = LayerTransform(
      position: Offset(20, 20),
      size: Size(100, 100),
    );
    const a = ShapeLayer(
      id: 'a',
      transform: transform,
      kind: ShapeKind.rectangle,
    );
    const b = ShapeLayer(
      id: 'b',
      transform: transform,
      kind: ShapeKind.rectangle,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      localizedHost(
        container,
        const SizedBox(
          width: 520,
          height: 120,
          child: MultiSelectModeToolbar(layers: [a, b]),
        ),
      ),
    );

    expect(find.text('تراز'), findsOneWidget);
    expect(find.text('شفافیت'), findsOneWidget);
    expect(find.text('لایه‌ها'), findsOneWidget);
    expect(find.text('بیشتر'), findsOneWidget);
    expect(find.text('هم‌تراز کردن'), findsNothing);
    expect(find.text('More actions'), findsNothing);
    expect(find.text('More'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'text toolbar surfaces Persian Font Size Color Style Align More',
    (tester) async {
      tester.view.physicalSize = const Size(560, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const layer = TextLayer(
        id: 'text-1',
        transform: LayerTransform(
          position: Offset(40, 40),
          size: Size(220, 80),
        ),
        content: 'سلام',
        style: TextStyleSpec(fontSize: 32),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: 800, height: 800);
      container
          .read(documentControllerProvider.notifier)
          .execute(const AddLayerCommand(layer));
      container.read(selectionControllerProvider.notifier).select(layer.id);

      await tester.pumpWidget(
        localizedHost(
          container,
          const SizedBox(width: 560, height: 120, child: TextModeToolbar()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('فونت'), findsOneWidget);
      expect(find.text('اندازه'), findsOneWidget);
      expect(find.text('رنگ'), findsOneWidget);
      expect(find.text('استایل'), findsOneWidget);
      expect(find.text('تراز'), findsOneWidget);
      expect(find.text('بیشتر'), findsOneWidget);
      expect(find.text('چیدمان'), findsNothing);
      expect(find.text('More actions'), findsNothing);
      expect(find.text('More'), findsNothing);
      // Bar consolidation (2026-07): decoration tiles are gone from
      // the bar — سایه/زمینه route through استایل's effect chips,
      // کادر is the خط دور chip, تغییر اندازه lives under بیشتر.
      // The strip is exactly these six tiles and never scrolls.
      expect(find.text('سایه'), findsNothing);
      expect(find.text('زمینه'), findsNothing);
      expect(find.text('پس‌زمینه'), findsNothing);
      expect(find.text('کادر'), findsNothing);
      expect(find.text('تغییر اندازه'), findsNothing);
      expect(find.byType(DockToolTile), findsNWidgets(6));
      final strip = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TextModeToolbar),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        strip.position.maxScrollExtent,
        0,
        reason: 'the consolidated 6-tile bar must not scroll',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
