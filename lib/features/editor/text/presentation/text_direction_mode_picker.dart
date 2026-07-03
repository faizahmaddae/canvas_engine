import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/modules/text/text_layer.dart';

/// Shared picker UI for a text layer's base paragraph direction.
///
/// The dialog returns the picked mode, or `null` if cancelled. Tapping
/// a row commits immediately and dismisses, matching the resize-mode
/// picker used from the same More sheet.
Future<TextDirectionMode?> pickTextDirectionMode(
  BuildContext context,
  TextDirectionMode current,
) {
  return showDialog<TextDirectionMode>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;

      Widget tile(TextDirectionMode mode, String title, IconData icon) {
        final selected = mode == current;
        return Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              HapticFeedback.selectionClick().catchError((_) {});
              Navigator.of(ctx).pop(mode);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_rounded, color: scheme.primary),
                ],
              ),
            ),
          ),
        );
      }

      return AlertDialog(
        title: Text(ctx.l10n.textDirectionTitle),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile(
              TextDirectionMode.auto,
              ctx.l10n.textDirectionAutoTitle,
              Icons.swap_horiz_rounded,
            ),
            const SizedBox(height: 4),
            tile(
              TextDirectionMode.rtl,
              ctx.l10n.textDirectionRtlTitle,
              Icons.format_textdirection_r_to_l_rounded,
            ),
            const SizedBox(height: 4),
            tile(
              TextDirectionMode.ltr,
              ctx.l10n.textDirectionLtrTitle,
              Icons.format_textdirection_l_to_r_rounded,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.cancelAction),
          ),
        ],
      );
    },
  );
}

String localizedTextDirectionModeLabel(
  BuildContext context,
  TextDirectionMode mode,
) {
  switch (mode) {
    case TextDirectionMode.auto:
      return context.l10n.textDirectionAutoTitle;
    case TextDirectionMode.rtl:
      return context.l10n.textDirectionRtlTitle;
    case TextDirectionMode.ltr:
      return context.l10n.textDirectionLtrTitle;
  }
}

IconData textDirectionModeIcon(TextDirectionMode mode) {
  switch (mode) {
    case TextDirectionMode.auto:
      return Icons.swap_horiz_rounded;
    case TextDirectionMode.rtl:
      return Icons.format_textdirection_r_to_l_rounded;
    case TextDirectionMode.ltr:
      return Icons.format_textdirection_l_to_r_rounded;
  }
}
