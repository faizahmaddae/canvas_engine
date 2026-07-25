// tb4 9/14: selective masking is a strip tile, not a button buried
// at the bottom of the Effects panel. The tile obeys the capability
// rule — a mask with nothing to mask is a lying control — so it stays
// disabled until the layer's effect stack has something in it.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/mask_edit_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_mode_toolbar.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

void main() {
  late ProviderContainer container;

  ImageLayer layerOf() =>
      container.read(documentControllerProvider).layerById('img1')
          as ImageLayer;

  setUp(() {
    container = ProviderContainer();
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1000, height: 1000);
    container
        .read(documentControllerProvider.notifier)
        .execute(
          AddLayerCommand(
            ImageLayer(
              id: 'img1',
              transform: const LayerTransform(
                position: Offset.zero,
                size: Size(800, 400),
              ),
              source: const ImageSource.asset('assets/test.png'),
            ),
          ),
        );
    container.read(selectionControllerProvider.notifier).select('img1');
  });

  tearDown(() => container.dispose());

  Future<void> pumpToolbar(WidgetTester tester) async {
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
              child: ImageModeToolbar(layer: layerOf()),
            ),
          ),
        ),
      ),
    );
  }

  void addAnEffect() {
    container
        .read(documentControllerProvider.notifier)
        .execute(
          const SetImageAdjustmentsCommand(layerId: 'img1', brightness: 20),
        );
  }

  testWidgets('with no effects the tile is present but does nothing', (
    tester,
  ) async {
    await pumpToolbar(tester);

    final tile = find.byIcon(AppIcons.selectiveMask);
    expect(tile, findsOneWidget);

    await tester.tap(tile, warnIfMissed: false);
    await tester.pump();
    expect(
      container.read(maskEditControllerProvider).active,
      isFalse,
      reason: 'a mask over an empty stack would mask nothing',
    );
  });

  testWidgets('with an effect the tile opens the mask-edit session', (
    tester,
  ) async {
    addAnEffect();
    await pumpToolbar(tester);

    await tester.tap(find.byIcon(AppIcons.selectiveMask));
    await tester.pump();

    final session = container.read(maskEditControllerProvider);
    expect(session.active, isTrue);
    expect(session.layerId, 'img1');
    expect(
      session.priorSelectionId,
      'img1',
      reason: 'entering from the image strip returns you to the image',
    );
  });
}
