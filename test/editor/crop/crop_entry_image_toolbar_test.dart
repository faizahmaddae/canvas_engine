import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_mode_toolbar.dart';
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

  testWidgets('image-toolbar Crop tab opens the centralised CropSession', (
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
              child: ImageModeToolbar(layer: layer),
            ),
          ),
        ),
      ),
    );

    expect(container.read(cropControllerProvider).active, isFalse);

    final cropFinder = find.byIcon(Icons.crop_rotate_rounded);
    await tester.scrollUntilVisible(cropFinder, 80);
    await tester.tap(cropFinder);
    await tester.pump();

    final s = container.read(cropControllerProvider);
    expect(s.active, isTrue);
    expect(s.layerId, 'img1');
    // The legacy dock-slot path must NOT have been taken.
    expect(
      container.read(imageToolControllerProvider).openSlot,
      isNot(ImageToolSlot.crop),
    );
  });

  testWidgets('image toolbar labels crop and replace as image actions', (
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
              child: ImageModeToolbar(layer: layer),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Crop image'), findsOneWidget);
    expect(find.text('Replace image'), findsOneWidget);
    expect(find.text('Opacity'), findsOneWidget);
    expect(find.text('More actions'), findsOneWidget);
  });

  testWidgets('image toolbar uses short Persian primary labels', (
    tester,
  ) async {
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
              child: ImageModeToolbar(layer: layer),
            ),
          ),
        ),
      ),
    );

    expect(find.text('لوک'), findsOneWidget);
    expect(find.text('کادر'), findsOneWidget);
    expect(find.text('سایه'), findsOneWidget);
    expect(find.text('شفافیت'), findsOneWidget);
    expect(find.text('جایگزین'), findsOneWidget);
    expect(find.text('بیشتر'), findsOneWidget);
    expect(find.text('جایگزینی تصویر'), findsNothing);
    expect(find.text('More actions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image-toolbar Opacity opens compact context panel state', (
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
              child: ImageModeToolbar(layer: layer),
            ),
          ),
        ),
      ),
    );

    final opacityFinder = find.byIcon(Icons.opacity);
    await tester.scrollUntilVisible(opacityFinder, 80);
    await tester.tap(opacityFinder);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(
      container.read(contextToolbarControllerProvider),
      ContextToolPanel.opacity,
    );
    expect(container.read(imageToolControllerProvider).openSlot, isNull);
  });

  testWidgets('broken image toolbar labels replacement as Relink image', (
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
              child: ImageModeToolbar(layer: broken),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Relink image'), findsOneWidget);
    expect(find.text('Replace image'), findsNothing);
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
