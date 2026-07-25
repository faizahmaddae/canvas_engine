// A dock tile is 66dp wide and gives its label 60 of them. A label
// that does not fit is ellipsised, and «Replace i…» / «More acti…»
// tell the user nothing the icon had not already said — the word that
// would have disambiguated the tile is the word that got cut.
//
// So the constraint is real and permanent: a tool tile's label has to
// be ONE short word, and the icon carries the rest. This measures every
// label the dock actually renders, in both locales, against the width
// it will actually get.

import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// The REAL faces. The default test font draws every glyph as a square
/// of the point size, so it over-measures Latin text by roughly half
/// and would fail this on labels that fit comfortably in the product.
Future<void> _loadUiFonts() async {
  const families = <String, List<String>>{
    'Hanken_Grotesk': [
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Regular.ttf',
      'assets/fonts/english/Hanken_Grotesk/HankenGrotesk-Bold.ttf',
    ],
    'Vazir_Regular': ['assets/fonts/farsi/Vazir_Regular.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

/// Every label rendered on a dock TILE (not a chip, not a sheet row).
///
/// Kept by hand rather than scraped, so adding a tile with a long
/// label means consciously adding it here and watching it fail.
List<String> _tileLabels(AppLocalizations l) => [
  // main strip
  l.photoTool, l.textTool, l.stickerTool, l.shapeTool, l.drawTool,
  l.cropTool, l.lookTool, l.canvasTool,
  // image strip
  l.opacityLabel, l.shadowTool, l.borderTool, l.replaceTool, l.relinkTool,
  l.effectsTool, l.selectiveMaskLabel, l.styleTool, l.moreLabel,
  // text strip
  l.sizeTool, l.colorLabel, l.alignAction, l.boldAction, l.italicAction,
  // shape / paint strips
  l.thicknessLabel, l.blurLabel, l.angleLabel, l.roundnessLabel,
  l.widthLabel, l.intensityLabel, l.featherLabel, l.fillLabel,
  // multi-select strip
  l.duplicateAction, l.deleteAction, l.lockAction,
];

void main() {
  // The label's own box: tile width minus the tile's 6dp of gutters.
  const labelWidth = kDockToolTileWidth - 6;
  const compactLabelWidth = kDockToolTileWidthCompact - 6;

  double widthOf(String text, {required double fontSize, String? family}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: family,
          fontSize: fontSize,
          fontWeight: FontWeight.w700, // the active weight — the widest
          letterSpacing: 0,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  testWidgets('the long forms genuinely do NOT fit — this is why the '
      'short ones exist', (tester) async {
    // Negative control. Without it, the guard above could pass simply
    // because nothing is measured properly, and the next person would
    // helpfully "restore" the descriptive labels.
    await _loadUiFonts();
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    for (final long in [
      l.replaceImageAction, // «Replace image» → «Replace i…»
      l.moreActionsSemantics, // «More actions» → «More acti…»
    ]) {
      expect(
        widthOf(long, fontSize: 11, family: 'Hanken_Grotesk'),
        greaterThan(labelWidth),
        reason: '$long would be ellipsised on a tile',
      );
    }
    // «Crop image» clears the full-width tile by under 3dp and loses
    // in the compact strip — close enough that it was never a safe
    // label, only a lucky one.
    expect(
      widthOf(l.cropImageAction, fontSize: 10, family: 'Hanken_Grotesk'),
      greaterThan(compactLabelWidth),
    );
  });

  for (final locale in const [Locale('en'), Locale('fa')]) {
    testWidgets('no dock label is ellipsised — ${locale.languageCode}', (
      tester,
    ) async {
      await _loadUiFonts();
      final l = await AppLocalizations.delegate.load(locale);
      final family = locale.languageCode == 'fa'
          ? 'Vazir_Regular'
          : 'Hanken_Grotesk';
      final tooWide = <String>[];
      for (final label in _tileLabels(l).toSet()) {
        final w = widthOf(label, fontSize: 11, family: family);
        if (w > labelWidth) tooWide.add('$label (${w.toStringAsFixed(1)}dp)');
      }
      expect(
        tooWide,
        isEmpty,
        reason:
            'these need a shorter word — a tile label that ellipsises loses '
            'exactly the part that distinguishes it from its neighbour',
      );
    });

    testWidgets('and none is ellipsised in the compact strip — '
        '${locale.languageCode}', (tester) async {
      // Landscape drops labels for value-less tiles, but the
      // value-bearing ones keep theirs at 10sp in a 50dp box.
      await _loadUiFonts();
      final l = await AppLocalizations.delegate.load(locale);
      final family = locale.languageCode == 'fa'
          ? 'Vazir_Regular'
          : 'Hanken_Grotesk';
      final tooWide = <String>[];
      for (final label in _tileLabels(l).toSet()) {
        final w = widthOf(label, fontSize: 10, family: family);
        if (w > compactLabelWidth) {
          tooWide.add('$label (${w.toStringAsFixed(1)}dp)');
        }
      }
      expect(tooWide, isEmpty);
    });
  }
}
