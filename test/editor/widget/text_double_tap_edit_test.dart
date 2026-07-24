// Double-tap IS the on-canvas edit affordance for text (text-tool
// redesign step 1): the floating pill that owned "edit" is gone, so
// double-tapping a text layer must select it and open the keyboard
// editor. Emoji stickers (TextLayers without an editable text flow)
// stay excluded.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 400, height: 300);
    ctrl.execute(
      AddLayerCommand(
        const TextLayer(
          id: 'text-1',
          transform: LayerTransform(
            position: Offset(40, 40),
            size: Size(320, 120),
          ),
          content: 'Hello',
          style: TextStyleSpec(fontSize: 48),
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

  testWidgets('double-tap on a text layer selects it and opens the editor', (
    tester,
  ) async {
    final container = await pump(tester);

    // The canvas auto-fits, so hit the layer through its rendered
    // text rather than computing viewport math here.
    final target = tester.getCenter(find.text('Hello'));
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(container.read(selectionControllerProvider).selectedId, 'text-1');
    // The keyboard editor sheet is open with the layer's content.
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Hello',
    );
  });
}
