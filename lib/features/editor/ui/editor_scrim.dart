import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';

/// Canonical editor scrim colour — dims the canvas behind any open
/// panel/sheet so elevated chrome reads as a layer above the work.
///
/// Warm ink (not pure black) in light mode so the dim stays in the
/// paper/ink family; the theme's scrim (black) carries dark mode
/// where a cream-tinted wash would glow instead of receding.
Color editorScrimColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark
      ? Theme.of(context).colorScheme.scrim.withValues(alpha: 0.5)
      : AppTokens.of(context).textPrimary.withValues(alpha: 0.45);
}
