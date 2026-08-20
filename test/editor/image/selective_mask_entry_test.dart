// tb4 9/14 · P3-10: selective masking is a strip tile, not a button
// buried at the bottom of the Effects panel. The tile obeys the
// capability rule — a mask with nothing to mask is a lying control —
// through contract §10.3's UNAVAILABLE state (the Crop/Look grammar,
// tb12): while the effect stack is empty it renders dimmed with a
// spoken precondition, but STAYS live, so the tap can explain itself
// and offer the Look panel, which is where effects are added. A
// disabled tile would be the forbidden third thing: present, inert
// and silent.
//
// The Effects panel's mask section is the second entry to the same
// session and must not carry the opposite rule: over an empty stack
// it hides (the panel's empty state names the recovery) — EXCEPT
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
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_effects_body.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
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

  Widget wrap(Widget child) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  Future<void> pumpToolbar(WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 800,
          height: 120,
          child: ImageModeToolbar(layer: layerOf()),
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

  DockToolTile selectiveTile(WidgetTester tester) =>
      tester.widget<DockToolTile>(
        find.widgetWithIcon(DockToolTile, AppIcons.selectiveMask),
      );

  group('strip tile', () {
    testWidgets('with no effects the tile is dimmed and hinted — not inert', (
      tester,
    ) async {
      await pumpToolbar(tester);

      final tile = selectiveTile(tester);
      expect(
        tile.unavailable,
        isTrue,
        reason:
            'an empty stack fails the precondition and the tile '
            'has to say so before it is pressed, not after',
      );
      expect(
        tile.enabled,
        isTrue,
        reason:
            'unavailable must NOT imply inert — the tap is the '
            'recovery (§10.3)',
      );
      expect(
        tile.unavailableHint,
        'Needs at least one effect',
        reason:
            'the dim is invisible to a screen reader; the hint '
            'names the precondition',
      );
    });

    testWidgets('tapping the unavailable tile explains and offers Look '
        'instead of opening a dead session', (tester) async {
      await pumpToolbar(tester);

      await tester.tap(find.byIcon(AppIcons.selectiveMask));
      await tester.pump();
      expect(
        container.read(maskEditControllerProvider).active,
        isFalse,
        reason: 'a mask over an empty stack would mask nothing',
      );
      expect(
        find.byType(SnackBar),
        findsOneWidget,
        reason: 'the tap explains instead of doing nothing (P3-10)',
      );
      expect(find.text('Add an effect to mask selectively.'), findsOneWidget);

      // Let the snackbar finish entering, then take the recovery.
      // The plain `Look` text also exists as a strip tile label, so
      // scope the finder to the snackbar's action.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.descendant(of: find.byType(SnackBar), matching: find.text('Look')),
      );
      await tester.pump();
      expect(
        container.read(imageToolControllerProvider).openSlot,
        ImageToolSlot.look,
        reason:
            'the recovery must satisfy the stated precondition: '
            'it opens the panel where effects are added',
      );
      expect(container.read(maskEditControllerProvider).active, isFalse);
      // Run out the snackbar's exit animation so no timers leak.
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('with an effect the tile re-lights and opens the '
        'mask-edit session', (tester) async {
      addAnEffect();
      await pumpToolbar(tester);

      expect(
        selectiveTile(tester).unavailable,
        isFalse,
        reason: 'adding an effect has to re-light the tile',
      );

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
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'no lecture when the precondition holds',
      );
    });
  });

  group('effects panel mask section', () {
    Future<void> pumpEffectsBody(WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(SizedBox(width: 400, child: ImageEffectsBody(layer: layerOf()))),
      );
    }

    testWidgets('hides over an empty stack — the empty state names the '
        'recovery', (tester) async {
      await pumpEffectsBody(tester);

      expect(find.text('No effects applied.'), findsOneWidget);
      expect(
        find.text('Open Look to add one.'),
        findsOneWidget,
        reason: 'the hidden section is explained, not silent (§10.3)',
      );
      expect(
        find.text('Adjust region'),
        findsNothing,
        reason:
            'live mask controls over an empty stack would open the '
            'session the strip tile refuses — two paths, opposite '
            'rules (P3-10)',
      );
      expect(find.text('Selective'), findsNothing);
    });

    testWidgets('renders once the stack has an effect', (tester) async {
      addAnEffect();
      await pumpEffectsBody(tester);

      expect(find.text('Selective'), findsOneWidget);
      expect(find.text('Adjust region'), findsOneWidget);
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

      await pumpEffectsBody(tester);
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
