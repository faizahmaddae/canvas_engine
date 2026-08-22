import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/crop/presentation/crop_mode_overlay.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contracts for the crop control card: the orientation switch that
/// replaced the duplicated portrait/landscape chips, and the pixel
/// readout that says what the frame will produce.
///
/// The switch is the load-bearing part — dropping «۵:۴» and «۹:۱۶»
/// as separate chips is only acceptable because one control reaches
/// every ratio in either orientation, including "Original", which the
/// old strip could not stand on end at all.
void main() {
  late ProviderContainer container;

  ImageLayer landscape() => ImageLayer(
    id: 'img1',
    transform: const LayerTransform(
      position: Offset.zero,
      size: Size(800, 400),
    ),
    source: const ImageSource.asset('assets/test.png'),
  );

  setUp(() {
    container = ProviderContainer();
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1000, height: 1000);
    container
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(landscape()));
  });

  tearDown(() => container.dispose());

  Future<void> pumpOverlay(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CropModeOverlay()),
      ),
    );
    await tester.pump();
  }

  testWidgets('the orientation switch transposes both label and ratio', (
    tester,
  ) async {
    container.read(cropControllerProvider.notifier).openCrop('img1');
    await pumpOverlay(tester);

    // A landscape source opens offering landscape ratios.
    expect(find.text('16:9'), findsOneWidget);
    expect(find.text('9:16'), findsNothing);

    await tester.tap(find.text('16:9'));
    await tester.pump();
    expect(
      container.read(cropControllerProvider).aspectRatio,
      closeTo(16 / 9, 1e-9),
    );

    await tester.tap(find.byKey(const ValueKey('crop-orientation-toggle')));
    await tester.pump();

    // The strip re-labels itself…
    expect(find.text('9:16'), findsOneWidget);
    expect(find.text('16:9'), findsNothing);
    // …and the locked ratio follows, so the frame can never disagree
    // with the row that describes it.
    expect(
      container.read(cropControllerProvider).aspectRatio,
      closeTo(9 / 16, 1e-9),
    );
  });

  testWidgets('a free crop leaves the switch label-only (no ratio lock)', (
    tester,
  ) async {
    container.read(cropControllerProvider.notifier).openCrop('img1');
    await pumpOverlay(tester);

    expect(container.read(cropControllerProvider).aspectRatio, isNull);
    await tester.tap(find.byKey(const ValueKey('crop-orientation-toggle')));
    await tester.pump();
    expect(container.read(cropControllerProvider).aspectRatio, isNull);
  });

  testWidgets('the readout states source pixels, and stays absent until '
      'the bitmap resolves', (tester) async {
    container.read(cropControllerProvider.notifier).openCrop('img1');
    await pumpOverlay(tester);

    // Nothing resolved yet: absent, not «۰ × ۰» (contract §10.3).
    expect(find.byKey(const ValueKey('crop-size-readout')), findsNothing);

    container
        .read(cropControllerProvider.notifier)
        .setSourceAspect(2, pixelSize: const Size(4000, 2000));
    await tester.pump();
    expect(find.text('4000 × 2000'), findsOneWidget);

    // Half the width of the frame is half the pixels.
    container
        .read(cropControllerProvider.notifier)
        .updateDraft(const Rect.fromLTRB(0, 0, 0.5, 1));
    await tester.pump();
    expect(find.text('2000 × 2000'), findsOneWidget);
  });

  test('draftPixelSize composes the draft through the display basis', () {
    // A 4000×2000 bitmap shown by a square box through a cover fit
    // displays its centred half; a draft over the left half of THAT
    // window keeps a quarter of the bitmap's width.
    const session = CropSession(
      active: true,
      layerId: 'img1',
      draftCrop: Rect.fromLTRB(0, 0, 0.5, 1),
      sourceAspect: 2,
      sourcePixelSize: Size(4000, 2000),
      displayBasis: Rect.fromLTRB(0.25, 0, 0.75, 1),
    );
    expect(session.draftPixelSize!.width, closeTo(1000, 1e-9));
    expect(session.draftPixelSize!.height, closeTo(2000, 1e-9));
  });
}
