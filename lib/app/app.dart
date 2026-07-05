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
      home: onboardingComplete ? const NavShell() : const OnboardingFlow(),
    );
  }
}
