// Composer-level UX contracts for `showTextInputFlowSheet`.
//
// Pinpoints the rules that make Add Text feel like a focused
// composer rather than a full editor:
//   * Add is disabled until trimmed input is non-empty (no
//     accidental empty layers from a stray tap).
//   * Add becomes enabled the moment trimmed input is non-empty
//     and committing pops the typed value back to the caller.
//   * Pre-commit style strip is intentionally minimal — only Bold
//     and the colour swatch, no italic / underline / alignment
//     icons. Full styling lives in the post-create text panel.
//   * The hint reads "Type something…" — drives the empty-state
//     visual that tells the user this surface is for typing.
//
// Driven through the public `showTextInputFlowSheet` entry so we
// exercise the same code path the editor uses.

import 'package:canvas_engine/features/editor/text/presentation/text_input_flow_sheet.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the composer and returns a tuple of `(resultFuture)` wrapped in
/// a single-element record so the outer awaits don't flatten the inner
/// `Future<String?>` (Dart auto-unwraps nested Futures otherwise).
Future<({Future<String?> result})> _openComposer(
  WidgetTester tester, {
  String initial = '',
  TextDirectionMode textDirectionMode = TextDirectionMode.auto,
}) {
  // Tall test surface so the sheet (incl. quick-style strip) fits
  // without needing scroll plumbing.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late Future<String?> result;

  return tester
      .pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      result = showTextInputFlowSheet(
                        ctx,
                        initial: initial,
                        title: 'Add text',
                        confirmLabel: 'Add',
                        textDirectionMode: textDirectionMode,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      )
      .then((_) async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        return (result: result);
      });
}

void main() {
  testWidgets('Add button is disabled when the input is empty', (tester) async {
    await _openComposer(tester);

    // FilledButton labelled "Add" exists, and is the FilledButton
    // we keyed for confirmation.
    final addButton = find.byKey(const ValueKey('add-text-confirm'));
    expect(addButton, findsOneWidget);

    final btn = tester.widget<FilledButton>(addButton);
    expect(
      btn.onPressed,
      isNull,
      reason:
          'Add must be disabled until trimmed input is non-empty '
          'so a stray tap never commits an empty layer.',
    );
  });

  testWidgets('Add button stays disabled when the input is whitespace only', (
    tester,
  ) async {
    await _openComposer(tester);

    final input = find.byKey(const ValueKey('add-text-input'));
    await tester.enterText(input, '   \n  ');
    await tester.pump();

    final btn = tester.widget<FilledButton>(
      find.byKey(const ValueKey('add-text-confirm')),
    );
    expect(
      btn.onPressed,
      isNull,
      reason: 'Whitespace must trim to empty and stay disabled.',
    );
  });

  testWidgets('Add button enables once non-empty trimmed input is present', (
    tester,
  ) async {
    await _openComposer(tester);

    final input = find.byKey(const ValueKey('add-text-input'));
    await tester.enterText(input, 'Hello');
    await tester.pump();

    final btn = tester.widget<FilledButton>(
      find.byKey(const ValueKey('add-text-confirm')),
    );
    expect(
      btn.onPressed,
      isNotNull,
      reason:
          'Add must enable as soon as the user has typed real '
          'content — the composer should feel responsive.',
    );
  });

  testWidgets('tapping Add pops the trimmed text back to the caller', (
    tester,
  ) async {
    final handle = await _openComposer(tester);

    final input = find.byKey(const ValueKey('add-text-input'));
    await tester.enterText(input, '  Hello world  ');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('add-text-confirm')));
    await tester.pumpAndSettle();

    expect(
      await handle.result,
      'Hello world',
      reason:
          'Commit must trim leading/trailing whitespace so the '
          'staged layer never carries accidental padding.',
    );
  });

  testWidgets('tapping Cancel pops null (no commit)', (tester) async {
    final handle = await _openComposer(tester);

    final input = find.byKey(const ValueKey('add-text-input'));
    await tester.enterText(input, 'Should not commit');
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      await handle.result,
      isNull,
      reason:
          'Cancel must always return null so the caller knows '
          'to revert the staged layer / preview.',
    );
  });

  testWidgets('pre-commit quick-style strip exposes only Bold + Color', (
    tester,
  ) async {
    await _openComposer(tester);

    // Bold is present.
    expect(
      find.byTooltip('Bold'),
      findsOneWidget,
      reason: 'Bold is one of the two pre-commit decisions.',
    );

    // Color swatch is present.
    expect(
      find.byTooltip('Color'),
      findsOneWidget,
      reason: 'Color is the other pre-commit decision.',
    );

    // Italic / underline are intentionally NOT in the composer —
    // they belong to the full text panel post-create.
    expect(
      find.byTooltip('Italic'),
      findsNothing,
      reason:
          'Italic must not appear in the composer — it belongs '
          'to the post-create text panel.',
    );
    expect(
      find.byTooltip('Underline'),
      findsNothing,
      reason:
          'Underline must not appear in the composer — it belongs '
          'to the post-create text panel.',
    );
  });

  testWidgets('placeholder reads "Type something…"', (tester) async {
    await _openComposer(tester);

    expect(
      find.text('Type something…'),
      findsOneWidget,
      reason:
          'The hint sets the empty-state expectation that this '
          'surface is for typing, not for editor controls.',
    );
  });

  testWidgets('commits Persian multiline text unchanged', (tester) async {
    final handle = await _openComposer(tester);

    const value = 'سلام دنیا\nامروز خوب است';
    await tester.enterText(find.byKey(const ValueKey('add-text-input')), value);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-text-confirm')));
    await tester.pumpAndSettle();

    expect(await handle.result, value);
  });

  testWidgets('commits mixed Persian and English text unchanged', (
    tester,
  ) async {
    final handle = await _openComposer(tester);

    const value = 'Sale ۵۰٪ برای امروز';
    await tester.enterText(find.byKey(const ValueKey('add-text-input')), value);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-text-confirm')));
    await tester.pumpAndSettle();

    expect(await handle.result, value);
  });

  testWidgets('forced RTL mode controls the input field direction', (
    tester,
  ) async {
    await _openComposer(
      tester,
      initial: 'Hello سلام',
      textDirectionMode: TextDirectionMode.rtl,
    );

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('add-text-input')),
    );
    expect(field.textDirection, TextDirection.rtl);
    expect(field.textAlign, TextAlign.right);
  });
}
