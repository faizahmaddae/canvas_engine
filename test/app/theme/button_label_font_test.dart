import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_typography.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Button labels must paint in the locale's UI face.
///
/// The trap, which cost a visible bug on Home: `AppTypeScale` roles
/// omit `fontFamily` on purpose so it inherits from the theme — true
/// wherever a `Text` reads an inherited `DefaultTextStyle`, false
/// inside a `ButtonStyle.textStyle`. `ButtonStyleButton` resolves that
/// property with `??` rather than merging, then hands it to
/// `Material.textStyle`, which REPLACES the ambient default. A role
/// passed there lands with a null family and Persian falls back to the
/// platform face — «مشاهده همه» rendered in the system font next to a
/// screen of Vazir.
///
/// These assert the RENDERED style (the `RenderParagraph`'s resolved
/// span), not the widget's declared one: the declared style was never
/// the thing that was wrong.
void main() {
  const persianFamily = 'Vazir_Regular';
  const latinFamily = 'Hanken_Grotesk';

  Widget host(Widget child, {required Locale locale}) => MaterialApp(
    locale: locale,
    theme: AppTheme.light(locale: locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );

  String? renderedFamily(WidgetTester tester, String text) => tester
      .renderObject<RenderParagraph>(find.text(text))
      .text
      .style
      ?.fontFamily;

  for (final (locale, expected) in const [
    (Locale('fa'), persianFamily),
    (Locale('en'), latinFamily),
  ]) {
    testWidgets('a TextButton styling its CHILD keeps the '
        '${locale.languageCode} family', (tester) async {
      await tester.pumpWidget(
        host(
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: Text(
              'مشاهده همه',
              style: AppTypeScale.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          locale: locale,
        ),
      );
      expect(renderedFamily(tester, 'مشاهده همه'), expected);
    });
  }

  // The defect itself, pinned as a demonstration: the SAME role in
  // ButtonStyle.textStyle loses the family. If a future Flutter starts
  // merging that property this test fails, which is the signal to
  // simplify the call sites — not a regression.
  testWidgets('the same role in ButtonStyle.textStyle loses it — this is '
      'why the call sites style their child', (tester) async {
    await tester.pumpWidget(
      host(
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            textStyle: AppTypeScale.caption.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('مشاهده همه'),
        ),
        locale: const Locale('fa'),
      ),
    );
    expect(
      renderedFamily(tester, 'مشاهده همه'),
      isNot(persianFamily),
      reason: 'if this now passes, ButtonStyle.textStyle started merging',
    );
  });

  testWidgets('no app-shell button hands a family-less role to '
      'ButtonStyle.textStyle', (tester) async {
    // A guard the greps cannot give: every button reachable in these
    // trees paints in the locale face. Covers the four Home sites the
    // fix touched via their own widget tests; this one pins the rule
    // for the primitive itself.
    await tester.pumpWidget(
      host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () {},
              child: Text(
                'ادامه',
                style: AppTypeScale.caption.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(onPressed: () {}, child: const Text('ذخیره')),
          ],
        ),
        locale: const Locale('fa'),
      ),
    );
    expect(renderedFamily(tester, 'ادامه'), persianFamily);
    expect(renderedFamily(tester, 'ذخیره'), persianFamily);
  });
}
