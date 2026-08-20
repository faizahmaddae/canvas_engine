import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/onboarding/application/onboarding_complete_provider.dart';
import '../features/onboarding/presentation/onboarding_flow.dart';
import '../features/settings/application/settings_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import 'navigation/nav_shell.dart';
import 'theme/app_theme.dart';

/// Root MaterialApp. Owns locale, theme, and the direct Home mount.
class CanvasEngineApp extends ConsumerWidget {
  const CanvasEngineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocale = ref.watch(appLocaleProvider);
    final onboardingComplete = ref.watch(onboardingCompleteProvider);
    final themeLocale =
        appLocale ?? WidgetsBinding.instance.platformDispatcher.locale;
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: appLocale,
      theme: AppTheme.light(locale: themeLocale),
      darkTheme: AppTheme.dark(locale: themeLocale),
      themeMode: ref.watch(themeModeProvider),
      // Tri-state gate: while the stored flag loads (null) render a
      // plain themed surface — one quiet frame — instead of guessing
      // "new user" and flashing the onboarding Welcome at every cold
      // launch for returning users (ux-audit P2-16).
      home: switch (onboardingComplete) {
        null => const _LaunchHold(),
        true => const NavShell(),
        false => const OnboardingFlow(),
      },
    );
  }
}

/// The frame(s) between process start and the onboarding flag's read:
/// a bare themed surface, no text, no logo — indistinguishable from
/// the OS launch screen, so the app appears to open directly into the
/// right destination.
class _LaunchHold extends StatelessWidget {
  const _LaunchHold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SizedBox.expand());
  }
}
