// Floating text quick-capsule contracts: renders over a selected
// (non-sticker) text layer, routes each pill to the SAME surface the
// matching bottom-bar tile opens, hides while that surface is open,
// and never appears for emoji stickers.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/quick_actions_overlay.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/text/presentation/text_quick_capsule.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpWithSelection(
    WidgetTester tester, {
    TextLayerKind kind = TextLayerKind.normal,
    String content = 'Hello',
  }) async {
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
        TextLayer(
          id: 'text-1',
          transform: const LayerTransform(
            position: Offset(140, 420),
            size: Size(800, 240),
          ),
          content: content,
          style: const TextStyleSpec(fontSize: 96),
          kind: kind,
        ),
      ),
    );
    container.read(selectionControllerProvider.notifier).select('text-1');

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

  Finder pill(String semanticLabel) => find.descendant(
    of: find.byType(TextQuickCapsule),
    matching: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == semanticLabel,
    ),
  );

  testWidgets('capsule renders over a selected text layer', (tester) async {
    await pumpWithSelection(tester);
    expect(find.byType(TextQuickCapsule), findsOneWidget);
    // Edit first, then font / size / color, then more.
    expect(pill('Edit text'), findsOneWidget);
    expect(pill('Font'), findsOneWidget);
    expect(pill('Size'), findsOneWidget);
    expect(pill('Color'), findsOneWidget);
    expect(pill('More actions'), findsOneWidget);
    // The size pill carries the LIVE px value.
    expect(
      find.descendant(
        of: find.byType(TextQuickCapsule),
        matching: find.text('96px'),
      ),
      findsOneWidget,
    );
  });

  for (final (label, sheetId) in [
    ('Font', 'font'),
    ('Size', 'size'),
    ('Color', 'color'),
  ]) {
    testWidgets('$label pill opens the same "$sheetId" sheet as the bar', (
      tester,
    ) async {
      final c = await pumpWithSelection(tester);
      await tester.tap(pill(label));
      // The canvas root owns double-tap-to-edit, so every in-canvas
      // single tap resolves only after the double-tap window lapses.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        c.read(textToolControllerProvider).openSheet,
        sheetId,
        reason: 'capsule must route through the SAME sheet id the bar uses',
      );
      // While its surface is open the capsule yields — it never
      // stacks on the panel it just opened.
      expect(find.byType(TextQuickCapsule), findsNothing);
    });
  }

  testWidgets('more pill opens the بیشتر modal sheet', (tester) async {
    await pumpWithSelection(tester);
    await tester.tap(pill('More actions'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('edit pill opens the inline text editor', (tester) async {
    await pumpWithSelection(tester);
    await tester.tap(pill('Edit text'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller?.text, 'Hello');
  });

  testWidgets('emoji stickers get NO text capsule (generic pill instead)', (
    tester,
  ) async {
    await pumpWithSelection(
      tester,
      kind: TextLayerKind.emojiSticker,
      content: '😀',
    );
    expect(find.byType(TextQuickCapsule), findsNothing);
    // Stickers keep the generic structural quick-actions pill.
    expect(find.byType(QuickActionsOverlay), findsOneWidget);
  });
}
