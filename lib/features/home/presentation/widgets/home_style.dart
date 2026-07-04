import 'package:flutter/material.dart';

import '../../../../app/theme/warm_palette.dart';

class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = WarmPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [palette.backgroundTop, palette.backgroundBottom],
        ),
      ),
      child: child,
    );
  }
}
