import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../canvas/application/canvas_tool_controller.dart';
import '../crop/application/crop_controller.dart';
import '../image/application/image_tool_controller.dart';
import '../paint/application/paint_tool_controller.dart';
import '../shape/application/shape_tool_controller.dart';
import '../sticker/application/sticker_tool_controller.dart';
import '../text/application/add_text_composer_state.dart';
import '../text/application/text_tool_controller.dart';
import 'context_toolbar_controller.dart';
import 'mask_edit_controller.dart';

/// True while any dock panel, sub-tool sheet, context panel, the
/// add-text composer, or a full-canvas modal session (crop / mask
/// edit) owns the bottom of the screen — the ONE signal floating
/// canvas chrome (quick capsule, floating bars, quick-actions pill)
/// uses to get out of the way.
///
/// Before this provider each floating-chrome builder enumerated the
/// other tools' providers by hand, and the five copies had already
/// drifted: the paint bar ignored the context panel, the quick pill
/// ignored the canvas-tool panel, and every new tool had to remember
/// to patch up to five guard sites (audit:
/// god-widget-and-copy-pasted-chrome-guards). The union here is
/// deliberately the SUPERSET of the old guards — floating chrome
/// hides whenever any panel owns the dock, uniformly.
final canvasChromeSuppressedProvider = Provider<bool>((ref) {
  final textSheet = ref.watch(
    textToolControllerProvider.select((s) => s.openSheet != null),
  );
  final paintSlot = ref.watch(
    paintToolControllerProvider.select((s) => s.openSlot != null),
  );
  final imageSlot = ref.watch(
    imageToolControllerProvider.select((s) => s.openSlot != null),
  );
  final shapeSlot = ref.watch(
    shapeToolControllerProvider.select((s) => s.openSlot != null),
  );
  final stickerSlot = ref.watch(
    stickerToolControllerProvider.select((s) => s.openSlot != null),
  );
  final canvasPanel = ref.watch(
    canvasToolControllerProvider.select((s) => s.panelOpen),
  );
  final contextPanel = ref.watch(contextToolbarControllerProvider) != null;
  final composer = ref.watch(addTextComposerOpenProvider);
  final cropActive = ref.watch(cropControllerProvider.select((s) => s.active));
  final maskActive = ref.watch(
    maskEditControllerProvider.select((s) => s.active),
  );
  return textSheet ||
      paintSlot ||
      imageSlot ||
      shapeSlot ||
      stickerSlot ||
      canvasPanel ||
      contextPanel ||
      composer ||
      cropActive ||
      maskActive;
});
