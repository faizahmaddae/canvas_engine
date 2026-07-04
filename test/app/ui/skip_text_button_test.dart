import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/skip_text_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      host(SkipTextButton(label: 'Skip', onPressed: () => tapped = true)),
    );

    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.byType(SkipTextButton));
    expect(tapped, isTrue);
  });

  testWidgets('uses textMuted as the foreground colour', (tester) async {
    await tester.pumpWidget(
      host(SkipTextButton(label: 'Skip', onPressed: () {})),
    );
    final button = tester.widget<TextButton>(find.byType(TextButton));
    final resolved = button.style!.foregroundColor!.resolve({});
    expect(resolved, AppTokens.light.textMuted);
  });

  testWidgets('renders without throwing in dark mode', (tester) async {
    await tester.pumpWidget(
      host(
        SkipTextButton(label: 'Skip', onPressed: () {}),
        brightness: Brightness.dark,
      ),
    );
    expect(tester.takeException(), isNull);
    final button = tester.widget<TextButton>(find.byType(TextButton));
    final resolved = button.style!.foregroundColor!.resolve({});
    expect(resolved, AppTokens.dark.textMuted);
  });
}
