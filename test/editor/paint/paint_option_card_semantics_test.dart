import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/paint/presentation/bodies/paint_tool_body.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tool catalogue is selected, semantic, and Persian-safe', (
    tester,
  ) async {
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
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2.5),
            ),
            child: Scaffold(body: PaintToolBody()),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('قلم'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('قلم')),
      matchesSemantics(
        label: 'قلم',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('شکل‌ها'));
    await tester.pump();

    expect(find.bySemanticsLabel('مربع'), findsOneWidget);
    expect(find.bySemanticsLabel('چندضلعی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
