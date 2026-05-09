// Contracts for the inline Font panel's data layer.
//
// The Font panel itself is a widget, but the *decisions* the panel
// makes — what counts as "Recommended" per script, and what sample
// word each font is previewed with — are pure functions exposed
// from `text_mode_toolbar.dart`. Pinning them here keeps the
// designed-for visual behaviour from drifting silently.

import 'package:canvas_engine/features/editor/text/domain/font_catalog.dart';
import 'package:canvas_engine/features/editor/text/presentation/text_mode_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recommendedFontEntries', () {
    test('Latin: surfaces Roboto first (workhorse default)', () {
      final recs = recommendedFontEntries(FontScript.latin);
      expect(recs, isNotEmpty);
      expect(recs.first.family, 'Roboto',
          reason:
              'Roboto is the auto-default for English content — '
              'putting it first means the active font is visible '
              'without scrolling on a fresh layer.');
    });

    test('Farsi: surfaces Vazir first (Persian default)', () {
      final recs = recommendedFontEntries(FontScript.arabic);
      expect(recs, isNotEmpty);
      expect(recs.first.family, 'Vazir_Regular',
          reason: 'Vazir is the Persian auto-default — must lead.');
    });

    test('mixes personalities, not just one category', () {
      // A "Recommended" tab full of identical sans faces would be
      // useless. The curated kit must include at least one display
      // OR script entry per script so the user can sense the range.
      for (final s in FontScript.values) {
        final recs = recommendedFontEntries(s);
        final categories = recs.map((e) => e.category).toSet();
        expect(categories.length, greaterThanOrEqualTo(2),
            reason:
                '${s.name}: Recommended must mix categories, '
                'found only $categories');
      }
    });

    test('every recommended family exists in kFontCatalog', () {
      // Guards against typos when curating the list — a missing
      // family would silently disappear from the panel.
      final shipped =
          kFontCatalog.map((e) => e.family).toSet();
      for (final s in FontScript.values) {
        for (final r in recommendedFontEntries(s)) {
          expect(shipped, contains(r.family),
              reason: '${r.family} is recommended but not shipped');
          expect(r.script, s,
              reason: '${r.family} is in the wrong script bucket');
        }
      }
    });

    test('stays a short list (\u22647) — Recommended is curated, not exhaustive', () {
      for (final s in FontScript.values) {
        expect(recommendedFontEntries(s).length, lessThanOrEqualTo(7),
            reason:
                '${s.name}: Recommended ballooned — pick the strict '
                '"safe trio + a couple statement faces" kit');
      }
    });
  });

  group('fontSampleText', () {
    FontEntry entryFor(String family) =>
        kFontCatalog.firstWhere((e) => e.family == family);

    test('Arabic faces preview a real Persian word, not "Aa"', () {
      // "Aa" tells you nothing about how the face shapes Persian
      // joined letters — the whole reason a Persian designer is
      // browsing this panel.
      expect(fontSampleText(entryFor('Vazir_Regular')), 'سلام دنیا');
      expect(fontSampleText(entryFor('BNazanin')), 'سلام دنیا');
    });

    test('Latin display faces preview a statement word', () {
      // "POSTER" exercises the all-caps weight and texture that
      // designers actually pick a display face for — "Aa" hides it.
      expect(fontSampleText(entryFor('Bungee_Shade')), 'POSTER');
      expect(fontSampleText(entryFor('Lobster')), 'POSTER');
    });

    test('Latin sans/script preview a readable word ("Hello")', () {
      expect(fontSampleText(entryFor('Roboto')), 'Hello');
      expect(fontSampleText(entryFor('Dancing_Script')), 'Hello');
    });

    test('mono previews include a digit ("Hello 12")', () {
      // The point of a mono face is fixed-width digits — the
      // sample needs to contain at least one digit to reveal it.
      final s = fontSampleText(entryFor('Chivo_Mono'));
      expect(s.contains(RegExp(r'\d')), isTrue,
          reason: 'mono sample "$s" must include a digit');
    });

    test('never returns an empty string', () {
      // An empty preview = an empty card = no signal.
      for (final e in kFontCatalog) {
        expect(fontSampleText(e), isNotEmpty,
            reason: '${e.family} produced an empty sample');
      }
    });
  });
}
