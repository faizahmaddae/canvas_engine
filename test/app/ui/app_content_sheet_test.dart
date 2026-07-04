import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/app_content_sheet.dart';
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

  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(host(const AppContentSheet(child: Text('hello'))));
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('fills with surface and rounds only the top corners', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const AppContentSheet(child: SizedBox.shrink())),
    );

    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, AppTokens.light.surface);
    final radius = decoration.borderRadius! as BorderRadius;
    expect(radius.topLeft, const Radius.circular(26));
    expect(radius.bottomLeft, Radius.zero);
  });

  testWidgets('renders without throwing and flips surface in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const AppContentSheet(child: SizedBox.shrink()),
        brightness: Brightness.dark,
      ),
    );
    expect(tester.takeException(), isNull);

    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, AppTokens.dark.surface);
  });
}
