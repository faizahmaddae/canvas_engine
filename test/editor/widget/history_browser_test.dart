// The history browser sheet: localized labels, current-position
// indication, undone styling, RTL/fa, and read-only behavior
// (tb5 follow-up — the prototype's history popover, shipped).

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/history_browser_sheet.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/history_labels.dart';
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

  group('label map exhaustiveness (audit P3-3)', () {
    // Every English raw label the engine and application layers can
    // emit into history. Sources: `String get label` across
    // engine/commands/*.dart, plus every English `labelOverride` site
    // (crop composite, gesture-batch bases, align/distribute, eraser
    // sweep). Presentation-authored overrides that arrive ALREADY
    // localized (e.g. removeBasePhotoCommand) are exempt by design —
    // they fall through the map unchanged. A new engine label added
    // without a map case fails here, in English, before a Persian
    // user ever sees it.
    const raws = <String>[
      'Add text',
      'Add image',
      'Add shape',
      'Add paint',
      'Add sticker',
      'Composite (3)',
      'Delete layer',
      'Remove layer',
      'Rename layer',
      'Reorder layer',
      'Set layer opacity',
      'Lock layer',
      'Unlock layer',
      'Show layer',
      'Hide layer',
      'Move',
      'Resize',
      'Rotate',
      'Transform',
      'Transform layer',
      'Flip horizontally',
      'Flip vertically',
      'Canvas background',
      'Canvas background mode',
      'Resize canvas',
      'Edit text',
      'Text direction',
      'Text resize mode',
      'Image adjustments',
      'Image border',
      'Image crop',
      'Image filter',
      'Image fit',
      'Image shadow',
      'Image shape',
      'Replace image',
      'Restore image',
      'Paint style',
      'Paint resize behavior',
      'Shape fill',
      'Shape stroke',
      'Shape radius',
      'Shape shadow',
      'Shape resize mode',
      'Replace shape',
      'Vignette',
      'Delete effect',
      'Reorder effect',
      'Restore effect',
      'Toggle effect',
      'Set base photo',
      'Clear base photo',
      'Photo project',
      'Design project',
      'Crop',
      'Stack mask',
      'Clear stack mask',
      'Align left',
      'Align center horizontally',
      'Align right',
      'Align top',
      'Align center vertically',
      'Align bottom',
      'Distribute horizontally',
      'Distribute vertically',
      'Align left 3 layers',
      'Move 2 layers',
      'Resize 4 layers',
      'Rotate 2 layers',
      'Transform 5 layers',
      'Distribute vertically 3 layers',
    ];

    test('every raw label localizes under fa — no English leaks', () {
      final fa = lookupAppLocalizations(const Locale('fa'));
      for (final raw in raws) {
        final out = localizedHistoryLabel(fa, raw);
        expect(
          out,
          isNot(raw),
          reason: '"$raw" fell through the map to raw English',
        );
        expect(out, isNotEmpty);
      }
    });

    test('batch labels compose the localized base with locale digits', () {
      final fa = lookupAppLocalizations(const Locale('fa'));
      final out = localizedHistoryLabel(
        fa,
        'Align left 3 layers',
        formatCount: (n) => const ['۰', '۱', '۲', '۳'][n],
      );
      expect(out, 'تراز چپ · ۳ لایه');
    });
  });
}
