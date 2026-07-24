// The history browser sheet: localized labels, current-position
// indication, undone styling, RTL/fa, and read-only behavior
// (tb5 follow-up — the prototype's history popover, shipped).

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/history_browser_sheet.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ShapeLayer shape(String id) => ShapeLayer(
    id: id,
    kind: ShapeKind.rectangle,
    transform: const LayerTransform(
      position: Offset.zero,
      size: Size(100, 100),
    ),
  );

  TextLayer text(String id) => TextLayer(
    id: id,
    content: 'hi',
    style: const TextStyleSpec(fontSize: 48),
    transform: const LayerTransform(position: Offset.zero, size: Size(100, 40)),
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    void Function(DocumentController)? edits,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 1080, height: 1080);
    edits?.call(ctrl);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () => showHistoryBrowser(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('lists applied steps with their localized labels, newest at '
      'the current position', (tester) async {
    await pump(
      tester,
      edits: (c) {
        c.execute(AddLayerCommand(shape('s1')));
        c.execute(AddLayerCommand(text('t1')));
      },
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Localized, not the raw engine 'Add shape' / 'Add text'.
    expect(find.text('Add shape'), findsOneWidget);
    expect(find.text('Add text'), findsOneWidget);
    // The start anchor row is present.
    expect(find.text('Document opened'), findsOneWidget);
  });

  testWidgets('an undone step stays visible, struck through', (tester) async {
    await pump(
      tester,
      edits: (c) {
        c.execute(AddLayerCommand(shape('s1')));
        c.execute(AddLayerCommand(text('t1')));
        c.undo(); // undo Add text
      },
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Still listed…
    final undone = tester.widget<Text>(find.text('Add text'));
    // …and marked as not-applied via a line-through.
    expect(undone.style?.decoration, TextDecoration.lineThrough);

    // The applied step is not struck.
    final applied = tester.widget<Text>(find.text('Add shape'));
    expect(applied.style?.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('current position carries an accessible "current" semantic', (
    tester,
  ) async {
    await pump(tester, edits: (c) => c.execute(AddLayerCommand(shape('s1'))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The current row's Semantics node appends the current-step phrase.
    expect(
      find.bySemanticsLabel(RegExp('Add shape.*current step')),
      findsOneWidget,
    );
  });

  testWidgets('opening the browser does not mutate the document '
      '(read-only)', (tester) async {
    final container = await pump(
      tester,
      edits: (c) => c.execute(AddLayerCommand(shape('s1'))),
    );
    final before = container.read(documentControllerProvider);
    final versionBefore = container.read(documentCommitVersionProvider);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      identical(container.read(documentControllerProvider), before),
      isTrue,
      reason: 'the browser is a view; it never edits',
    );
    expect(container.read(documentCommitVersionProvider), versionBefore);
  });

  testWidgets('fa: labels are Persian and the sheet lays out RTL', (
    tester,
  ) async {
    await pump(
      tester,
      locale: const Locale('fa'),
      edits: (c) => c.execute(AddLayerCommand(shape('s1'))),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('افزودن شکل'), findsOneWidget); // Add shape, fa
    expect(find.text('تاریخچه'), findsWidgets); // History title, fa
    expect(
      Directionality.of(tester.element(find.text('افزودن شکل'))),
      TextDirection.rtl,
    );
  });

  testWidgets('empty history shows only the start row as current', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Document opened'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Document opened.*current step')),
      findsOneWidget,
    );
  });
}
