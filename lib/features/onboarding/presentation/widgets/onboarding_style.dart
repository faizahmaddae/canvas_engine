import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/warm_palette.dart';

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
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            palette.backgroundTop,
            palette.backgroundBottom,
          ],
        ),
      ),
      child: SizedBox.expand(child: child),
    );
  }
}
