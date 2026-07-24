// Delete-protection audit: every UI surface that removes a layer
// must respect `EditorDocument.isProtectedBasePhoto`.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_target_resolver.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layer_actions.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layers_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ImageLayer _img(String id, {bool locked = false}) => ImageLayer(
  id: id,
  transform: LayerTransform(position: Offset.zero, size: const Size(400, 300)),
  source: const ImageSource.asset('a.png'),
  locked: locked,
);

ProviderContainer _photoProject({String id = 'photo'}) {
  final c = ProviderContainer();
  final ctrl = c.read(documentControllerProvider.notifier);
  ctrl.newDocument(width: 400, height: 300, kind: ProjectKind.photo);
  ctrl.execute(
    CompositeCommand([
      AddLayerCommand(_img(id, locked: true)),
      SetBasePhotoCommand(id),
    ], labelOverride: 'Import photo'),
  );
  ctrl.clearHistory();
  return c;
}

Future<void> _withRef(
  WidgetTester tester,
  ProviderContainer c,
  Future<void> Function(BuildContext ctx, WidgetRef ref) body,
) async {
  late BuildContext capturedCtx;
  late WidgetRef capturedRef;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) {
              capturedCtx = ctx;
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  await body(capturedCtx, capturedRef);
}

void main() {
  group('Layers panel delete', () {
    testWidgets('delete is DISABLED for protected base photo', (tester) async {
      final c = _photoProject();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: LayersPanel())),
        ),
      );
      final delete = find.widgetWithIcon(IconButton, Icons.delete_outline);
      expect(delete, findsOneWidget);
      expect(tester.widget<IconButton>(delete).onPressed, isNull);
    });

    testWidgets('delete is ENABLED for normal design-project layer', (
      tester,
    ) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 1080, height: 1080);
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_img('i')));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: LayersPanel())),
        ),
      );
      final delete = find.widgetWithIcon(IconButton, Icons.delete_outline);
      expect(delete, findsOneWidget);
      expect(tester.widget<IconButton>(delete).onPressed, isNotNull);
    });

    testWidgets('overlay row deletable; base-photo row not', (tester) async {
      final c = _photoProject();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_img('overlay')));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: LayersPanel())),
        ),
      );
      final buttons = tester
          .widgetList<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .toList();
      expect(buttons, hasLength(2));
      expect(
        buttons.where((b) => b.onPressed != null),
        hasLength(1),
        reason: 'only the overlay row should have delete enabled',
      );
    });
  });

  group('LayerActions.delete (programmatic)', () {
    testWidgets('Cancel leaves the photo intact', (tester) async {
      final c = _photoProject();
      addTearDown(c.dispose);
      await _withRef(tester, c, (ctx, ref) async {
        final layer = c.read(documentControllerProvider).layerById('photo')!;
        final future = LayerActions.delete(ctx, ref, layer);
        await tester.pump();
        await tester.tap(find.text('Keep'));
        await future;
        await tester.pump();
        final doc = c.read(documentControllerProvider);
        expect(doc.layerById('photo'), isNotNull);
        expect(doc.basePhotoLayerId, 'photo');
        expect(doc.projectKind, ProjectKind.photo);
      });
    });

    testWidgets('Confirm removes photo + flips kind, undoes atomically', (
      tester,
    ) async {
      final c = _photoProject();
      addTearDown(c.dispose);
      await _withRef(tester, c, (ctx, ref) async {
        final layer = c.read(documentControllerProvider).layerById('photo')!;
        final future = LayerActions.delete(ctx, ref, layer);
        await tester.pump();
        await tester.tap(find.text('Remove'));
        await future;
        await tester.pump();
        var doc = c.read(documentControllerProvider);
        expect(doc.layerById('photo'), isNull);
        expect(doc.basePhotoLayerId, isNull);
        expect(doc.projectKind, ProjectKind.design);
        c.read(documentControllerProvider.notifier).undo();
        doc = c.read(documentControllerProvider);
        expect(doc.layerById('photo'), isNotNull);
        expect(doc.basePhotoLayerId, 'photo');
        expect(doc.projectKind, ProjectKind.photo);
      });
    });

    testWidgets('overlay image in photo project deletes WITHOUT confirm', (
      tester,
    ) async {
      final c = _photoProject();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_img('overlay')));
      await _withRef(tester, c, (ctx, ref) async {
        final layer = c.read(documentControllerProvider).layerById('overlay')!;
        await LayerActions.delete(ctx, ref, layer);
        await tester.pump();
        expect(find.text('Remove'), findsNothing);
        expect(find.text('Keep'), findsNothing);
        final doc = c.read(documentControllerProvider);
        expect(doc.layerById('overlay'), isNull);
        expect(doc.basePhotoLayerId, 'photo');
        expect(doc.projectKind, ProjectKind.photo);
      });
    });
  });

  test('protected base photo still resolves for Crop/Filters/Adjust', () {
    final c = _photoProject();
    addTearDown(c.dispose);
    c.read(selectionControllerProvider.notifier).clear();
    final outcome = resolveImageTarget(
      c.read(documentControllerProvider),
      selectedId: null,
    );
    expect(outcome, isA<ImageTargetAutoSelect>());
    expect((outcome as ImageTargetAutoSelect).layer.id, 'photo');
  });
}
