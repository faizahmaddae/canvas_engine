// Behavioral net for THE unified layer overflow sheet (tb2 7/16 —
// one capability-driven sheet replaces the three drifted copies:
// layer_actions_sheet / selected_layer_actions_sheet /
// panels/text/more_sheet; their pins migrated here). Pins: the
// canonical row ORDER (once, on the fullest — text — row set), the
// per-type capability matrix (text/shape/paint/image + multi), the
// Align/Opacity context-panel routing, delete clearing the
// selection, and the multi batch guarantees that closed the
// "multi-select has no batch actions" audit finding — batch delete
// is ONE undo entry, batch duplicate selects the clones, batch lock
// is one composite.

import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layer_overflow_sheet.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

ShapeLayer _shape(String id, {bool locked = false}) => ShapeLayer(
  id: id,
  transform: const LayerTransform(
    position: Offset(40, 40),
    size: Size(120, 80),
  ),
  kind: ShapeKind.rectangle,
  locked: locked,
);

TextLayer _text(String id) => TextLayer(
  id: id,
  transform: const LayerTransform(
    position: Offset(100, 100),
    size: Size(160, 80),
  ),
  content: 'Hello سلام',
  style: const TextStyleSpec(fontSize: 24),
  textDirectionMode: TextDirectionMode.rtl,
);

PaintLayer _paint(String id) => PaintLayer(
  id: id,
  transform: const LayerTransform(
    position: Offset(60, 60),
    size: Size(200, 120),
  ),
  kind: PaintKind.freestyle,
  normalizedPoints: const [Offset(0, 0), Offset(0.5, 0.5), Offset(1, 1)],
);

ImageLayer _image(String id) => ImageLayer(
  id: id,
  transform: const LayerTransform(
    position: Offset(20, 20),
    size: Size(300, 200),
  ),
  source: const ImageSource.file('/nonexistent.png'),
);

ProviderContainer _containerWith(List<EditorLayer> layers) {
  final container = ProviderContainer();
  container
      .read(documentControllerProvider.notifier)
      .newDocument(width: 400, height: 400);
  for (final layer in layers) {
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
  }
  return container;
}

Widget _host(
  ProviderContainer container,
  EditorLayer layer, {
  List<EditorLayer>? selectedLayers,
  VoidCallback? onOpenLayers,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => FilledButton(
              onPressed: () => showLayerOverflowSheet(
                context,
                ref,
                layer: layer,
                selectedLayers: selectedLayers,
                onOpenLayers: onOpenLayers,
              ),
              child: const Text('Open actions'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open actions'));
  await tester.pumpAndSettle();
}

/// Scrolls a row into the sheet's clamped viewport before tapping —
/// the union list is taller than the modal sheet on the test surface.
Future<void> _tapRow(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  testWidgets('text layer: full row set present, canonical order pinned', (
    tester,
  ) async {
    final layer = _text('text-1');
    final container = _containerWith([layer]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, layer));
    await _open(tester);

    // Canonical order (tb2 7/16): the y-position of each row must be
    // strictly increasing through the full union list. Pinned ONCE,
    // here, on the fullest (text) variant.
    final orderedFinders = <Finder>[
      find.text('Edit text'),
      find.text('Align'),
      find.text('Opacity'),
      find.text('Rename'),
      find.text('Duplicate'),
      find.text('Bring forward'),
      find.text('Send backward'),
      find.text('Lock layer'),
      find.text('Resize behavior'),
      find.text('Text direction'),
      find.text('Delete'),
    ];
    double? prevY;
    for (final finder in orderedFinders) {
      expect(finder, findsOneWidget, reason: 'missing row: $finder');
      final y = tester.getCenter(finder).dy;
      if (prevY != null) {
        expect(
          y,
          greaterThan(prevY),
          reason: 'row out of canonical order: $finder',
        );
      }
      prevY = y;
    }
    // No Layers row: this host passed no onOpenLayers callback.
    expect(find.text('Layers'), findsNothing);
    // No B/I/U row: live document-mutating toggles moved to the
    // استایل dock panel where the canvas is visible (audit P3-2) —
    // every row left in this sheet pops-then-acts.
    expect(find.byIcon(AppIcons.bold), findsNothing);
    // Direction subtitle reflects the layer's current mode.
    expect(find.text('Right to left'), findsOneWidget);
  });

  testWidgets('shape layer: text rows hidden, resize row is a live toggle', (
    tester,
  ) async {
    final layer = _shape('shape-1');
    final container = _containerWith([layer]);
    addTearDown(container.dispose);
    // The shape controller applies resize-mode writes to the SELECTED
    // shape layer — select it like the real 'more' entry point does.
    container.read(selectionControllerProvider.notifier).select('shape-1');

    await tester.pumpWidget(_host(container, layer));
    await _open(tester);

    expect(find.text('Edit text'), findsNothing);
    expect(find.text('Text direction'), findsNothing);
    expect(find.byIcon(AppIcons.bold), findsNothing);
    expect(find.text('Align'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
    expect(find.text('Resize behavior'), findsOneWidget);
    // Rectangle defaults to Free; tapping toggles to Scale inline
    // (sheet stays up) and writes through the shape controller.
    expect(find.text('Free'), findsOneWidget);
    await _tapRow(tester, find.text('Resize behavior'));
    await tester.pump();
    expect(find.text('Scale'), findsOneWidget);
    expect(
      find.byType(BottomSheet),
      findsOneWidget,
      reason: 'toggle stays inline',
    );
    final updated =
        container.read(documentControllerProvider).layerById('shape-1')
            as ShapeLayer;
    expect(updated.effectiveResizeMode, ShapeResizeMode.scale);
  });

  testWidgets('paint layer: resize toggle writes through paint controller', (
    tester,
  ) async {
    final layer = _paint('paint-1');
    final container = _containerWith([layer]);
    addTearDown(container.dispose);
    container.read(selectionControllerProvider.notifier).select('paint-1');

    await tester.pumpWidget(_host(container, layer));
    await _open(tester);

    expect(find.text('Resize behavior'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    await _tapRow(tester, find.text('Resize behavior'));
    await tester.pump();
    final updated =
        container.read(documentControllerProvider).layerById('paint-1')
            as PaintLayer;
    expect(updated.resizeMode, PaintResizeMode.scale);
  });

  testWidgets('image layer: structural rows only — no resize/text rows', (
    tester,
  ) async {
    final layer = _image('img-1');
    final container = _containerWith([layer]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, layer, onOpenLayers: () {}));
    await _open(tester);

    expect(find.text('Align'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Bring forward'), findsOneWidget);
    expect(find.text('Send backward'), findsOneWidget);
    expect(find.text('Lock layer'), findsOneWidget);
    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Resize behavior'), findsNothing);
    expect(find.text('Edit text'), findsNothing);
  });

  testWidgets('Align and Opacity route to context panels, sheet dismissed', (
    tester,
  ) async {
    final layer = _text('text-1');
    final container = _containerWith([layer]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, layer));
    await _open(tester);
    await tester.tap(find.text('Align'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      container.read(contextToolbarControllerProvider),
      ContextToolPanel.align,
    );

    await _open(tester);
    await tester.tap(find.text('Opacity'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      container.read(contextToolbarControllerProvider),
      ContextToolPanel.opacity,
    );
  });

  // Audit P2-7: the Align row used to stay live for a locked layer and
  // route to a panel whose every tile silently no-oped. The row must
  // read from the controller's own eligibility rule — the same greyed
  // treatment the base-photo and reorder gates already use.
  testWidgets('locked layer: Align row disabled and routes nowhere', (
    tester,
  ) async {
    final layer = _shape('frozen', locked: true);
    final container = _containerWith([layer]);
    addTearDown(container.dispose);
    container.read(selectionControllerProvider.notifier).select('frozen');

    await tester.pumpWidget(_host(container, layer));
    await _open(tester);

    final row = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Align'));
    expect(row.enabled, isFalse);

    await tester.tap(find.text('Align'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget, reason: 'sheet stays up');
    expect(container.read(contextToolbarControllerProvider), isNull);
  });

  // Lock rule (EditorLayer.locked, audit P3-1): opacity is frozen
  // content, so the row that opens its live panel must grey out for a
  // locked layer — same treatment as the Align row above, gated by
  // the same predicate the slider itself refuses through.
  testWidgets('locked layer: Opacity row disabled and routes nowhere', (
    tester,
  ) async {
    final layer = _shape('frozen', locked: true);
    final container = _containerWith([layer]);
    addTearDown(container.dispose);
    container.read(selectionControllerProvider.notifier).select('frozen');

    await tester.pumpWidget(_host(container, layer));
    await _open(tester);

    final row = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Opacity'),
    );
    expect(row.enabled, isFalse);

    await tester.tap(find.text('Opacity'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget, reason: 'sheet stays up');
    expect(container.read(contextToolbarControllerProvider), isNull);
  });

  // Audit P3-1's exact repro: «قرینه افقی» mutated a locked layer's
  // transform while the canvas refused every other transform. Flip is
  // a content transform — the rows grey out and a tap commits nothing.
  testWidgets('locked layer: flip rows disabled, no history entry', (
    tester,
  ) async {
    final layer = _shape('frozen', locked: true);
    final container = _containerWith([layer]);
    addTearDown(container.dispose);
    container.read(selectionControllerProvider.notifier).select('frozen');
    container.read(documentControllerProvider.notifier).clearHistory();

    await tester.pumpWidget(_host(container, layer));
    await _open(tester);

    for (final label in ['Flip horizontally', 'Flip vertically']) {
      final row = tester.widget<ListTile>(find.widgetWithText(ListTile, label));
      expect(row.enabled, isFalse, reason: '$label must render disabled');
    }

    await _tapRow(tester, find.text('Flip horizontally'));
    await tester.pumpAndSettle();

    final doc = container.read(documentControllerProvider);
    expect(doc.layerById('frozen')!.transform.flipH, isFalse);
    expect(
      container.read(documentControllerProvider.notifier).canUndo,
      isFalse,
      reason: 'a refused flip must not create a history entry',
    );
  });

  testWidgets('rename action commits a custom layer name', (tester) async {
    final layer = _shape('shape-1');
    final container = _containerWith([layer]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, layer));
    await _open(tester);

    await _tapRow(tester, find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hero card');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final updated = container
        .read(documentControllerProvider)
        .layerById('shape-1');
    expect(updated!.name, 'Hero card');
  });

  testWidgets('layer order actions still reorder the selected layer', (
    tester,
  ) async {
    final bottom = _shape('bottom');
    final top = _shape('top');
    final container = _containerWith([bottom, top]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, bottom));
    await _open(tester);

    await _tapRow(tester, find.text('Bring forward'));
    await tester.pumpAndSettle();

    expect(container.read(documentControllerProvider).layers.map((l) => l.id), [
      'top',
      'bottom',
    ]);
  });

  testWidgets('delete removes the layer and clears the selection', (
    tester,
  ) async {
    final layer = _shape('shape-1');
    final container = _containerWith([layer]);
    addTearDown(container.dispose);
    container.read(selectionControllerProvider.notifier).select('shape-1');

    await tester.pumpWidget(_host(container, layer));
    await _open(tester);
    await _tapRow(tester, find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(container.read(documentControllerProvider).layers, isEmpty);
    expect(
      container.read(selectionControllerProvider).hasSelection,
      isFalse,
      reason: 'delete must clear the selection, never promote a sibling',
    );
  });

  group('multi-selection variant', () {
    testWidgets('shows count header, batch rows and Layers link', (
      tester,
    ) async {
      var openedLayers = false;
      final a = _shape('a');
      final b = _shape('b');
      final c = _shape('c');
      final container = _containerWith([a, b, c]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _host(
          container,
          c,
          selectedLayers: [a, b, c],
          onOpenLayers: () => openedLayers = true,
        ),
      );
      await _open(tester);

      expect(find.text('Multi-select · 3'), findsOneWidget);
      expect(find.text('Align'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Lock layer'), findsOneWidget);
      expect(find.text('Layers'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      // Single-layer-only rows never leak into the batch variant.
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Bring forward'), findsNothing);
      expect(find.text('Send backward'), findsNothing);
      expect(find.text('Opacity'), findsNothing);

      await _tapRow(tester, find.text('Layers'));
      await tester.pumpAndSettle();
      expect(openedLayers, isTrue);
    });

    testWidgets('batch delete removes all as ONE undo entry', (tester) async {
      final a = _shape('a');
      final b = _shape('b');
      final c = _shape('c');
      final container = _containerWith([a, b, c]);
      addTearDown(container.dispose);
      container.read(selectionControllerProvider.notifier).selectMany([
        'a',
        'b',
        'c',
      ]);

      await tester.pumpWidget(_host(container, c, selectedLayers: [a, b, c]));
      await _open(tester);
      await _tapRow(tester, find.text('Delete'));
      await tester.pumpAndSettle();

      expect(container.read(documentControllerProvider).layers, isEmpty);
      expect(container.read(selectionControllerProvider).hasSelection, isFalse);

      // ONE undo restores the whole batch — the composite guarantee
      // that closes the multi-select audit finding.
      container.read(documentControllerProvider.notifier).undo();
      expect(
        container.read(documentControllerProvider).layers.map((l) => l.id),
        ['a', 'b', 'c'],
      );
    });

    testWidgets('batch duplicate is one entry and selects the clones', (
      tester,
    ) async {
      final a = _shape('a');
      final b = _shape('b');
      final c = _shape('c');
      final container = _containerWith([a, b, c]);
      addTearDown(container.dispose);
      container.read(selectionControllerProvider.notifier).selectMany([
        'a',
        'b',
        'c',
      ]);

      await tester.pumpWidget(_host(container, c, selectedLayers: [a, b, c]));
      await _open(tester);
      await _tapRow(tester, find.text('Duplicate'));
      await tester.pumpAndSettle();

      final doc = container.read(documentControllerProvider);
      expect(doc.layers, hasLength(6));
      final selection = container.read(selectionControllerProvider);
      expect(selection.selectedIds, hasLength(3));
      expect(
        selection.selectedIds.any({'a', 'b', 'c'}.contains),
        isFalse,
        reason: 'the CLONES become the new selection, not the originals',
      );

      // One undo removes all three clones at once.
      container.read(documentControllerProvider.notifier).undo();
      expect(
        container.read(documentControllerProvider).layers.map((l) => l.id),
        ['a', 'b', 'c'],
      );
    });

    // Audit P2-7: batch Align had no gate at all — an all-locked or
    // effectively-single batch opened six live tiles that did nothing.
    testWidgets('all-locked batch: Align row disabled', (tester) async {
      final a = _shape('a', locked: true);
      final b = _shape('b', locked: true);
      final container = _containerWith([a, b]);
      addTearDown(container.dispose);
      container.read(selectionControllerProvider.notifier).selectMany([
        'a',
        'b',
      ]);

      await tester.pumpWidget(_host(container, b, selectedLayers: [a, b]));
      await _open(tester);

      final row = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Align'),
      );
      expect(row.enabled, isFalse);

      await tester.tap(find.text('Align'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(container.read(contextToolbarControllerProvider), isNull);
    });

    testWidgets('mixed pair with one movable member: Align row disabled', (
      tester,
    ) async {
      // `align()` bails below two ELIGIBLE members, so a pair with one
      // locked layer strands the movable one — the row must say so.
      final a = _shape('a');
      final frozen = _shape('frozen', locked: true);
      final container = _containerWith([a, frozen]);
      addTearDown(container.dispose);
      container.read(selectionControllerProvider.notifier).selectMany([
        'a',
        'frozen',
      ]);

      await tester.pumpWidget(
        _host(container, frozen, selectedLayers: [a, frozen]),
      );
      await _open(tester);

      final row = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Align'),
      );
      expect(row.enabled, isFalse);
    });

    testWidgets('mixed batch with two movable members keeps Align live', (
      tester,
    ) async {
      final a = _shape('a');
      final b = _shape('b');
      final frozen = _shape('frozen', locked: true);
      final container = _containerWith([a, b, frozen]);
      addTearDown(container.dispose);
      container.read(selectionControllerProvider.notifier).selectMany([
        'a',
        'b',
        'frozen',
      ]);

      await tester.pumpWidget(
        _host(container, frozen, selectedLayers: [a, b, frozen]),
      );
      await _open(tester);

      final row = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Align'),
      );
      expect(row.enabled, isTrue);

      await tester.tap(find.text('Align'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        container.read(contextToolbarControllerProvider),
        ContextToolPanel.align,
      );
    });

    // Lock rule: batch flip drops locked members (like batch align)
    // instead of silently flipping frozen content — and the survivors
    // stay ONE composite, so one undo restores the whole gesture.
    testWidgets('mixed batch flip: only unlocked members flip, ONE composite', (
      tester,
    ) async {
      final a = _shape('a');
      final b = _shape('b');
      final frozen = _shape('frozen', locked: true);
      final container = _containerWith([a, b, frozen]);
      addTearDown(container.dispose);
      container.read(selectionControllerProvider.notifier).selectMany([
        'a',
        'b',
        'frozen',
      ]);
      container.read(documentControllerProvider.notifier).clearHistory();

      await tester.pumpWidget(
        _host(container, frozen, selectedLayers: [a, b, frozen]),
      );
      await _open(tester);
      await _tapRow(tester, find.text('Flip horizontally'));
      await tester.pumpAndSettle();

      final doc = container.read(documentControllerProvider);
      expect(doc.layerById('a')!.transform.flipH, isTrue);
      expect(doc.layerById('b')!.transform.flipH, isTrue);
      expect(
        doc.layerById('frozen')!.transform.flipH,
        isFalse,
        reason: 'locked member never flips',
      );

      // ONE undo restores both flipped members — the composite
      // guarantee; a second entry would leave one flipped here.
      container.read(documentControllerProvider.notifier).undo();
      final after = container.read(documentControllerProvider);
      expect(after.layers.every((l) => !l.transform.flipH), isTrue);
      expect(
        container.read(documentControllerProvider.notifier).canUndo,
        isFalse,
        reason: 'the whole batch flip was exactly one history entry',
      );
    });

    testWidgets('all-locked batch: flip rows disabled, nothing committed', (
      tester,
    ) async {
      final a = _shape('a', locked: true);
      final b = _shape('b', locked: true);
      final container = _containerWith([a, b]);
      addTearDown(container.dispose);
      container.read(selectionControllerProvider.notifier).selectMany([
        'a',
        'b',
      ]);
      container.read(documentControllerProvider.notifier).clearHistory();

      await tester.pumpWidget(_host(container, b, selectedLayers: [a, b]));
      await _open(tester);

      for (final label in ['Flip horizontally', 'Flip vertically']) {
        final row = tester.widget<ListTile>(
          find.widgetWithText(ListTile, label),
        );
        expect(row.enabled, isFalse, reason: '$label must render disabled');
      }

      await _tapRow(tester, find.text('Flip horizontally'));
      await tester.pumpAndSettle();
      expect(
        container.read(documentControllerProvider.notifier).canUndo,
        isFalse,
      );
    });

    testWidgets('batch lock locks every member as ONE undo entry', (
      tester,
    ) async {
      final a = _shape('a');
      final b = _shape('b');
      final c = _shape('c');
      final container = _containerWith([a, b, c]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_host(container, c, selectedLayers: [a, b, c]));
      await _open(tester);
      await _tapRow(tester, find.text('Lock layer'));
      await tester.pumpAndSettle();

      final doc = container.read(documentControllerProvider);
      expect(doc.layers.every((l) => l.locked), isTrue);

      container.read(documentControllerProvider.notifier).undo();
      expect(
        container
            .read(documentControllerProvider)
            .layers
            .every((l) => !l.locked),
        isTrue,
        reason: 'one undo unlocks the whole batch',
      );
    });
  });
}
