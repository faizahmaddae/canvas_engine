// tb6 4/5: the Done pill reads `editorToolModeProvider` instead of
// re-deriving its own mode from paint/text `panelOpen`. These pin the
// behaviour that survived the refactor, including the ONE extra rule
// the pill still owns (the protected base photo).

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/mode_done_button.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required void Function(ProviderContainer) setup,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    setup(container);
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

  testWidgets('idle: no selection, no pill', (tester) async {
    await pump(
      tester,
      setup: (c) => c
          .read(documentControllerProvider.notifier)
          .newDocument(width: 1080, height: 1080),
    );
    expect(find.byType(ModeDoneButton), findsNothing);
  });

  testWidgets('a selected shape shows the pill', (tester) async {
    await pump(
      tester,
      setup: (c) {
        final doc = c.read(documentControllerProvider.notifier);
        doc.newDocument(width: 1080, height: 1080);
        doc.execute(
          AddLayerCommand(
            ShapeLayer(
              id: 's1',
              kind: ShapeKind.rectangle,
              transform: const LayerTransform(
                position: Offset(40, 40),
                size: Size(100, 100),
              ),
            ),
          ),
        );
        c.read(selectionControllerProvider.notifier).select('s1');
      },
    );
    expect(find.byType(ModeDoneButton), findsOneWidget);
  });

  testWidgets('a selected PAINT layer shows the pill — the case the old '
      'panelOpen derivation could miss', (tester) async {
    await pump(
      tester,
      setup: (c) {
        final doc = c.read(documentControllerProvider.notifier);
        doc.newDocument(width: 1080, height: 1080);
        doc.execute(
          AddLayerCommand(
            PaintLayer(
              id: 'p1',
              transform: const LayerTransform(
                position: Offset(20, 20),
                size: Size(200, 200),
              ),
              kind: PaintKind.freestyle,
              normalizedPoints: const [Offset(0.1, 0.1), Offset(0.9, 0.9)],
            ),
          ),
        );
        c.read(selectionControllerProvider.notifier).select('p1');
      },
    );
    expect(find.byType(ModeDoneButton), findsOneWidget);
  });

  testWidgets('the protected base photo keeps the pill suppressed — the '
      'pill\'s one remaining rule of its own', (tester) async {
    await pump(
      tester,
      setup: (c) {
        final doc = c.read(documentControllerProvider.notifier);
        doc.newDocument(width: 1080, height: 1080, kind: ProjectKind.photo);
        doc.execute(
          AddLayerCommand(
            ImageLayer(
              id: 'base',
              transform: const LayerTransform(
                position: Offset.zero,
                size: Size(1080, 1080),
              ),
              source: const ImageSource.file('/nonexistent.png'),
            ),
          ),
        );
        doc.execute(const SetBasePhotoCommand('base'));
        c.read(selectionControllerProvider.notifier).select('base');
      },
    );
    expect(
      find.byType(ModeDoneButton),
      findsNothing,
      reason: 'the base photo is the canvas, not an object selection',
    );
  });
}
