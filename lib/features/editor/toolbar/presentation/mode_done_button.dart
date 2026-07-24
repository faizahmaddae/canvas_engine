import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../presentation/widgets/editor_breakpoints.dart';

/// Reusable "Done" pill chrome.
///
/// Visual grammar extracted from the original `_ModeExitPill` so
/// every mode — current and future — exits through the same
/// affordance with identical look-and-feel. Owns no observation
/// logic: callers decide *when* to show it and *what* to do on tap.
///
/// `_ModeExitPill` (paint + text + any selection) renders through
/// this; the mode-controller work routes its exit action here
/// without re-skinning.
class ModeDoneButton extends StatelessWidget {
  const ModeDoneButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon = Icons.check_rounded,
  });

  final VoidCallback onPressed;
  final String? label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Hit box ≥ kMinHitTarget while the PAINTED pill stays 36dp
    // (tb2 a11y pass): the InkWell wraps a 44dp-min transparent box
    // with the visual pill centred inside. Mount sites compensate
    // the 4dp halo (see the editor screen's `top: 4`) so the
    // painted position is pixel-identical.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          EditorHaptics.tap();
          onPressed();
        },
        child: Container(
          constraints: const BoxConstraints(
            minWidth: kMinHitTarget,
            minHeight: kMinHitTarget,
          ),
          alignment: Alignment.center,
          child: _pill(tokens, scheme, context),
        ),
      ),
    );
  }

  /// The painted 36dp pill — visually identical to the pre-a11y
  /// button; only the surrounding hit box grew.
  Widget _pill(AppTokens tokens, ColorScheme scheme, BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.border),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tokens.accent),
          const SizedBox(width: 6),
          Text(
            label ?? context.l10n.doneAction,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
