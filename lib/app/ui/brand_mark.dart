import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// App identity mark (design doc §4) — a placeholder glyph for now,
/// replace the icon when a real logo mark exists.
///
/// Built to read on a `brandStrong` colour hero (its primary
/// placement, per §5): a translucent [AppTokens.onBrand] halo behind
/// an [AppTokens.onBrand] glyph. `onBrand` is fixed white in both
/// light and dark (design doc §1), so this stays legible on the hero
/// in either theme without branching on brightness itself.
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
