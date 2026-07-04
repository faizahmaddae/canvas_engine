import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/app_primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Workstream B, Commit 2: AppPrimaryButton widget test incl. a
/// dark-mode render check (design doc discipline: every new
/// component gets one).
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Scaffold(body: child),
    );
  }

  testWidgets('renders the label and dispatches onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        AppPrimaryButton(label: 'Get Started', onPressed: () => tapped = true),
      ),
    );

    expect(find.text('Get Started'), findsOneWidget);
    await tester.tap(find.byType(AppPrimaryButton), warnIfMissed: false);
    expect(tapped, isTrue);
  });

  testWidgets('fills with brand and labels with onBrand in light mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AppPrimaryButton(label: 'Go', onPressed: () {})),
    );

    final ink = tester.widget<Ink>(find.byType(Ink));
    final decoration = ink.decoration! as BoxDecoration;
    expect(decoration.color, AppTokens.light.brand);

    final text = tester.widget<Text>(find.text('Go'));
    expect(text.style?.color, AppTokens.light.onBrand);
  });

  testWidgets('renders without throwing and stays brand-filled in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AppPrimaryButton(label: 'Go', onPressed: () {}),
        brightness: Brightness.dark,
      ),
    );
    expect(tester.takeException(), isNull);

    final ink = tester.widget<Ink>(find.byType(Ink));
    final decoration = ink.decoration! as BoxDecoration;
    expect(decoration.color, AppTokens.dark.brand);
  });
}
