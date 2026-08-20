import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/paint/presentation/bodies/paint_shape_body.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_bench.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The bench and its sheets must stay semantic (buttons with real
// labels and selection state) and Persian-safe under large
// accessibility text on a small phone — the combination that
// historically broke the old tool catalogue's fixed grid cells.
void main() {
  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    required Widget child,
  }) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2.5),
            ),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('the rack is selected, semantic, and Persian-safe', (
    tester,
  ) async {
    await pumpHost(
      tester,
      child: const SizedBox(height: 130, child: PaintBench()),
    );

    expect(find.bySemanticsLabel('قلم'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('قلم')),
      matchesSemantics(
        label: 'قلم',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(find.bySemanticsLabel('انتخاب'), findsOneWidget);
    expect(find.bySemanticsLabel('پاک‌کن'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shape sheet\'s kind cards stay labelled and safe', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpHost(
      tester,
      child: SingleChildScrollView(
        child: Consumer(
          builder: (context, ref, _) =>
              PaintShapeBody(view: ref.watch(paintStyleViewProvider)),
        ),
      ),
    );

    expect(find.bySemanticsLabel('مربع'), findsOneWidget);
    expect(find.bySemanticsLabel('چندضلعی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
