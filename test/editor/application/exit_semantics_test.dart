// Pins the contract §4 exit-semantics fixes (tb2 10/16): the Done
// pill is E2-implies-E1 through ONE lifecycle call (it must close
// the canvas panel and every mode panel before clearing the
// selection), the canvas panel never resurrects across an
// intervening selection (audit shell:canvas-panel-resurrects), and
// the main-strip Look entry mirrors Crop's priorSelectionId
// round-trip (audit crop-filters-adjust-exit-asymmetry): the
// auto-selected image is deselected again when the panel closes,
// while deliberate image-strip entries and mid-flow ownership
// changes keep the user's own selection.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/canvas/application/canvas_tool_controller.dart';
import 'package:canvas_engine/features/editor/canvas/presentation/canvas_panel_body.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/image/application/image_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/domain/paint_tool_type.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_sheet_chrome.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/mode_done_button.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

ShapeLayer _shape(String id) => ShapeLayer(
  id: id,
  transform: const LayerTransform(
    position: Offset(40, 40),
    size: Size(200, 200),
  ),
  kind: ShapeKind.rectangle,
);

ImageLayer _image(String id) => ImageLayer(
  id: id,
  transform: const LayerTransform(
    position: Offset(100, 100),
    size: Size(500, 400),
  ),
  source: const ImageSource.file('/nonexistent-exit-semantics.png'),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// [basePhotoId], when given, seeds a PHOTO project whose base
  /// photo is that layer. The main-strip Look/Crop tiles are P scope
  /// (contract §10) and exist only there, so any test that taps them
  /// must pass it.
  Future<ProviderContainer> pumpEditor(
    WidgetTester tester, {
    List<EditorLayer> layers = const [],
    String? basePhotoId,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final docCtl = container.read(documentControllerProvider.notifier);
    docCtl.newDocument(
      width: 1080,
      height: 1080,
      kind: basePhotoId == null ? ProjectKind.design : ProjectKind.photo,
    );
    for (final layer in layers) {
      docCtl.execute(AddLayerCommand(layer));
    }
    if (basePhotoId != null) {
      docCtl.execute(SetBasePhotoCommand(basePhotoId));
    }
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'canvas panel does not resurrect: open → select layer → Done pill',
    (tester) async {
      final container = await pumpEditor(tester, layers: [_shape('shape-1')]);

      // Open the canvas panel from the idle (no-selection) dock.
      container.read(canvasToolControllerProvider.notifier).togglePanel();
      await settle(tester);
      expect(find.byType(CanvasPanelBody), findsOneWidget);

      // Selecting a layer hides the no-selection branch AND must
      // clear panelOpen — the stale flag was what resurrected the
      // panel on the next deselect.
      container.read(selectionControllerProvider.notifier).select('shape-1');
      await settle(tester);
      expect(find.byType(CanvasPanelBody), findsNothing);
      expect(
        container.read(canvasToolControllerProvider).panelOpen,
        isFalse,
        reason: 'selection must clear canvas panelOpen (no zombie state)',
      );

      // Done pill → E3. The dock returns to the idle branch and the
      // canvas panel must NOT re-mount.
      await tester.tap(find.byType(ModeDoneButton));
      await settle(tester);
      expect(container.read(selectionControllerProvider).hasSelection, isFalse);
      expect(
        find.byType(CanvasPanelBody),
        findsNothing,
        reason: 'audit shell:canvas-panel-resurrects — must stay closed',
      );
      expect(container.read(canvasToolControllerProvider).panelOpen, isFalse);
    },
  );

  testWidgets('Done pill is one seam: closes paint mode, its slot AND a stale '
      'canvas panel (E2 implies E1)', (tester) async {
    final container = await pumpEditor(tester);

    // Stale canvas flag + armed paint mode with an open sub-panel.
    container.read(canvasToolControllerProvider.notifier).togglePanel();
    container
        .read(paintToolControllerProvider.notifier)
        .selectTool(PaintToolType.freestyle);
    container.read(paintToolControllerProvider.notifier).openSlot('color');
    await settle(tester);
    expect(find.byType(ModeDoneButton), findsOneWidget);

    await tester.tap(find.byType(ModeDoneButton));
    await settle(tester);

    final paint = container.read(paintToolControllerProvider);
    expect(paint.panelOpen, isFalse, reason: 'E2: paint mode exited');
    expect(paint.openSlot, isNull, reason: 'E1: paint sub-panel closed');
    expect(paint.activeTool, isNull);
    expect(
      container.read(canvasToolControllerProvider).panelOpen,
      isFalse,
      reason:
          'E1 includes the canvas panel — the old hand-rolled '
          'pill closes missed it',
    );
  });

  testWidgets('main-strip Look auto-selects the image and restores the (empty) '
      'prior selection when the panel closes', (tester) async {
    final container = await pumpEditor(
      tester,
      layers: [_image('img-1')],
      basePhotoId: 'img-1',
    );
    expect(container.read(selectionControllerProvider).hasSelection, isFalse);

    // Reach the tier-2 Look tile on the main strip.
    final strip = find.descendant(
      of: find.byType(EditorScreen),
      matching: find.byType(Scrollable),
    );
    final lookTile = find.byIcon(AppIcons.lookTool);
    await tester.scrollUntilVisible(lookTile, 80, scrollable: strip.first);
    await tester.tap(lookTile);
    await settle(tester);

    // Entry: image auto-selected, Look panel open.
    expect(
      container.read(selectionControllerProvider).selectedId,
      'img-1',
      reason: 'main-strip Look must auto-select its resolved target',
    );
    expect(
      container.read(imageToolControllerProvider).openSlot,
      ImageToolSlot.look,
    );

    // E1 close via the canonical drag-handle tap.
    final chrome = tester.getRect(find.byType(DockSheetChrome));
    await tester.tapAt(Offset(chrome.center.dx, chrome.top + 7));
    await settle(tester);

    expect(container.read(imageToolControllerProvider).openSlot, isNull);
    expect(
      container.read(selectionControllerProvider).hasSelection,
      isFalse,
      reason:
          'audit crop-filters-adjust-exit-asymmetry: closing the '
          'main-strip-entered panel must restore the prior (empty) '
          'selection instead of stranding the user in image mode',
    );
  });

  testWidgets(
    'deliberate image-strip Look entry keeps the selection on close',
    (tester) async {
      final container = await pumpEditor(tester, layers: [_image('img-1')]);
      // The user selected the image themselves: entry happens through
      // the IMAGE strip, which records no main-strip session.
      container.read(selectionControllerProvider.notifier).select('img-1');
      await settle(tester);

      container
          .read(imageToolControllerProvider.notifier)
          .toggleSlot(ImageToolSlot.look);
      await settle(tester);
      container.read(imageToolControllerProvider.notifier).closePanel();
      await settle(tester);

      expect(
        container.read(selectionControllerProvider).selectedId,
        'img-1',
        reason: 'a deliberate selection is never yanked away on E1',
      );
    },
  );

  testWidgets(
    'switching panels inside image mode takes ownership: no restore on '
    'the eventual close',
    (tester) async {
      final container = await pumpEditor(
        tester,
        layers: [_image('img-1')],
        basePhotoId: 'img-1',
      );

      final strip = find.descendant(
        of: find.byType(EditorScreen),
        matching: find.byType(Scrollable),
      );
      final lookTile = find.byIcon(AppIcons.lookTool);
      await tester.scrollUntilVisible(lookTile, 80, scrollable: strip.first);
      await tester.tap(lookTile);
      await settle(tester);
      expect(
        container.read(imageToolControllerProvider).openSlot,
        ImageToolSlot.look,
      );

      // The user moves to a sibling panel — they now own image mode.
      container
          .read(imageToolControllerProvider.notifier)
          .toggleSlot(ImageToolSlot.style);
      await settle(tester);
      container.read(imageToolControllerProvider.notifier).closePanel();
      await settle(tester);

      expect(
        container.read(selectionControllerProvider).selectedId,
        'img-1',
        reason:
            'deliberate interaction with image mode disarms the '
            'main-strip entry session — the selection stays',
      );
    },
  );
}
