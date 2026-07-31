// The font picker must open on a tab that can show where you are.
//
// `_autoTab` used to key off the layer's CONTENT script alone. Every
// new layer gets `Vazir_Regular` (`defaultFontFamilyForContent`
// returns it unconditionally, for any content), so a layer typed in
// English opened the Latin tab — whose entries can never include
// Vazir — and the picker rendered with no selected specimen at all,
// on the default path, for every English text layer.

import 'package:canvas_engine/features/editor/presentation/panels/text/font_picker/inline_browser.dart';
import 'package:canvas_engine/features/editor/text/domain/font_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the inline font body and reports which specimen, if any, the
/// grid is currently marking as selected.
Future<String?> _selectedSpecimen(
  WidgetTester tester, {
  required String? current,
  required String content,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 260,
          child: InlineFontBody(
            layerId: 'l1',
            current: current,
            content: content,
            onPick: (_) {},
            onBrowseAll: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  for (final e in kFontCatalog) {
    if (find.text(e.family).evaluate().isNotEmpty) {
      // Family captions render under each specimen card; the presence
      // of the effective family's caption means its tab is open.
      return e.family;
    }
  }
  return null;
}

void main() {
  testWidgets('English content on the default font opens the Persian tab', (
    tester,
  ) async {
    // current == null is the real default-layer case: no explicit
    // family, but it RENDERS in Vazir and Vazir is what the grid marks.
    final shown = await _selectedSpecimen(
      tester,
      current: null,
      content: 'Hello Dunya',
    );
    expect(
      shown,
      isNotNull,
      reason: 'the picker must never open with nothing highlighted',
    );
    final entry = kFontCatalog.firstWhere((e) => e.family == shown);
    expect(
      entry.script,
      FontScript.arabic,
      reason: 'the default family is Vazir, so its tab must be the one open',
    );
  });

  testWidgets('an explicitly Latin family opens the Latin tab', (tester) async {
    final latin = kFontCatalog.firstWhere((e) => e.script == FontScript.latin);
    final shown = await _selectedSpecimen(
      tester,
      current: latin.family,
      content: 'سلام',
    );
    expect(shown, isNotNull);
    expect(
      kFontCatalog.firstWhere((e) => e.family == shown).script,
      FontScript.latin,
      reason: 'the current font wins over the content script',
    );
  });
}
