import 'package:flutter/material.dart';

/// Visual primitives for the Home surface.
///
/// The Home page intentionally shares the softened editorial feel of
/// onboarding while still leaning on the app-wide Material theme for
/// typography and interaction states.
abstract final class HomePalette {
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

class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [HomePalette.backgroundTop, HomePalette.backgroundBottom],
        ),
      ),
      child: child,
    );
  }
}
