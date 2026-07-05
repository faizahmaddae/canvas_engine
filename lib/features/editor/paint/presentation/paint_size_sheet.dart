import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../application/paint_tool_controller.dart';
import 'paint_size_body.dart';

/// Bottom sheet for adjusting stroke size + fill — opened from the
/// "Size" entry in the paint mode toolbar and from the paint floating
/// toolbar's stroke pill.
///
/// Live mutation: changing the slider or toggling fill mutates state
/// immediately so the canvas reflects the new value while the sheet is
/// open. When a paint layer is selected the edits target THAT layer
/// (single coalesced undo entry per drag, courtesy of
/// [UpdatePaintStyleCommand.mergeWith]); otherwise they update the
/// session defaults used for the next drawn stroke.
Future<void> showPaintSizeSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PaintSizeSheet(),
  );
}

class _PaintSizeSheet extends ConsumerWidget {
  const _PaintSizeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(paintToolControllerProvider);
    final controller = ref.read(paintToolControllerProvider.notifier);
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);

    // When a paint layer is selected, the sheet edits THAT layer and
    // its current values must drive the body — otherwise the user
    // opens the sheet for a thin red stroke and sees a fat blue
    // session-default. Falling back to the session when nothing is
    // selected keeps the in-tool drawing flow working.
    //
    // We watch the document + selection so the body tracks the
    // layer mutation `setStrokeWidth` pushes every frame during a
    // drag.
    final selection = ref.watch(selectionControllerProvider);
    final doc = ref.watch(documentControllerProvider);
    final selectedLayer = selection.hasSelection
        ? doc.layerById(selection.selectedId!)
        : null;
    final paintLayer = selectedLayer is PaintLayer ? selectedLayer : null;

    final strokeWidth = paintLayer?.strokeWidth ?? session.strokeWidth;
    final strokeColor = paintLayer?.strokeColor ?? session.strokeColor;
    // PaintLayer geometry doesn't (yet) carry its own dash pattern;
    // use the session pattern so the hero preview still reflects the
    // user's current dash style.
    final dashPattern = session.dashPattern;
    final fillEnabled = paintLayer != null
        ? paintLayer.fillColor != null
        : session.fillColor != null;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.border.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Reuse the inline panel verbatim. One source of truth
            // for hero preview, presets, precision disclosure,
            // haptics, and pointer-cancel handling — the modal and
            // dock cannot drift apart.
            PaintSizeBody(
              value: strokeWidth,
              color: strokeColor,
              dashPattern: dashPattern,
              onChange: controller.setStrokeWidth,
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Fill stays a simple row in the modal so quick toggles
            // from the floating toolbar don't require diving into
            // the dedicated Fill panel. Only the on/off affordance
            // is here — colour / preset choices live in `_PaintFillBody`.
            Row(
              children: [
                Icon(
                  Icons.format_color_fill_rounded,
                  size: 22,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Fill shapes',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: fillEnabled,
                  onChanged: controller.setFillEnabled,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
