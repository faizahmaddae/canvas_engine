import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/modules/text/text_layer.dart';

/// Shared picker UI for [TextResizeMode].
///
/// Both the Layout sheet (deprecated location) and the floating-bar
/// overflow / more menu (canonical location) call into this so the
/// two surfaces never drift apart visually or behaviourally.
///
/// The dialog returns the picked mode, or `null` if cancelled. Tapping
/// a row commits the choice immediately and dismisses — there is no
/// extra confirm step. The caller is responsible for actually applying
/// the mode (so the picker stays decoupled from the controller layer).
Future<TextResizeMode?> pickTextResizeMode(
  BuildContext context,
  TextResizeMode current,
) {
  return showDialog<TextResizeMode>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;

      Widget tile(
        TextResizeMode mode,
        String title,
        String subtitle,
        IconData icon,
      ) {
        final selected = mode == current;
        return Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              // Light haptic on selection — matches the rest of the
              // editor's structural-action haptics.
              HapticFeedback.selectionClick().catchError((_) {});
              Navigator.of(ctx).pop(mode);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: selected ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
        title: Text(ctx.l10n.resizeBehaviorTitle),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile(
              TextResizeMode.scaleText,
              ctx.l10n.scaleTextTitle,
              ctx.l10n.scaleTextSubtitle,
              Icons.zoom_out_map_rounded,
            ),
            const SizedBox(height: 4),
            tile(
              TextResizeMode.resizeBox,
              ctx.l10n.resizeBoxTitle,
              ctx.l10n.resizeBoxSubtitle,
              Icons.crop_landscape_rounded,
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

String localizedTextResizeModeLabel(BuildContext context, TextResizeMode mode) {
  switch (mode) {
    case TextResizeMode.scaleText:
      return context.l10n.scaleTextSummary;
    case TextResizeMode.resizeBox:
      return context.l10n.resizeBoxSummary;
  }
}

/// Short, user-facing label for [mode] — used in list-tile subtitles.
String textResizeModeLabel(TextResizeMode mode) {
  switch (mode) {
    case TextResizeMode.scaleText:
      return 'Scale text — corner drag scales the whole text';
    case TextResizeMode.resizeBox:
      return 'Resize box — corner drag changes the wrap width';
  }
}

/// Glyph paired with [mode] in summary rows.
IconData textResizeModeIcon(TextResizeMode mode) {
  switch (mode) {
    case TextResizeMode.scaleText:
      return Icons.zoom_out_map_rounded;
    case TextResizeMode.resizeBox:
      return Icons.crop_landscape_rounded;
  }
}
