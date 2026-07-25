// Host contract for the single editor modal sheet (tb2 8/16,
// interaction contract §1-M/§9): barrier mapping (none/whisper/full),
// the ≥44dp handle dismiss zone (0563102's hit floor), and
// keyboard-aware placement for text-entry content.

import 'package:canvas_engine/features/editor/presentation/widgets/editor_modal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

void main() {
  Future<BuildContext> pumpHostApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    late BuildContext hostCtx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              hostCtx = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return hostCtx;
  }

  Color? barrierColorOf(WidgetTester tester) =>
      tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last.color;

  testWidgets('barrier mapping: none → fully transparent', (tester) async {
    final ctx = await pumpHostApp(tester);
    showEditorSheet<void>(
      ctx,
      barrier: EditorSheetBarrier.none,
      builder: (_) => const SizedBox(height: 120),
    );
    await tester.pumpAndSettle();
    // A fully-transparent barrier surfaces as either an explicit
    // transparent color or a color-less ModalBarrier.
    final color = barrierColorOf(tester);
    expect(color == null || color.a == 0, isTrue);
  });

  testWidgets('barrier mapping: whisper → 6% scrim', (tester) async {
    final ctx = await pumpHostApp(tester);
    showEditorSheet<void>(
      ctx,
      barrier: EditorSheetBarrier.whisper,
      builder: (_) => const SizedBox(height: 120),
    );
    await tester.pumpAndSettle();
    final color = barrierColorOf(tester)!;
    expect(color.a, closeTo(kEditorSheetWhisperAlpha, 0.005));
  });

  testWidgets('barrier mapping: full → the framework default scrim', (
    tester,
  ) async {
    final ctx = await pumpHostApp(tester);
    showEditorSheet<void>(
      ctx,
      // full is the default.
      builder: (_) => const SizedBox(height: 120),
    );
    await tester.pumpAndSettle();
    final color = barrierColorOf(tester)!;
    expect(
      color.a,
      greaterThan(0.3),
      reason: 'full barrier keeps a real scrim (framework default)',
    );
  });

  testWidgets('handle zone is ≥44dp tall and tap-dismisses with null', (
    tester,
  ) async {
    final ctx = await pumpHostApp(tester);
    Object? result = 'sentinel';
    showEditorSheet<String>(
      ctx,
      builder: (_) => const SizedBox(height: 120),
    ).then((v) => result = v);
    await tester.pumpAndSettle();

    final zone = find.byKey(const ValueKey('editor-sheet-handle-zone'));
    expect(zone, findsOneWidget);
    expect(
      tester.getSize(zone).height,
      greaterThanOrEqualTo(44.0),
      reason: 'chrome hit floor (tb2 14/16)',
    );

    await tester.tap(zone);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-sheet-handle-zone')),
      findsNothing,
    );
    expect(result, isNull, reason: 'handle dismiss resolves like any dismiss');
  });

  testWidgets('optional title row renders title + icon', (tester) async {
    final ctx = await pumpHostApp(tester);
    showEditorSheet<void>(
      ctx,
      title: 'Sheet title',
      titleIcon: AppIcons.precisionAdjust,
      builder: (_) => const SizedBox(height: 60),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sheet title'), findsOneWidget);
    expect(find.byIcon(AppIcons.precisionAdjust), findsOneWidget);
  });

  testWidgets('keyboardAware lifts the card above the view insets', (
    tester,
  ) async {
    final ctx = await pumpHostApp(tester);
    const contentKey = ValueKey('sheet-content');
    showEditorSheet<void>(
      ctx,
      keyboardAware: true,
      builder: (_) => const SizedBox(key: contentKey, height: 120),
    );
    await tester.pumpAndSettle();
    final bottomBefore = tester.getBottomLeft(find.byKey(contentKey)).dy;

    // Fake IME: 240 physical px at DPR 1.0.
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    final bottomAfter = tester.getBottomLeft(find.byKey(contentKey)).dy;

    expect(
      bottomAfter,
      lessThanOrEqualTo(956.0 - 240.0),
      reason: 'content must sit fully above the keyboard',
    );
    expect(bottomAfter, lessThan(bottomBefore));
  });
}
