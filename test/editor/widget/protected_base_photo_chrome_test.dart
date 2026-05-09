// Selection chrome behaviour for the protected base photo.
//
// The user-visible decision (see commit notes): when the protected
// base photo is selected (typically via the Layers panel, since the
// canvas hit-test skips locked layers), we render
//   * the selection FRAME (so "what is selected" is obvious),
//   * a small "Base photo" badge label,
// and we do NOT render
//   * any transform handles,
//   * the floating QuickActionsOverlay (duplicate / delete),
//   * the transform HUD readout.
// Normal layers and overlay images keep their full chrome.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layers_panel.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/quick_actions_overlay.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/selection_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ImageLayer _img(String id, {bool locked = false, Offset pos = Offset.zero}) =>
    ImageLayer(
      id: id,
      transform: LayerTransform(
        position: pos,
        size: const Size(400, 300),
      ),
      source: const ImageSource.asset('a.png'),
      locked: locked,
    );

ProviderContainer _setup(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

Future<void> _photoProject(
  WidgetTester tester,
  ProviderContainer c, {
  String id = 'photo',
}) async {
  final ctrl = c.read(documentControllerProvider.notifier);
  ctrl.newDocument(width: 400, height: 300, kind: ProjectKind.photo);
  ctrl.execute(
    CompositeCommand(
      [AddLayerCommand(_img(id, locked: true)), SetBasePhotoCommand(id)],
      labelOverride: 'Import photo',
    ),
  );
  ctrl.clearHistory();
}

Future<void> _pumpCanvas(
  WidgetTester tester,
  ProviderContainer c,
) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: EditorCanvas())),
  ));
  await tester.pump();
  await tester.pump();
  // Asset-backed ImageLayers in widget tests fail to load (no
  // bundled bytes for `a.png`). The image renderer logs the error
  // via the FlutterError handler; drain it so it does not fail
  // the test. The selection chrome we are testing is independent
  // of whether the bitmap actually decoded.
  tester.takeException();
}

void main() {
  group('protected base photo selection chrome', () {
    testWidgets('shows frame WITHOUT handles + Base photo badge',
        (tester) async {
      final c = _setup(tester);
      await _photoProject(tester, c);
      c.read(selectionControllerProvider.notifier).select('photo');
      await _pumpCanvas(tester, c);

      // Frame is present.
      final frames = tester
          .widgetList<LayerSelectionOverlay>(find.byType(LayerSelectionOverlay))
          .toList();
      expect(frames, hasLength(1));
      // Handles disabled.
      expect(frames.single.showHandles, isFalse);
      // No body drag wired up.
      expect(frames.single.onBody, isNull);
      // Badge label is shown.
      expect(find.text('Base photo'), findsOneWidget);
      // Floating quick-actions toolbar is suppressed.
      expect(find.byType(QuickActionsOverlay), findsNothing);
    });

    testWidgets('overlay image in photo project keeps full chrome',
        (tester) async {
      final c = _setup(tester);
      await _photoProject(tester, c);
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_img('overlay', pos: const Offset(20, 20))));
      c.read(selectionControllerProvider.notifier).select('overlay');
      await _pumpCanvas(tester, c);

      final frames = tester
          .widgetList<LayerSelectionOverlay>(find.byType(LayerSelectionOverlay))
          .toList();
      expect(frames, hasLength(1));
      expect(frames.single.showHandles, isTrue);
      expect(frames.single.onBody, isNotNull);
      // Floating quick-actions toolbar is shown for normal layers.
      expect(find.byType(QuickActionsOverlay), findsOneWidget);
      // No "Base photo" label on the overlay.
      expect(find.text('Base photo'), findsNothing);
    });

    testWidgets('design-project image keeps full chrome', (tester) async {
      final c = _setup(tester);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 800, height: 800);
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_img('a')));
      c.read(selectionControllerProvider.notifier).select('a');
      await _pumpCanvas(tester, c);

      final frame = tester.widget<LayerSelectionOverlay>(
          find.byType(LayerSelectionOverlay));
      expect(frame.showHandles, isTrue);
      expect(frame.onBody, isNotNull);
      expect(find.byType(QuickActionsOverlay), findsOneWidget);
      expect(find.text('Base photo'), findsNothing);
    });

    testWidgets('shape selection chrome unchanged', (tester) async {
      final c = _setup(tester);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 800, height: 800);
      c.read(documentControllerProvider.notifier).execute(
            AddLayerCommand(
              ShapeLayer(
                id: 's',
                transform: const LayerTransform(
                  position: Offset(100, 100),
                  size: Size(80, 80),
                ),
                kind: ShapeKind.rectangle,
              ),
            ),
          );
      c.read(selectionControllerProvider.notifier).select('s');
      await _pumpCanvas(tester, c);

      final frame = tester.widget<LayerSelectionOverlay>(
          find.byType(LayerSelectionOverlay));
      expect(frame.showHandles, isTrue);
      expect(frame.onBody, isNotNull);
      expect(find.text('Base photo'), findsNothing);
    });
  });

  group('Layers panel: tapping protected base photo', () {
    testWidgets(
        'selects the layer AND closes the drawer',
        (tester) async {
      final c = _setup(tester);
      await _photoProject(tester, c);
      final scaffoldKey = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            key: scaffoldKey,
            endDrawer: const LayersPanel(),
            body: const SizedBox.expand(),
          ),
        ),
      ));
      scaffoldKey.currentState!.openEndDrawer();
      await tester.pumpAndSettle();
      expect(find.byType(LayersPanel), findsOneWidget);

      // Tap the (only) layer row.
      await tester.tap(find.text('Image #1'));
      await tester.pumpAndSettle();

      expect(c.read(selectionControllerProvider).selectedId, 'photo');
      // Drawer should now be closed.
      expect(find.byType(LayersPanel), findsNothing);
    });

    testWidgets(
        'tapping a normal layer does NOT auto-close the drawer',
        (tester) async {
      final c = _setup(tester);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 800, height: 800);
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_img('n')));
      final scaffoldKey = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            key: scaffoldKey,
            endDrawer: const LayersPanel(),
            body: const SizedBox.expand(),
          ),
        ),
      ));
      scaffoldKey.currentState!.openEndDrawer();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Image #1'));
      await tester.pumpAndSettle();

      expect(c.read(selectionControllerProvider).selectedId, 'n');
      // Drawer stays open for normal layers (panel curation flow).
      expect(find.byType(LayersPanel), findsOneWidget);
    });
  });
}
