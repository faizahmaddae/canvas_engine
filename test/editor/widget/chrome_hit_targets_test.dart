// Pins the tb2 a11y hit-target floor (audit
// chrome-tap-targets-below-44dp): every primary dismiss/commit
// chrome control exposes a hit box of at least
// EditorBreakpoints.kMinHitTarget (44dp) while the PAINTED chrome
// stayed pixel-identical (verified separately by the capture
// byte-compare). Covers the dock-sheet drag-handle dismiss zone
// (was 14dp), the sheet header ✕ chip (was 28dp), the Done pill
// (was 36dp), and the crop top-bar Done/Cancel (visuals 38dp; hit
// inflated by Material's padded tap target — pinned so a future
// `tapTargetSize: shrinkWrap` can't silently regress it). Also
// proves the EXPANDED areas are live by tapping outside the old
// visual bounds.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_sheet_chrome.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_breakpoints.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/mode_done_button.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpEditor(
    WidgetTester tester, {
    List<EditorLayer> layers = const [],
    void Function(ProviderContainer container)? seed,
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
    docCtl.newDocument(width: 1080, height: 1080);
    for (final layer in layers) {
      docCtl.execute(AddLayerCommand(layer));
    }
    seed?.call(container);
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

  TextLayer text(String id) => TextLayer(
    id: id,
    transform: const LayerTransform(
      position: Offset(140, 220),
      size: Size(800, 240),
    ),
    content: 'سلام',
    style: const TextStyleSpec(fontSize: 96),
  );

  group('dock sheet chrome', () {
    Future<ProviderContainer> pumpWithSheet(WidgetTester tester) {
      return pumpEditor(
        tester,
        layers: [text('text-1')],
        seed: (c) {
          c.read(selectionControllerProvider.notifier).select('text-1');
          c.read(textToolControllerProvider.notifier).openSheet('size');
        },
      );
    }

    testWidgets('drag-handle dismiss zone is ≥44dp tall and full width', (
      tester,
    ) async {
      await pumpWithSheet(tester);
      final zone = find.byKey(const ValueKey('dock-sheet-handle-hit'));
      expect(zone, findsOneWidget);
      final size = tester.getSize(zone);
      expect(size.height, greaterThanOrEqualTo(kMinHitTarget));
      expect(
        size.width,
        tester.getSize(find.byType(DockSheetChrome)).width,
        reason: 'the dismiss zone spans the whole sheet width',
      );
    });

    testWidgets('tap in the grown zone (below the painted handle) dismisses', (
      tester,
    ) async {
      final container = await pumpWithSheet(tester);
      final chrome = tester.getRect(find.byType(DockSheetChrome));
      // y+40: inside the 44dp zone but far below the old 14dp
      // handle slot; horizontal centre keeps clear of the ✕ chip.
      await tester.tapAt(Offset(chrome.center.dx, chrome.top + 40));
      await tester.pump();
      expect(container.read(textToolControllerProvider).openSheet, isNull);
    });

    testWidgets('header ✕ chip hit box is 44dp square', (tester) async {
      await pumpWithSheet(tester);
      final hit = find.byKey(const ValueKey('dock-sheet-close-hit'));
      expect(hit, findsOneWidget);
      final size = tester.getSize(hit);
      expect(size.width, greaterThanOrEqualTo(kMinHitTarget));
      expect(size.height, greaterThanOrEqualTo(kMinHitTarget));
    });

    testWidgets('tap outside the painted 28dp ✕ but inside its 44dp box '
        'closes the sheet', (tester) async {
      final container = await pumpWithSheet(tester);
      final hit = find.byKey(const ValueKey('dock-sheet-close-hit'));
      // 2dp inside the hit box corner — ~6dp outside the painted
      // 28dp chip's corner.
      final corner = tester.getTopLeft(hit) + const Offset(2, 2);
      await tester.tapAt(corner);
      await tester.pump();
      expect(container.read(textToolControllerProvider).openSheet, isNull);
    });
  });

  testWidgets('Done pill hit box meets the 44dp floor (visual stays 36dp)', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      layers: [
        ShapeLayer(
          id: 'shape-1',
          transform: const LayerTransform(
            position: Offset(40, 40),
            size: Size(200, 200),
          ),
          kind: ShapeKind.rectangle,
        ),
      ],
      seed: (c) =>
          c.read(selectionControllerProvider.notifier).select('shape-1'),
    );
    final pill = find.byType(ModeDoneButton);
    expect(pill, findsOneWidget);
    final size = tester.getSize(pill);
    expect(size.height, greaterThanOrEqualTo(kMinHitTarget));
    expect(size.width, greaterThanOrEqualTo(kMinHitTarget));
  });

  testWidgets('crop top-bar Done and Cancel hit boxes meet the 44dp floor', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      layers: [
        ImageLayer(
          id: 'img-1',
          transform: const LayerTransform(
            position: Offset(0, 0),
            size: Size(800, 400),
          ),
          source: const ImageSource.asset('assets/missing-test.png'),
        ),
      ],
      seed: (c) => c.read(cropControllerProvider.notifier).openCrop('img-1'),
    );

    // Done is the white FilledButton, Cancel the TextButton — both
    // inflate to ≥44 via Material's padded tap target; pinned so a
    // future shrinkWrap override can't silently regress them.
    final done = tester.getSize(find.byKey(const ValueKey('crop-top-done')));
    expect(done.height, greaterThanOrEqualTo(kMinHitTarget));
    expect(done.width, greaterThanOrEqualTo(kMinHitTarget));
    final cancel = tester.getSize(
      find.byKey(const ValueKey('crop-top-cancel')),
    );
    expect(cancel.height, greaterThanOrEqualTo(kMinHitTarget));
    expect(cancel.width, greaterThanOrEqualTo(kMinHitTarget));
  });
}
