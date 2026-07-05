import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Small saffron diamond identity mark (design direction v2: "a small
/// saffron diamond mark", restrained) — a rotated square, no glyph,
/// no halo. Shared by the welcome screen's top row and Home's
/// wordmark header.
class SaffronDiamond extends StatelessWidget {
  const SaffronDiamond({super.key, this.size = 12});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Optical margin so the rotated square's point doesn't kiss
      // neighbouring content.
      padding: const EdgeInsets.all(6),
      child: Transform.rotate(
        angle: 0.785398, // 45° — square reads as a diamond
        child: Container(
          width: size,
          height: size,
          color: AppTokens.of(context).accent,
        ),
      ),
    );
  }
}
