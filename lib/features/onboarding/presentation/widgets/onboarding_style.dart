import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';

/// Onboarding primitives shared by Welcome, Goal, and Ready.
///
/// Design rationale:
/// - The product is a Persian creative tool, so the base feels like a
///   warm design-magazine page rather than a blank utility surface.
/// - Purple remains the brand accent, supported by restrained rose and
///   saffron notes borrowed from Persian editorial palettes.
/// - Background color is soft and low contrast; depth comes from
///   layered cards and typography, not noisy decoration.
abstract final class OnboardingPalette {
  static const Color backgroundTop = Color(0xFFFFFBF6);
  static const Color backgroundBottom = Color(0xFFF3F0FF);
  static const Color surface = Color(0xFFFFFEFC);
  static const Color surfaceMuted = Color(0xFFFAF7F2);
  static const Color canvasPaper = Color(0xFFFFFCF7);
  static const Color ink = Color(0xFF17151F);
  static const Color muted = Color(0xFF746C7E);
  static const Color hairline = Color(0xFFE9DFD7);
  static const Color accent = Color(0xFF7C5CFF);
  static const Color accentPressed = Color(0xFF6747F2);
  static const Color accentSoft = Color(0xFFF1ECFF);
  static const Color rose = Color(0xFFD87995);
  static const Color saffron = Color(0xFFE5A044);
  static const Color shadow = Color(0xFF3A2E46);
}

class OnboardingPageShell extends StatelessWidget {
  const OnboardingPageShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.pageGutter),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return OnboardingBackground(
      child: SafeArea(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class OnboardingBackground extends StatelessWidget {
  const OnboardingBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            OnboardingPalette.backgroundTop,
            OnboardingPalette.backgroundBottom,
          ],
        ),
      ),
      child: SizedBox.expand(child: child),
    );
  }
}
