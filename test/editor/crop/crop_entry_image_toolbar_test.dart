import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_studio_bench.dart';
import 'package:canvas_engine/features/editor/crop/presentation/crop_mode_overlay.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the image-toolbar Crop entry-point. Verifies
/// that tapping the Crop tab opens the centralised crop session
/// (instead of toggling the legacy dock body slot).
void main() {
  late ProviderContainer container;
  late ImageLayer layer;

  setUp(() {
    container = ProviderContainer();
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1000, height: 1000);
    layer = ImageLayer(
      id: 'img1',
      transform: LayerTransform(
        position: const Offset(0, 0),
        size: const Size(800, 400),
      ),
      source: const ImageSource.asset('assets/test.png'),
    );
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(layer));
    container.read(selectionControllerProvider.notifier).select('img1');
  });

  tearDown(() => container.dispose());

  testWidgets('image-bench Crop segment opens the centralised CropSession', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 120,
              child: ImageStudioBench(layer: layer),
            ),
          ),
        ),
      ),
    );

    expect(container.read(cropControllerProvider).active, isFalse);

    await tester.tap(find.byKey(const ValueKey('image-aspect-crop')));
    await tester.pump();

    final s = container.read(cropControllerProvider);
    expect(s.active, isTrue);
    expect(s.layerId, 'img1');
    // Crop is a bench action, not a dock slot — no sheet may open.
    expect(container.read(imageToolControllerProvider).openSlot, isNull);
  });

  testWidgets('image bench labels crop and replace as image actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 140,
              child: ImageStudioBench(layer: layer),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Crop'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    // Opacity is the fact cluster's percentage zone, not a labelled
    // tile — the value IS the label.
    expect(find.byKey(const ValueKey('image-pill-opacity')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('image bench uses short Persian primary labels', (tester) async {
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 140,
              child: ImageStudioBench(layer: layer),
            ),
          ),
        ),
      ),
    );

    expect(find.text('فیلتر'), findsOneWidget);
    expect(find.text('سبک'), findsOneWidget);
    expect(find.text('برش'), findsOneWidget);
    expect(find.text('جایگزین'), findsOneWidget);
    expect(find.text('بیشتر'), findsOneWidget);
    expect(find.text('جایگزینی تصویر'), findsNothing);
    expect(find.text('More'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image-bench opacity zone opens compact context panel state', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 140,
              child: ImageStudioBench(layer: layer),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('image-pill-opacity')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      container.read(contextToolbarControllerProvider),
      ContextToolPanel.opacity,
    );
    expect(container.read(imageToolControllerProvider).openSlot, isNull);
  });

  testWidgets('broken image bench labels the specimen as Relink', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final broken = layer.copyAll(
      source: const ImageSource.file('/tmp/canvas_engine_missing_toolbar.png'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 140,
              child: ImageStudioBench(layer: broken),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Relink'), findsOneWidget);
    expect(find.text('Replace'), findsNothing);
  });

  testWidgets('crop overlay exposes obvious Cancel Done and Restore actions', (
    tester,
  ) async {
    container.read(cropControllerProvider.notifier).openCrop('img1');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CropModeOverlay()),
      ),
    );
    await tester.pump();

    expect(find.text('Cancel'), findsOneWidget);
    // The overlay is a screen, not a 60dp tile — it keeps the full
    // phrase. Only the dock tile shortens to «Crop».
    expect(find.text('Crop image'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Restore image'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(container.read(cropControllerProvider).active, isFalse);
  });

  testWidgets('crop overlay Done commits the draft crop', (tester) async {
    container.read(cropControllerProvider.notifier).openCrop('img1');
    container
        .read(cropControllerProvider.notifier)
        .updateDraft(const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CropModeOverlay()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pump();

    final updated =
        container.read(documentControllerProvider).layerById('img1')
            as ImageLayer;
    expect(container.read(cropControllerProvider).active, isFalse);
    expect(updated.cropRect, ImageLayer.fullCrop);
    expect(updated.transform.size.width, closeTo(640, 1e-6));
    expect(updated.transform.size.height, closeTo(240, 1e-6));
  });
}
