import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layers_panel.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ImageLayer image(String id, {bool locked = false}) => ImageLayer(
    id: id,
    transform: const LayerTransform(
      position: Offset.zero,
      size: Size(400, 300),
    ),
    source: const ImageSource.asset('a.png'),
    locked: locked,
  );

  TextLayer text(String id) => TextLayer(
    id: id,
    transform: const LayerTransform(
      position: Offset(40, 40),
      size: Size(180, 80),
    ),
    content: 'Hello',
    style: const TextStyleSpec(fontSize: 24),
  );

  ShapeLayer shape(String id, Offset position) => ShapeLayer(
    id: id,
    transform: LayerTransform(position: position, size: const Size(80, 80)),
    kind: ShapeKind.rectangle,
  );

  ProviderContainer containerWithLayers(
    List<EditorLayer> layers, {
    List<String> selectedIds = const <String>[],
  }) {
    final container = ProviderContainer();
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 400, height: 300);
    for (final layer in layers) {
      ctrl.execute(AddLayerCommand(layer));
    }
    if (selectedIds.length == 1) {
      container
          .read(selectionControllerProvider.notifier)
          .select(selectedIds.single);
    } else if (selectedIds.length > 1) {
      container
          .read(selectionControllerProvider.notifier)
          .selectMany(selectedIds);
    }
    return container;
  }

  ProviderContainer containerWith({EditorLayer? layer}) {
    return containerWithLayers(
      layer == null ? const <EditorLayer>[] : <EditorLayer>[layer],
      selectedIds: layer == null ? const <String>[] : <String>[layer.id],
    );
  }

  Future<void> pumpEditor(
    WidgetTester tester,
    ProviderContainer container, {
    Locale locale = const Locale('en'),
    Size screenSize = const Size(480, 900),
  }) async {
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const EditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void expectMinimalAppBar() {
    final appBar = find.byType(AppBar);
    // tb4 5/14: the «⋮» is gone. Layers and Export are the only
    // action icons; the document's own actions (rename / resize /
    // fit / save) live in the title menu.
    expect(
      find.descendant(of: appBar, matching: find.byTooltip('Export')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byTooltip('Layers')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.byTooltip('More')),
      findsNothing,
    );
    expect(
      find.descendant(of: appBar, matching: find.byTooltip('Save project')),
      findsNothing,
    );
    expect(
      find.descendant(of: appBar, matching: find.byTooltip('Delete')),
      findsNothing,
    );
    expect(
      find.descendant(of: appBar, matching: find.byTooltip('More actions')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: appBar,
        matching: find.byTooltip('Center selected layer in canvas'),
      ),
      findsNothing,
    );
  }

  testWidgets('main editor app bar exposes Layers and Export affordances', (
    tester,
  ) async {
    final container = containerWith();
    addTearDown(container.dispose);
    await pumpEditor(tester, container);

    expectMinimalAppBar();
  });

  testWidgets('AppBar remains minimal with a text layer selected', (
    tester,
  ) async {
    final container = containerWith(layer: text('text-1'));
    addTearDown(container.dispose);

    await pumpEditor(tester, container);

    expectMinimalAppBar();
    // Two 'Edit text' doors while a text layer is selected: the
    // quick-capsule pill floating over the selection, and the Studio
    // Bench's specimen chip in the dock. Their own contracts live in
    // their tests — here we only pin that the APP BAR stays minimal
    // while they show.
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Edit text',
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('AppBar remains minimal with an image layer selected', (
    tester,
  ) async {
    final container = containerWith(
      layer: image('image-1').copyAll(
        source: const ImageSource.file('/tmp/missing-editor-image.png'),
      ),
    );
    addTearDown(container.dispose);

    await pumpEditor(tester, container);

    expectMinimalAppBar();
    // Printed labels are one word (a tile gives them 60dp); the full
    // phrase is what a screen reader gets. See dock_label_fit_test.
    expect(find.text('Crop'), findsOneWidget);
    expect(find.text('Relink'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
  });

  testWidgets('the Layers icon raises the drawer directly', (tester) async {
    final container = containerWith();
    addTearDown(container.dispose);
    await pumpEditor(tester, container);

    expectMinimalAppBar();
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('Layers'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LayersPanel), findsOneWidget);
  });

  testWidgets('the title menu carries the document actions', (tester) async {
    final container = containerWith();
    addTearDown(container.dispose);
    await pumpEditor(tester, container);

    await tester.tap(find.byKey(const ValueKey('appbar-title-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Resize canvas'), findsOneWidget);
    expect(find.text('Fit to screen'), findsOneWidget);
    expect(find.text('Save project'), findsOneWidget);
  });

  testWidgets('a never-saved document says so under its name', (tester) async {
    final container = containerWith();
    addTearDown(container.dispose);
    await pumpEditor(tester, container);

    expect(
      find.textContaining('Unsaved', findRichText: true),
      findsOneWidget,
      reason:
          'a document that exists only in the crash journal has to '
          'admit it',
    );
  });

  testWidgets('multiple selected layers use contextual toolbar actions', (
    tester,
  ) async {
    final a = shape('a', const Offset(20, 20));
    final b = shape('b', const Offset(140, 80));
    final c = shape('c', const Offset(260, 140));
    final container = containerWithLayers(
      [a, b, c],
      selectedIds: ['a', 'b', 'c'],
    );
    addTearDown(container.dispose);

    await pumpEditor(tester, container);

    expectMinimalAppBar();
    expect(find.text('Align'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    await tester.tap(find.text('Align'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('Distribute horizontally'), findsOneWidget);
    expect(find.byTooltip('Distribute vertically'), findsOneWidget);

    await tester.tap(find.text('Opacity'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('Persian RTL AppBar stays minimal without overflow', (
    tester,
  ) async {
    final container = containerWith();
    addTearDown(container.dispose);

    await pumpEditor(
      tester,
      container,
      locale: const Locale('fa'),
      screenSize: const Size(360, 760),
    );

    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('protected base photo does not expose selected-layer actions', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 400, height: 300, kind: ProjectKind.photo);
    ctrl.execute(
      CompositeCommand([
        AddLayerCommand(image('photo', locked: true)),
        const SetBasePhotoCommand('photo'),
      ], labelOverride: 'Import photo'),
    );
    container.read(selectionControllerProvider.notifier).select('photo');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EditorScreen(),
        ),
      ),
    );
    await tester.pump();
    tester.takeException();

    expect(find.byTooltip('More actions'), findsNothing);
  });
}
