import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// App identity mark (design doc §4) — a placeholder glyph for now,
/// replace the icon when a real logo mark exists.
///
/// Built to read on a [AppTokens.brand]-filled surface: a translucent
/// [AppTokens.onBrand] halo behind an [AppTokens.onBrand] glyph.
/// Under the v2 palette `onBrand` tracks `brand`'s ink/cream swap
/// (paper-on-ink in light, ink-on-cream in dark), so the mark stays
/// legible on a brand fill in either mode without branching on
/// brightness itself.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tokens.onBrand.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.auto_awesome_mosaic_rounded,
        color: tokens.onBrand,
        size: size * 0.55,
      ),
    );
  }
}
