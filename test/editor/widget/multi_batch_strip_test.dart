// tb6 1/5: the multi strip's batch structural actions are one tap
// again — the approved prototype had del/dup/lock on the strip and
// the first implementation buried them in the overflow sheet.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/multi_select_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/slot_strip.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ShapeLayer shape(String id) => ShapeLayer(
    id: id,
    kind: ShapeKind.rectangle,
    transform: LayerTransform(
      position: const Offset(40, 40),
      size: const Size(100, 100),
    ),
  );

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final doc = container.read(documentControllerProvider.notifier);
    doc.newDocument(width: 1080, height: 1080);
    doc.execute(AddLayerCommand(shape('a')));
    doc.execute(AddLayerCommand(shape('b')));
    container.read(selectionControllerProvider.notifier).select('a');
    container.read(selectionControllerProvider.notifier).toggle('b');

    final layers = container.read(documentControllerProvider).layers;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 120,
              child: MultiSelectModeToolbar(layers: layers),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('the batch trio is on the strip, one tap each', (tester) async {
    await pump(tester);
    final strip = tester.widget<SlotStrip>(find.byType(SlotStrip));
    final ids = strip.slots.map((s) => s.id).toList();
    expect(ids, contains('duplicate'));
    expect(ids, contains('lock'));
    expect(ids, contains('delete'));
    // Still reachable the old way too — this added reach, it did not
    // move anything out of the overflow sheet.
    expect(ids, contains('more'));
    expect(
      ids.indexOf('delete'),
      greaterThan(ids.indexOf('duplicate')),
      reason: 'the destructive tile is not the one next to align',
    );
  });

  testWidgets('batch delete removes both layers in ONE undo entry', (
    tester,
  ) async {
    final c = await pump(tester);
    final before = c.read(documentCommitVersionProvider);

    final strip = tester.widget<SlotStrip>(find.byType(SlotStrip));
    strip.slots.firstWhere((s) => s.id == 'delete').onTap();
    await tester.pump();

    expect(c.read(documentControllerProvider).layers, isEmpty);
    expect(
      c.read(documentCommitVersionProvider),
      before + 1,
      reason: 'a batch is one composite, not one command per layer',
    );

    c.read(documentControllerProvider.notifier).undo();
    expect(c.read(documentControllerProvider).layers.length, 2);
  });

  testWidgets('batch duplicate adds two clones in ONE undo entry', (
    tester,
  ) async {
    final c = await pump(tester);
    final before = c.read(documentCommitVersionProvider);

    final strip = tester.widget<SlotStrip>(find.byType(SlotStrip));
    strip.slots.firstWhere((s) => s.id == 'duplicate').onTap();
    await tester.pump();

    expect(c.read(documentControllerProvider).layers.length, 4);
    expect(c.read(documentCommitVersionProvider), before + 1);

    c.read(documentControllerProvider.notifier).undo();
    expect(c.read(documentControllerProvider).layers.length, 2);
  });

  testWidgets('the lock tile flips its verb once the batch is locked', (
    tester,
  ) async {
    final c = await pump(tester);
    final strip = tester.widget<SlotStrip>(find.byType(SlotStrip));
    expect(strip.slots.firstWhere((s) => s.id == 'lock').label, 'Lock');

    strip.slots.firstWhere((s) => s.id == 'lock').onTap();
    await tester.pump();

    expect(
      c.read(documentControllerProvider).layers.every((l) => l.locked),
      isTrue,
    );
    // Rebuild with the new layer list — the tile reads the same
    // `allLocked` the overflow sheet's row does.
    final relocked = c.read(documentControllerProvider).layers;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 120,
              child: MultiSelectModeToolbar(layers: relocked),
            ),
          ),
        ),
      ),
    );
    final after = tester.widget<SlotStrip>(find.byType(SlotStrip));
    expect(after.slots.firstWhere((s) => s.id == 'lock').label, 'Unlock');
  });
}
