// Pins for tb2 12/16 (interaction contract §1/§2/§8):
//   * All-fonts live preview — highlighting stages the family on
//     the live overlay through the style-drag session (committed
//     doc frozen), picking commits exactly ONE UpdateTextCommand,
//     dismissing un-picked reverts with ZERO history entries;
//   * the sheet's highlight→pick tap grammar + preview debounce;
//   * the write seam — style writes during an open live-edit
//     session stage on the overlay and never bump the commit
//     version;
//   * visualFontSizeOf — readouts report the FittedBox-magnified
//     px for corner-up-scaled scaleText layers, raw px otherwise
//     (mirroring the write path's compensation asymmetry).

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/panels/text/font_picker/picker_sheet.dart';
import 'package:canvas_engine/features/editor/text/application/text_tool_controller.dart';
import 'package:canvas_engine/features/editor/text/domain/font_catalog.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(documentControllerProvider.notifier)
        .newDocument(width: 800, height: 800);
    return c;
  }

  TextLayer addText(
    ProviderContainer c, {
    Size size = const Size(200, 80),
    double fontSize = 24,
  }) {
    final layer = TextLayer(
      id: 't1',
      transform: LayerTransform(position: const Offset(50, 50), size: size),
      content: 'hello world',
      style: TextStyleSpec(fontSize: fontSize),
    );
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(layer));
    c.read(selectionControllerProvider.notifier).select('t1');
    return layer;
  }

  group('all-fonts preview session (controller level)', () {
    test('highlight stages overlay; committed doc frozen', () {
      final c = makeContainer();
      addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      final v0 = c.read(documentCommitVersionProvider);

      ctrl.beginStyleDrag();
      ctrl.setFontFamily('Lobster');
      expect(c.read(documentCommitVersionProvider), v0);
      final staged =
          c.read(liveOverlayProvider).replacements['t1'] as TextLayer;
      expect(staged.style.fontFamily, 'Lobster');
      final committed =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(committed.style.fontFamily, isNull);
      ctrl.cancelStyleDrag();
    });

    test('dismiss un-picked reverts: overlay dropped, zero entries', () {
      final c = makeContainer();
      addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      final v0 = c.read(documentCommitVersionProvider);

      ctrl.beginStyleDrag();
      ctrl.setFontFamily('Lobster');
      ctrl.cancelStyleDrag();

      expect(c.read(documentCommitVersionProvider), v0);
      expect(c.read(liveOverlayProvider).isEmpty, isTrue);
      expect(ctrl.isStyleDragOpen, isFalse);
      final committed =
          c.read(documentControllerProvider).layerById('t1') as TextLayer;
      expect(committed.style.fontFamily, isNull);
    });

    test('pick commits exactly ONE entry; single undo restores', () {
      final c = makeContainer();
      addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      final v0 = c.read(documentCommitVersionProvider);

      ctrl.beginStyleDrag();
      ctrl.setFontFamily('Lobster');
      ctrl.setFontFamily('Vazirmatn');
      ctrl.endStyleDrag();

      expect(c.read(documentCommitVersionProvider), v0 + 1);
      expect(
        (c.read(documentControllerProvider).layerById('t1') as TextLayer)
            .style
            .fontFamily,
        'Vazirmatn',
      );
      c.read(documentControllerProvider.notifier).undo();
      expect(
        (c.read(documentControllerProvider).layerById('t1') as TextLayer)
            .style
            .fontFamily,
        isNull,
        reason: 'the whole browse session is one undo step',
      );
    });
  });

  group('write seam (§2)', () {
    test('style write during a live EDIT session stages on the overlay '
        'and never bumps the commit version', () {
      final c = makeContainer();
      addText(c);
      final ctrl = c.read(textToolControllerProvider.notifier);
      ctrl.beginEditText();
      final v0 = c.read(documentCommitVersionProvider);

      ctrl.setColor(const Color(0xFF112233));
      ctrl.setFontFamily('Lobster');

      expect(c.read(documentCommitVersionProvider), v0);
      final staged =
          c.read(liveOverlayProvider).replacements['t1'] as TextLayer;
      expect(staged.style.color, const Color(0xFF112233));
      expect(staged.style.fontFamily, 'Lobster');
      ctrl.cancelLiveEdit();
    });
  });

  group('visualFontSizeOf (§ readout honesty)', () {
    test('up-scaled scaleText layer reports magnified px; unscaled and '
        'down-scaled report raw', () {
      final c = makeContainer();
      final ctrl = c.read(textToolControllerProvider.notifier);
      // Up-scaled: a 300px-tall box around ~28px of natural metrics.
      final up = addText(c, size: const Size(600, 300), fontSize: 24);
      final upVisual = ctrl.visualFontSizeOf(up);
      expect(upVisual, greaterThan(24 * 2));

      // Down-scaled: box far smaller than the 96px natural metrics —
      // the write path passes raw through, so the readout must too.
      final down = TextLayer(
        id: 't2',
        transform: const LayerTransform(
          position: Offset(0, 0),
          size: Size(60, 24),
        ),
        content: 'hello world',
        style: const TextStyleSpec(fontSize: 96),
      );
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(down));
      expect(ctrl.visualFontSizeOf(down), 96);
    });
  });

  group('all-fonts sheet tap grammar (widget level)', () {
    Future<(List<String?>, Future<FontPickResult>)> openSheet(
      WidgetTester tester,
    ) async {
      final highlights = <String?>[];
      late Future<FontPickResult> result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    result = showFontPickerSheet(
                      ctx,
                      current: null,
                      initialScript: FontScript.latin,
                      specimenText: 'hello world',
                      onHighlight: highlights.add,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (highlights, result);
    }

    // A real catalog row: the system-default row equals `current`
    // (null) in this harness, so it picks on FIRST tap by design —
    // the two-step grammar applies to not-yet-previewed families.
    final firstLatin = kFontCatalog.firstWhere(
      (e) => e.script == FontScript.latin,
    );

    testWidgets('first tap highlights (debounced preview), second tap '
        'on the same row picks', (tester) async {
      final (highlights, result) = await openSheet(tester);
      final row = find.text(firstLatin.labelFor('en'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        highlights,
        isEmpty,
        reason: 'preview is debounced by kFontPreviewDebounce',
      );
      await tester.pump(kFontPreviewDebounce);
      expect(highlights, [firstLatin.family]);
      expect(
        find.text('open'),
        findsOneWidget,
        reason: 'sheet stays open after a highlight',
      );

      await tester.tap(row);
      await tester.pumpAndSettle();
      final picked = await result;
      expect(picked.isDismissed, isFalse);
      expect(picked.family, firstLatin.family);
    });

    testWidgets('dismissing without picking resolves unchanged', (
      tester,
    ) async {
      final (highlights, result) = await openSheet(tester);
      final row = find.text(firstLatin.labelFor('en'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump(kFontPreviewDebounce);
      expect(highlights, [firstLatin.family]);
      // Barrier tap = dismiss.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      final picked = await result;
      expect(picked.isDismissed, isTrue);
    });
  });
}
