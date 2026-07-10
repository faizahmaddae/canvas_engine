// Eyedropper contract: from the shared colour picker (embedded in
// the text colour panel), قطره‌چکان snapshots the canvas board,
// tracks the finger with live sampling, and releasing over the
// design applies the colour under the finger — preserving the
// text's current alpha, like every other swatch-style pick.

import 'package:canvas_engine/features/color_picker/presentation/eyedropper_overlay.dart';
import 'package:canvas_engine/features/editor/application/canvas_capture.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Editor with a big red rectangle on the canvas and the text
  /// colour panel (the embedded shared picker) open for `text-1`.
  Future<ProviderContainer> pumpColorPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 1080, height: 1080);
    ctrl.execute(
      AddLayerCommand(
        ShapeLayer(
          id: 'shape-1',
          transform: const LayerTransform(
            position: Offset(100, 100),
            size: Size(600, 600),
          ),
          kind: ShapeKind.rectangle,
          // Document content colour (sample target, not UI chrome).
          fillColor: const Color(0xFFDD2244),
        ),
      ),
    );
    ctrl.execute(
      AddLayerCommand(
        const TextLayer(
          id: 'text-1',
          transform: LayerTransform(
            position: Offset(140, 800),
            size: Size(480, 100),
          ),
          content: 'Hello',
          style: TextStyleSpec(fontSize: 48, color: Color(0x80000000)),
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('text-1');
    container.read(textToolControllerProvider.notifier).openSheet('color');

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

  Color textColorOf(ProviderContainer c) =>
      (c.read(documentControllerProvider).layerById('text-1')! as TextLayer)
          .style
          .color;

  /// Screen position of a logical canvas point, walked through the
  /// live viewport transform via the shared boundary key.
  Offset canvasToScreen(ProviderContainer c, Offset canvasPoint) {
    final key = c.read(canvasBoardBoundaryKeyProvider);
    final box = key.currentContext!.findRenderObject()! as RenderBox;
    return box.localToGlobal(canvasPoint);
  }

  testWidgets('eyedropper button is offered when the canvas is mounted', (
    tester,
  ) async {
    await pumpColorPanel(tester);
    expect(
      find.byKey(const ValueKey('color-picker-eyedropper')),
      findsOneWidget,
    );
  });

  testWidgets(
    'sampling the red shape applies its colour to the text (alpha preserved)',
    (tester) async {
      final container = await pumpColorPanel(tester);

      // Tap in the fake-async zone (so the session future's
      // continuation stays pumpable), then let the real-async engine
      // work (RepaintBoundary.toImage + byte readout) land inside
      // runAsync.
      await tester.tap(find.byKey(const ValueKey('color-picker-eyedropper')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      // Drag over the red rectangle and release.
      final target = canvasToScreen(container, const Offset(400, 400));
      final gesture = await tester.startGesture(target);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final picked = textColorOf(container);
      expect(
        picked.toARGB32() & 0x00FFFFFF,
        0xDD2244,
        reason: 'the colour under the finger must be applied',
      );
      expect(
        picked.a,
        closeTo(0x80 / 255.0, 0.005),
        reason: 'an eyedrop is a hue choice — current alpha survives',
      );
    },
  );

  testWidgets('releasing outside the board cancels and restores the colour', (
    tester,
  ) async {
    final container = await pumpColorPanel(tester);
    final before = textColorOf(container);

    await tester.tap(find.byKey(const ValueKey('color-picker-eyedropper')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    // Press on the design (live colour applies)…
    final onCanvas = canvasToScreen(container, const Offset(400, 400));
    final gesture = await tester.startGesture(onCanvas);
    await tester.pump();
    expect(
      textColorOf(container).toARGB32() & 0x00FFFFFF,
      0xDD2244,
      reason: 'sampling is live while the finger is down',
    );
    // …then slide off the board and release: cancel.
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      textColorOf(container),
      before,
      reason: 'a cancelled eyedrop restores the pre-drag colour',
    );
  });

  test(
    'startCanvasEyedropper without a mounted boundary resolves null',
    () async {
      final key = GlobalKey();
      // No widget tree at all — must not throw, just decline.
      expect(
        await startCanvasEyedropper(_FakeContext(), boundaryKey: key),
        isNull,
      );
    },
  );
}

/// Minimal BuildContext stand-in for the no-boundary guard path —
/// the function returns before ever touching the context.
class _FakeContext extends Fake implements BuildContext {}
