import 'package:flutter/material.dart';

import '../../../../core/utils/haptics.dart';

/// Reusable "Done" pill chrome.
///
/// Visual grammar extracted from the original `_ModeExitPill` so
/// every mode — current and future — exits through the same
/// affordance with identical look-and-feel. Owns no observation
/// logic: callers decide *when* to show it and *what* to do on tap.
///
/// Phase 1 plugs this into `_ModeExitPill` (paint + text + any
/// selection). Later phases swap the per-controller observation for
/// a single `ToolbarController.exitMode()` call without re-skinning.
class ModeDoneButton extends StatelessWidget {
  const ModeDoneButton({
    super.key,
    required this.onPressed,
    this.label = 'Done',
    this.icon = Icons.check_rounded,
  });

  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          EditorHaptics.tap();
          onPressed();
        },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
