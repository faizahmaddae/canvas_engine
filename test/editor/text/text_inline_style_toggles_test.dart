// B/I/U live in the استایل dock panel (audit P3-2): a dock panel is a
// live surface with the canvas visible, which is what document-
// mutating toggles need. They used to sit in the «⋯» overflow sheet,
// mutating behind a full scrim in a list where every other row
// pops-then-acts. The toggles read straight off the layer — no local
// flag state — so the chip always shows the committed truth.

import 'package:canvas_engine/app/theme/app_icons.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
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

  Future<ProviderContainer> openStyles(WidgetTester tester) async {
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
        const TextLayer(
          id: 'text-1',
          transform: LayerTransform(
            position: Offset(140, 220),
            size: Size(480, 100),
          ),
          content: 'Hello',
          style: TextStyleSpec(fontSize: 48),
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('text-1');
    container.read(textToolControllerProvider.notifier).openSheet('styles');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('fa'),
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

  TextStyleSpec style(ProviderContainer c) =>
      (c.read(documentControllerProvider).layerById('text-1')! as TextLayer)
          .style;

  testWidgets('B/I/U toggles live in the styles panel and write one '
      'command each', (tester) async {
    final container = await openStyles(tester);
    final version = container.read(documentCommitVersionProvider);

    expect(find.byIcon(AppIcons.bold), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.bold));
    await tester.pump();
    expect(style(container).isBold, isTrue);
    expect(container.read(documentCommitVersionProvider), version + 1);

    await tester.tap(find.byIcon(AppIcons.textItalic));
    await tester.pump();
    expect(style(container).italic, isTrue);

    await tester.tap(find.byIcon(AppIcons.textUnderline));
    await tester.pump();
    expect(style(container).underline, isTrue);

    // Un-toggle: the chip read the committed layer, so a second tap
    // reverses — no stale local flag.
    await tester.tap(find.byIcon(AppIcons.bold));
    await tester.pump();
    expect(style(container).isBold, isFalse);
  });

  testWidgets('an undo flips the toggle back — the chip mirrors the '
      'document, not widget state', (tester) async {
    final container = await openStyles(tester);

    await tester.tap(find.byIcon(AppIcons.bold));
    await tester.pump();
    expect(style(container).isBold, isTrue);

    container.read(documentControllerProvider.notifier).undo();
    await tester.pump();
    expect(style(container).isBold, isFalse);
  });
}
