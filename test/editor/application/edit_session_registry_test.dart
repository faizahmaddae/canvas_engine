// Pins the session registry (contract §6, tb2 13/16):
// `anyDraftSessionOpenProvider` is the derived union of every draft
// session (crop, mask, text compose, text edit flow, export
// render/persist), and while it is true the out-of-session history
// affordances go inert — the top-bar undo/redo buttons disable
// (crop/mask unmount the whole AppBar, which satisfies §6
// structurally and is pinned as such), and the Layers drawer
// edge-swipe is off. The export flag's begin/end bracketing is
// pinned controller-level; the multi-finger shortcut's registry
// gate is pinned in two_finger_undo_test.dart.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/edit_session_registry.dart';
import 'package:canvas_engine/features/editor/application/export_session.dart';
import 'package:canvas_engine/features/editor/application/mask_edit_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/text/application/add_text_composer_state.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('anyDraftSessionOpenProvider composition', () {
    test('false at rest; true for each session source; false again', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 400, height: 400);
      // Mask-edit validates its target (images only) — seed one.
      c
          .read(documentControllerProvider.notifier)
          .execute(
            AddLayerCommand(
              ImageLayer(
                id: 'img-1',
                transform: const LayerTransform(
                  position: Offset(0, 0),
                  size: Size(200, 200),
                ),
                source: const ImageSource.asset('assets/missing.png'),
              ),
            ),
          );
      expect(c.read(anyDraftSessionOpenProvider), isFalse);

      c.read(cropControllerProvider.notifier).openCrop('img-1');
      expect(c.read(anyDraftSessionOpenProvider), isTrue);
      c.read(cropControllerProvider.notifier).cancelCrop();
      expect(c.read(anyDraftSessionOpenProvider), isFalse);

      c.read(maskEditControllerProvider.notifier).open('img-1');
      expect(c.read(anyDraftSessionOpenProvider), isTrue);
      c.read(maskEditControllerProvider.notifier).cancel();
      expect(c.read(anyDraftSessionOpenProvider), isFalse);

      c.read(addTextComposerOpenProvider.notifier).setOpen(true);
      expect(c.read(anyDraftSessionOpenProvider), isTrue);
      c.read(addTextComposerOpenProvider.notifier).setOpen(false);
      expect(c.read(anyDraftSessionOpenProvider), isFalse);

      c.read(textEditFlowOpenProvider.notifier).setOpen(true);
      expect(c.read(anyDraftSessionOpenProvider), isTrue);
      c.read(textEditFlowOpenProvider.notifier).setOpen(false);
      expect(c.read(anyDraftSessionOpenProvider), isFalse);

      c.read(exportSessionControllerProvider.notifier).begin();
      expect(c.read(anyDraftSessionOpenProvider), isTrue);
      c.read(exportSessionControllerProvider.notifier).end();
      expect(c.read(anyDraftSessionOpenProvider), isFalse);
    });

    test('export begin/end brackets are idempotent', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final ctrl = c.read(exportSessionControllerProvider.notifier);
      ctrl.begin();
      ctrl.begin(); // double-begin (render then save) never toggles off
      expect(c.read(exportSessionControllerProvider), isTrue);
      ctrl.end();
      expect(c.read(exportSessionControllerProvider), isFalse);
      ctrl.end(); // dispose-backstop after a normal end is a no-op
      expect(c.read(exportSessionControllerProvider), isFalse);
    });
  });

  group('§6 affordance gates (pumped EditorScreen)', () {
    Future<ProviderContainer> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final docCtl = container.read(documentControllerProvider.notifier);
      docCtl.newDocument(width: 1080, height: 1080);
      docCtl.execute(
        AddLayerCommand(
          ShapeLayer(
            id: 'shape-1',
            transform: const LayerTransform(
              position: Offset(40, 40),
              size: Size(200, 200),
            ),
            kind: ShapeKind.rectangle,
          ),
        ),
      );
      docCtl.execute(
        AddLayerCommand(
          ImageLayer(
            id: 'img-1',
            transform: const LayerTransform(
              position: Offset(300, 300),
              size: Size(400, 300),
            ),
            source: const ImageSource.asset('assets/missing-registry.png'),
          ),
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const EditorScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return container;
    }

    Finder undoButton() => find.widgetWithIcon(IconButton, AppIcons.undo);
    bool undoEnabled(WidgetTester tester) =>
        tester.widget<IconButton>(undoButton()).onPressed != null;

    testWidgets('undo/redo buttons disable while an export session is open and '
        're-enable when it ends', (tester) async {
      final container = await pumpEditor(tester);
      expect(undoEnabled(tester), isTrue, reason: 'history exists');

      container.read(exportSessionControllerProvider.notifier).begin();
      await tester.pump();
      expect(
        undoEnabled(tester),
        isFalse,
        reason: '§6: history must not mutate under a session',
      );
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, AppIcons.redo))
            .onPressed,
        isNull,
      );

      container.read(exportSessionControllerProvider.notifier).end();
      await tester.pump();
      expect(undoEnabled(tester), isTrue);
    });

    testWidgets('crop session unmounts the undo buttons (with the AppBar) and '
        'cancel restores them enabled', (tester) async {
      final container = await pumpEditor(tester);
      expect(undoButton(), findsOneWidget);

      container.read(cropControllerProvider.notifier).openCrop('img-1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Crop owns the screen: the whole AppBar (undo included) is
      // gone — §6 satisfied structurally for this session class.
      expect(undoButton(), findsNothing);

      container.read(cropControllerProvider.notifier).cancelCrop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(undoButton(), findsOneWidget);
      expect(undoEnabled(tester), isTrue, reason: 're-enabled on cancel');
    });

    testWidgets('Layers drawer edge-swipe is gated by the registry', (
      tester,
    ) async {
      final container = await pumpEditor(tester);
      Scaffold scaffold() =>
          tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold().endDrawerEnableOpenDragGesture, isTrue);

      // Crop: the editor scaffold is still in the tree underneath
      // the full-screen overlay — its edge gesture must be off.
      container.read(cropControllerProvider.notifier).openCrop('img-1');
      await tester.pump();
      expect(scaffold().endDrawerEnableOpenDragGesture, isFalse);
      container.read(cropControllerProvider.notifier).cancelCrop();
      await tester.pump();
      expect(scaffold().endDrawerEnableOpenDragGesture, isTrue);

      // Mask: rides the live canvas — same gate. (Mask sessions
      // only open on image layers.)
      container.read(maskEditControllerProvider.notifier).open('img-1');
      await tester.pump();
      expect(scaffold().endDrawerEnableOpenDragGesture, isFalse);
      container.read(maskEditControllerProvider.notifier).cancel();
      await tester.pump();
      expect(scaffold().endDrawerEnableOpenDragGesture, isTrue);
    });
  });
}
