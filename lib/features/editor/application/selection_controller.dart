import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/core/selection_state.dart';

/// Mobile selection mode.
///
///   * [single] — the default. Tap replaces the selection. Tap-cycling
///     through overlapping layers is enabled.
///   * [multi] — entered explicitly via long-press on the canvas. Tap
///     toggles a layer in/out of the selection. Tap on empty canvas
///     exits the mode and clears the selection. Tap-cycling is
///     suppressed (cycling + toggle would conflict).
///
/// The mode is intentionally NOT part of [SelectionState] (which models
/// only the set of selected ids) — it is a UX-modal flag and so lives
/// alongside, exposed via [selectionModeProvider]. Every existing call
/// site that reads selection ids is unchanged.
enum SelectionMode { single, multi }

class SelectionModeController extends Notifier<SelectionMode> {
  @override
  SelectionMode build() => SelectionMode.single;

  /// Enter multi-select mode. Idempotent.
  void enterMulti() {
    if (state == SelectionMode.multi) return;
    state = SelectionMode.multi;
  }

  /// Exit multi-select mode. Idempotent. Does NOT clear the selection
  /// itself — callers decide whether to combine the two (e.g. tap on
  /// empty canvas exits *and* clears).
  void exitMulti() {
    if (state == SelectionMode.single) return;
    state = SelectionMode.single;
  }
}

final selectionModeProvider =
    NotifierProvider<SelectionModeController, SelectionMode>(
  SelectionModeController.new,
);

class SelectionController extends Notifier<SelectionState> {
  @override
  SelectionState build() => SelectionState.empty;

  /// Plain (non-additive) selection. Replaces the entire selection with
  /// a single layer id. This is the path used by single-tap / single-
  /// click on the canvas and by the layers panel.
  void select(String id) {
    if (state.selectedIds.length == 1 && state.selectedId == id) return;
    state = state.select(id);
  }

  /// Additive selection: add [id] to the current selection and make it
  /// the primary. Used by Cmd/Ctrl-tap and Shift-tap. No-op when [id]
  /// is already primary; otherwise either promotes (if already
  /// selected) or adds.
  void add(String id) {
    if (state.selectedId == id) return;
    state = state.add(id);
  }

  /// Toggle [id] in the selection. Removes it when present, otherwise
  /// adds it (and makes it primary). The standard binding for
  /// Cmd/Ctrl-tap on a layer.
  void toggle(String id) {
    state = state.toggle(id);
  }

  /// Replace the selection with [ids] verbatim (last unique id becomes
  /// primary).
  void selectMany(Iterable<String> ids) {
    final next = state.replaceWith(ids);
    if (next == state) return;
    state = next;
  }

  void clear() {
    if (!state.hasSelection) return;
    state = state.clear();
  }
}

final selectionControllerProvider =
    NotifierProvider<SelectionController, SelectionState>(
  SelectionController.new,
);
