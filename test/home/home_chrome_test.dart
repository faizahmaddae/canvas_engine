import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/saffron_diamond.dart';
import 'package:canvas_engine/features/home/presentation/widgets/home_header.dart';
import 'package:canvas_engine/features/home/presentation/widgets/quick_action_card.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_engine/app/theme/app_icons.dart';

/// Home redesign commit 1 (docs/home-screen-redesign-2026-07.md):
/// the v2 chrome — wordmark header with the saffron diamond and a
/// quiet settings circle, and the two token-driven create cards.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  group('HomeHeader', () {
    testWidgets('renders wordmark, diamond mark, settings and greeting', (
      tester,
    ) async {
      await tester.pumpWidget(host(const HomeHeader()));

      expect(find.byType(SaffronDiamond), findsOneWidget);
      expect(find.text('Canvas'), findsOneWidget); // homeBrandTitle (en)
      expect(find.byIcon(AppIcons.settings), findsOneWidget);
      // Daypart line + headline present.
      expect(find.byType(Text), findsAtLeastNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('greeting uses textPrimary in dark mode', (tester) async {
      await tester.pumpWidget(
        host(const HomeHeader(), brightness: Brightness.dark),
      );
      expect(tester.takeException(), isNull);

      final headline = tester.widget<Text>(
        find.text('What shall we make today?'),
      );
      expect(headline.style?.color, AppTokens.dark.textPrimary);
    });

    // The one line on Home that admits what time it is. Boundaries:
    // [5, 11) morning, [11, 15) noon, [15, 20) evening, else night.
    for (final (hour, expected) in const [
      (5, 'Good morning'),
      (10, 'Good morning'),
      (11, 'Good afternoon'),
      (14, 'Good afternoon'),
      (15, 'Good evening'),
      (19, 'Good evening'),
      (20, 'Good night'),
      (3, 'Good night'),
    ]) {
      testWidgets('daypart greeting at ${hour}h says "$expected"', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(HomeHeader(now: DateTime(2026, 8, 22, hour))),
        );
        expect(find.text(expected), findsOneWidget);
      });
    }

    testWidgets('the daypart line is the saffron accent, and the old '
        'static subtitle is gone', (tester) async {
      await tester.pumpWidget(host(HomeHeader(now: DateTime(2026, 8, 22, 9))));
      final greeting = tester.widget<Text>(find.text('Good morning'));
      expect(greeting.style?.color, AppTokens.light.accentText);
      expect(
        find.textContaining('Start from a template'),
        findsNothing,
        reason: 'the subtitle described the two buttons below it',
      );
    });
  });

  group('QuickActionCard', () {
    testWidgets('filled card: brand fill, onBrand label, saffron icon, '
        'dispatches onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          QuickActionCard(
            label: 'New design',
            icon: AppIcons.add,
            filled: true,
            onTap: () => tapped = true,
          ),
        ),
      );

      final ink = tester.widget<Ink>(find.byType(Ink));
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.color, AppTokens.light.brand);
      expect(decoration.border, isNull);

      final label = tester.widget<Text>(find.text('New design'));
      expect(label.style?.color, AppTokens.light.onBrand);
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.add));
      expect(icon.color, AppTokens.light.accent);

      await tester.tap(find.byType(QuickActionCard));
      expect(tapped, isTrue);
    });

    testWidgets('outline card: surface fill, hairline border, ink label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          QuickActionCard(
            label: 'Edit a photo',
            icon: AppIcons.editPhoto,
            onTap: () {},
          ),
        ),
      );

      final ink = tester.widget<Ink>(find.byType(Ink));
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.color, AppTokens.light.surface);
      expect((decoration.border! as Border).top.color, AppTokens.light.border);

      final label = tester.widget<Text>(find.text('Edit a photo'));
      expect(label.style?.color, AppTokens.light.textPrimary);
    });

    testWidgets('dark mode: filled card flips to cream with ink label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          QuickActionCard(
            label: 'New design',
            icon: AppIcons.add,
            filled: true,
            onTap: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      expect(tester.takeException(), isNull);

      final ink = tester.widget<Ink>(find.byType(Ink));
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.color, AppTokens.dark.brand); // cream
      final label = tester.widget<Text>(find.text('New design'));
      expect(label.style?.color, AppTokens.dark.onBrand); // ink
    });
  });
}
