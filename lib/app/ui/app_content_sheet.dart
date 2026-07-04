import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';

/// The "rising sheet" (design doc §4) — a `surface` container with
/// rounded top corners and one soft top shadow lifting it off
/// whatever sits above (a colour hero, another sheet, …). This is
/// the seed that retires the app's parallel one-off overflow-sheet
/// implementations; reuse it for every bottom-sheet/panel that needs
/// the same "content rising off a surface" read, starting with the
/// welcome screen.
///
/// Deliberately no side/bottom radius and no elevation beyond the one
/// shadow — design doc §3: "mostly flat, colour blocks do the work."
class AppContentSheet extends StatelessWidget {
  const AppContentSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadii.sheetTop),
          topRight: Radius.circular(AppRadii.sheetTop),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.textPrimary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
