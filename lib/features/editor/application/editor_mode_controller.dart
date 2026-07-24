import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/modules/image/image_layer.dart';
import '../engine/modules/paint/paint_layer.dart';
import '../engine/modules/shape/shape_layer.dart';
import '../engine/modules/text/text_layer.dart';
import '../paint/application/paint_tool_controller.dart';
import '../text/application/add_text_composer_state.dart';
import 'document_controller.dart';
import 'selection_controller.dart';

/// Which family of bottom-dock chrome owns the editor right now.
///
/// [idle] is the main add-tools strip. A selected [PaintLayer]
/// deliberately maps to [idle] for now — committed strokes have no
/// dock mode yet and keep the floating bar (roadmap tb4 gives paint
/// a real mode; when it does, only this mapping changes).
enum EditorToolMode { idle, text, image, shape, sticker, paint, multi }

/// THE single derivation of the editor's dock mode (roadmap tb1
/// 7/17). Before this provider, the paint→text→multi→sticker→image→
/// shape→main priority ladder was hand-rolled three times inside
/// editor_screen.dart with per-flag negation chains, and text mode
/// was driven by a sticky `panelOpen` flag — the root of three
/// verified bug families: selecting a non-text layer left the dock
/// on a fully-disabled text strip, drawer selections showed the
/// wrong toolbar while a mode panel was open, and undoing the
/// selected text layer's add stranded the user in dead chrome.
///
/// Derivation rules, in priority order:
///  1. Explicit sessions win: paint mode while its session is armed;
///     text while the add-composer stages a layer that exists only
///     on the live overlay (edit sessions need no flag — their layer
///     is committed, so rule 3 already resolves to text).
///  2. Group selection: more than one actionable (non-protected,
///     still-existing) selected layer → multi. Matches the previous
///     count-based `multiSelected` guard exactly.
///  3. Selected layer type, read from the COMMITTED document —
///     sticky tool flags no longer outrank what the user actually
///     has selected. Selection change wins over open panels; the
///     per-tool `openSlot`/`openSheet` values only choose WHICH
///     panel shows inside the mode that owns the dock.
///  4. Nothing selected → idle.
final editorToolModeProvider = Provider<EditorToolMode>((ref) {
  // 1 — explicit sessions.
  final paintOpen = ref.watch(
    paintToolControllerProvider.select((s) => s.panelOpen),
  );
  if (paintOpen) return EditorToolMode.paint;
  final composing = ref.watch(addTextComposerOpenProvider);
  if (composing) return EditorToolMode.text;

  final selection = ref.watch(selectionControllerProvider);
  if (!selection.hasSelection) return EditorToolMode.idle;
  final doc = ref.watch(documentControllerProvider);

  // 2 — group selection (actionable = exists and not the protected
  // base photo, mirroring _selectedLayersForActions).
  var actionable = 0;
  for (final id in selection.selectedIds) {
    final layer = doc.layerById(id);
    if (layer == null || doc.isProtectedBasePhoto(id)) continue;
    actionable++;
  }
  if (actionable > 1) return EditorToolMode.multi;

  // 3 — selected layer type. Emoji stickers are TextLayers but get
  // the sticker strip: font/layout controls don't apply to a single
  // glyph.
  final layer = doc.layerById(selection.selectedId!);
  return switch (layer) {
    TextLayer l when l.isSticker => EditorToolMode.sticker,
    TextLayer _ => EditorToolMode.text,
    ImageLayer _ => EditorToolMode.image,
    ShapeLayer _ => EditorToolMode.shape,
    PaintLayer _ => EditorToolMode.idle,
    _ => EditorToolMode.idle,
  };
});
