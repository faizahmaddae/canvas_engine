import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Muted top skip/dismiss action (design doc §4) — low-emphasis
/// text button in [AppTokens.textMuted].
class SkipTextButton extends StatelessWidget {
  const SkipTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppTokens.of(context).textMuted,
      ),
      child: Text(label),
    );
  }
}
