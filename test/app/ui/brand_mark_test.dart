import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/brand_mark.dart';
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

  testWidgets('renders an onBrand glyph in light mode', (tester) async {
    await tester.pumpWidget(host(const BrandMark()));

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, AppTokens.light.onBrand);
  });

  testWidgets('stays onBrand (fixed white) in dark mode', (tester) async {
    await tester.pumpWidget(
      host(const BrandMark(), brightness: Brightness.dark),
    );
    expect(tester.takeException(), isNull);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, AppTokens.dark.onBrand);
    expect(icon.color, AppTokens.light.onBrand);
  });

  testWidgets('respects the size parameter', (tester) async {
    await tester.pumpWidget(host(const BrandMark(size: 60)));
    final container = tester.widget<Container>(find.byType(Container));
    expect(container.constraints?.maxWidth, 60);
  });
}
