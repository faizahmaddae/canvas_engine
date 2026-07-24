import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../../presentation/widgets/editor_modal_sheet.dart';
import '../application/paint_tool_controller.dart';
import 'paint_size_body.dart';

/// Bottom sheet for adjusting stroke size + fill — opened from the
/// "Size" entry in the paint mode toolbar and from the paint floating
/// toolbar's stroke pill.
///
/// Live preview: slider ticks stage on the live overlay (contract
/// §2, tb2 3/16) so the canvas reflects the new value while the
/// sheet is open, and the gesture end commits ONE undoable command.
/// When a paint layer is selected the edits target THAT layer;
/// otherwise they update the session defaults used for the next
/// drawn stroke (session-only — no document writes).
Future<void> showPaintSizeSheet(BuildContext context, WidgetRef ref) {
  // Barrier NONE (contract §9): this sheet advertises live preview —
  // the stroke width lands on the canvas while dragging — so the old
  // default scrim contradicted its whole point (audit:
  // dimmed-live-preview). The shared host supplies card + handle.
  return showEditorSheet<void>(
    context,
    barrier: EditorSheetBarrier.none,
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
    // We watch the MERGED view + selection so the body tracks the
    // overlay preview `previewStrokeWidth` stages every frame
    // during a drag (the committed doc stays frozen mid-drag by
    // design — contract §2).
    final selection = ref.watch(selectionControllerProvider);
    final doc = ref.watch(renderedDocumentProvider);
    final selectedLayer = selection.hasSelection
        ? doc.layerById(selection.selectedId!)
        : null;
    final paintLayer = selectedLayer is PaintLayer ? selectedLayer : null;

    final strokeWidth = paintLayer?.strokeWidth ?? session.strokeWidth;
    final strokeColor = paintLayer?.strokeColor ?? session.strokeColor;
    final fillEnabled = paintLayer != null
        ? paintLayer.fillColor != null
        : session.fillColor != null;

    // Chrome (card, handle, safe area) comes from the shared modal
    // host (tb2 8/16); this body owns padding + its scroll guard.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      // Scroll guard: the modal's height is bounded (short landscape
      // phones, large text scale), but this Column is min-sized and
      // its children are fixed-height. Without a scroll view the
      // content overflows at short heights — mirrors the
      // SingleChildScrollView DockSheetChrome wraps around the inline
      // rendering of the same PaintSizeBody.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reuse the inline panel verbatim. One source of truth
            // for hero preview, presets, precision disclosure,
            // haptics, and pointer-cancel handling — the modal and
            // dock cannot drift apart.
            PaintSizeBody(
              value: strokeWidth,
              color: strokeColor,
              onChange: controller.previewStrokeWidth,
              onChangeEnd: controller.commitStrokeWidth,
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
