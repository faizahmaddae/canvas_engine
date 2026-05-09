import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_mode_toolbar.dart';
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

  testWidgets(
    'image-toolbar Crop tab opens the centralised CropSession',
    (tester) async {
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
    },
  );
}
