// UX audit P3-13: the hex field flagged its error border four times
// while a valid six-digit code was being typed — every incomplete
// prefix ('E', 'EF44', 'EF444') parsed as null and lit the border.
// The contract pinned here: while TYPING, only input that can never
// become valid (an illegal character, more than 8 digits) shows the
// error; incompleteness is judged at submit, where an explicit "done"
// on a half code is a real error.

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

  Future<ProviderContainer> openCustomWheel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 667);
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
          style: TextStyleSpec(fontSize: 48, color: Color(0xFFFF0000)),
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
    await tester.tap(find.byKey(const ValueKey('color-picker-custom')));
    await tester.pumpAndSettle();
    return container;
  }

  // Two hex rows exist while the wheel sheet is up (the embedded
  // panel keeps its own mounted underneath) — scope every read to the
  // wheel sheet's subtree.
  Finder hexRow() => find.descendant(
    of: find.byKey(const ValueKey('color-picker-level-custom')),
    matching: find.byKey(const ValueKey('color-picker-hex')),
  );

  /// The error state renders as the thicker (1.5) error-coloured
  /// hairline on the field's container — the field's only outline.
  bool errorShown(WidgetTester tester) {
    final box = tester.widget<Container>(hexRow());
    final border = (box.decoration! as BoxDecoration).border! as Border;
    return border.top.width > 1.2;
  }

  Finder hexField() =>
      find.descendant(of: hexRow(), matching: find.byType(TextField)).first;

  testWidgets('typing a valid code character by character never flashes the '
      'error border', (tester) async {
    await openCustomWheel(tester);

    const code = 'EF4444';
    for (var i = 1; i <= code.length; i++) {
      await tester.enterText(hexField(), code.substring(0, i));
      await tester.pump();
      expect(
        errorShown(tester),
        isFalse,
        reason: 'prefix "${code.substring(0, i)}" can still become valid',
      );
    }
  });

  testWidgets('illegal characters cannot enter the field at all, so typing '
      'never reaches an error state', (tester) async {
    await openCustomWheel(tester);

    // The input formatter allows only hex digits and '#': garbage is
    // rejected at the keyboard, not flagged after the fact.
    await tester.enterText(hexField(), 'XY');
    await tester.pump();
    expect(tester.widget<TextField>(hexField()).controller!.text, isEmpty);
    expect(errorShown(tester), isFalse);
  });

  testWidgets('submitting an incomplete code is a real error', (tester) async {
    await openCustomWheel(tester);

    await tester.enterText(hexField(), 'EF44');
    await tester.pump();
    expect(errorShown(tester), isFalse, reason: 'still typing — no judgment');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      errorShown(tester),
      isTrue,
      reason: 'an explicit done on a half code is the moment to say so',
    );
  });
}
