import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'logical canvas board lays out at document size, not screen size',
    (tester) async {
      // Pick a small "screen" and a much larger document.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentControllerProvider.notifier)
          .newDocument(width: 2000, height: 3000);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: EditorCanvas()),
          ),
        ),
      );
      // Let the post-frame fit run.
      await tester.pump();

      // Find the inner board: a SizedBox that is *both* 2000 wide and
      // 3000 tall. If layout were clamped to the screen, no such box
      // would exist.
      final boards = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((s) => s.width == 2000 && s.height == 3000);
      expect(boards, isNotEmpty,
          reason:
              'Logical canvas SizedBox must lay out at the full document '
              'size regardless of screen constraints.');

      // And the viewport should have been auto-fitted (scale < 1 because
      // a 2000x3000 doc has to shrink to fit a 400x800 screen).
      final viewport = container.read(viewportControllerProvider);
      expect(viewport.scale, lessThan(1.0));
    },
  );
}
