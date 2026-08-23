import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/multi_select_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/text/presentation/text_studio_bench.dart';
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
    'text studio bench surfaces Persian labels and the identity row',
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
          const SizedBox(width: 560, height: 124, child: TextStudioBench()),
        ),
      );
      await tester.pumpAndSettle();

      // Aspect row: three wide Persian chips, no English fallbacks.
      expect(find.text('سبک'), findsOneWidget);
      expect(find.text('چیدمان'), findsOneWidget);
      expect(find.text('بیشتر'), findsOneWidget);
      expect(find.text('More actions'), findsNothing);
      expect(find.text('More'), findsNothing);
      expect(find.text('Layout'), findsNothing);
      // Identity row: specimen + font pill + size pill + ink dot —
      // the six anonymous tiles are gone.
      expect(find.byKey(const ValueKey('text-specimen')), findsOneWidget);
      expect(find.byKey(const ValueKey('text-pill-font')), findsOneWidget);
      expect(find.byKey(const ValueKey('text-pill-size')), findsOneWidget);
      expect(find.byKey(const ValueKey('text-ink-dot')), findsOneWidget);
      // Touch floors: every bench tap target meets the 44dp rule.
      // The aspect segments must STRETCH to the track height — the
      // first bench let them collapse to their 18dp intrinsic row
      // and shipped chips too thin to touch.
      for (final k in const [
        'text-aspect-look',
        'text-aspect-layout',
        'text-aspect-more',
        'text-ink-dot',
        'text-specimen',
      ]) {
        expect(
          tester.getSize(find.byKey(ValueKey(k))).height,
          greaterThanOrEqualTo(44),
          reason: '$k must meet the 44dp touch floor',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
