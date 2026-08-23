// Image-studio §3: the selective-mask section lives inside the Look
// panel, physically below the effects it masks, so its precondition
// is visible instead of narrated. The gating rule is unchanged from
// the retired Effects panel (P3-10): a mask with nothing to mask is
// a lying control, so the section hides over an empty stack — EXCEPT
// while a stack mask survives deleting the last effect, because the
// engine deliberately keeps that mask as user state and the section
// is the only control that can see or clear it.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/mask_edit_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/image_commands.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_look_body.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Widget wrap(Widget child) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  void addAnEffect() {
    container
        .read(documentControllerProvider.notifier)
        .execute(
          const SetImageAdjustmentsCommand(layerId: 'img1', brightness: 20),
        );
  }

  Future<void> pumpLookBody(WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        SingleChildScrollView(
          child: SizedBox(width: 400, child: ImageLookBody(layer: layerOf())),
        ),
      ),
    );
  }

  group('Look panel mask section', () {
    testWidgets('hides over an empty stack', (tester) async {
      await pumpLookBody(tester);

      expect(
        find.text('Adjust region'),
        findsNothing,
        reason:
            'live mask controls over an empty stack would open a '
            'session with nothing to mask (P3-10)',
      );
      expect(find.text('Selective'), findsNothing);
    });

    testWidgets('renders once the stack has an effect — alongside the '
        'applied-effects list', (tester) async {
      addAnEffect();
      await pumpLookBody(tester);

      expect(find.text('Selective'), findsOneWidget);
      expect(find.text('Adjust region'), findsOneWidget);
      expect(
        find.text('Effects'),
        findsOneWidget,
        reason:
            'the applied-effects list surfaces in the same panel — '
            'one surface owns grading (image-studio §3)',
      );
      expect(find.text('Brightness'), findsOneWidget);
    });

    testWidgets('Adjust region opens the mask-edit session for the layer', (
      tester,
    ) async {
      addAnEffect();
      await pumpLookBody(tester);

      await tester.ensureVisible(find.text('Adjust region'));
      await tester.tap(find.text('Adjust region'));
      await tester.pump();

      final session = container.read(maskEditControllerProvider);
      expect(session.active, isTrue);
      expect(session.layerId, 'img1');
      expect(
        session.priorSelectionId,
        'img1',
        reason: 'Done/Cancel must land the user back on the image',
      );
    });

    testWidgets('stays while a mask survives deleting the last effect', (
      tester,
    ) async {
      addAnEffect();
      container
          .read(documentControllerProvider.notifier)
          .execute(
            const SetStackMaskCommand(
              layerId: 'img1',
              mask: RectMask(rect: Rect.fromLTWH(0, 0, 800, 200), feather: 20),
            ),
          );
      container
          .read(documentControllerProvider.notifier)
          .execute(const DeleteEffectCommand(layerId: 'img1', index: 0));

      expect(layerOf().effects.effects, isEmpty);
      expect(
        layerOf().effects.stackMask,
        isNotNull,
        reason: 'the engine keeps the mask on purpose — it is user state',
      );

      await pumpLookBody(tester);
      expect(
        find.text('Adjust region'),
        findsOneWidget,
        reason:
            'hiding the section now would leave the mask set but '
            'sightless, with no control anywhere to see or clear it',
      );
    });
  });
}
