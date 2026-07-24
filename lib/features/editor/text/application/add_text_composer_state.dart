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
