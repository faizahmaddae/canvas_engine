import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` while the Add Text composer bottom sheet is on screen.
///
/// The composer is the very first moment a user types new text — it
/// must feel like a focused, single-purpose surface. While it's open
/// the canvas suppresses chrome that would compete with the input
/// (selection handles, transform HUD, floating contextual toolbars,
/// quick-action pill). The sheet's modal scrim handles the dim;
/// this flag handles the chrome.
///
/// Toggled by `EditorScreen._startTextInputFlow` around the
/// `showTextInputFlowSheet` call. Read by `EditorCanvas` to gate
/// overlay rendering. Intentionally a tiny standalone notifier so
/// no controller surface area changes for a pure UX-polish flag.
class AddTextComposerOpenController extends Notifier<bool> {
  @override
  bool build() => false;

  void setOpen(bool open) {
    if (state == open) return;
    state = open;
  }
}

final addTextComposerOpenProvider =
    NotifierProvider<AddTextComposerOpenController, bool>(
      AddTextComposerOpenController.new,
    );

/// `true` while the EDIT-text flow sheet is on screen
/// (`showEditTextLayerFlow`). Deliberately a SEPARATE flag from
/// [addTextComposerOpenProvider]: the composer flag also drives
/// mode resolution and canvas-chrome suppression, and the edit flow
/// must not inherit those side effects. The session registry
/// (contract §6) unions both, so compose AND edit count as open
/// text sessions.
class TextEditFlowOpenController extends Notifier<bool> {
  @override
  bool build() => false;

  void setOpen(bool open) {
    if (state == open) return;
    state = open;
  }
}

final textEditFlowOpenProvider =
    NotifierProvider<TextEditFlowOpenController, bool>(
      TextEditFlowOpenController.new,
    );
