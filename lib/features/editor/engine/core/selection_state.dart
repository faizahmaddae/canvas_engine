import 'package:flutter/foundation.dart';

/// Which part of the selected layer the user is currently grabbing.
///
/// Kept as a small, serializable enum so gesture code doesn't need to know
/// about UI widgets.
enum InteractionHandle {
  body,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,

  /// Dedicated rotation knob — rendered as a stemmed handle above the
  /// selection's top-centre (tb3 6/7, decision D-a); previously it
  /// occupied the top-right corner, which now resizes like the other
  /// three. Rotation math is position-agnostic: the engine captures
  /// the pointer's start angle about the layer centre and applies
  /// pure deltas, so relocating the handle needed no math changes.
  rotate,

  /// Multi-touch gesture (pinch / rotate / drag with 1–2 fingers). Used for
  /// native touch interaction; drives the same engine math as the discrete
  /// handles but interprets scale + rotation deltas together.
  gesture,
}

/// Selection state.
///
/// Internally stores an **insertion-ordered** list of layer ids. The
/// last id is the *primary* selection — the layer that selection-driven
/// UI (transform handles, HUD, properties panel) operates on. The order
/// matters for additive selection semantics: `Cmd+tap` on a new layer
/// makes it primary; Cmd+tap on an already-selected layer removes it
/// and the previous-most-recent becomes primary again.
///
/// Single-selection call sites (the vast majority today) keep working
/// transparently: [select] replaces the whole selection with one id;
/// [selectedId] returns that id; [hasSelection] is `true`.
@immutable
class SelectionState {
  /// Internal: callers should use [select], [add], [toggle], [clear],
  /// [replaceWith], or one of the named constructors.
  const SelectionState._(this._ids);

  /// Single-selection convenience constructor — preserves the previous
  /// public API so call sites that pass `SelectionState(selectedId: x)`
  /// still compile.
  SelectionState({String? selectedId})
    : _ids = selectedId == null ? const <String>[] : <String>[selectedId];

  /// Insertion-ordered list of selected ids. The LAST entry is the
  /// primary selection. Stored as a `List` (not a `Set`) so order is
  /// preserved deterministically and equality is cheap; uniqueness is
  /// enforced by the mutators below.
  final List<String> _ids;

  static const empty = SelectionState._(<String>[]);

  /// True when at least one layer is selected.
  bool get hasSelection => _ids.isNotEmpty;

  /// The *primary* selected id (most-recently-added), or `null` when
  /// nothing is selected. Backwards-compatible with the previous
  /// single-selection API — every existing call site that reads
  /// `selectedId` keeps working.
  String? get selectedId => _ids.isEmpty ? null : _ids.last;

  /// All selected layer ids in insertion order (oldest first, primary
  /// last). Returned as an unmodifiable view so callers can't mutate
  /// the immutable state in place.
  List<String> get selectedIds => List<String>.unmodifiable(_ids);

  /// Number of selected layers.
  int get count => _ids.length;

  /// True when [id] is part of the current selection (primary or not).
  bool contains(String id) => _ids.contains(id);

  // --- mutators (return new instances) ---

  /// Replace the entire selection with a single [id]. This is the
  /// behaviour the controller uses for plain (non-additive) taps and is
  /// what every existing call site maps to.
  SelectionState select(String id) => SelectionState._(<String>[id]);

  /// Add [id] to the selection and make it primary. If [id] is already
  /// selected it is moved to the primary slot (end of the list)
  /// without duplication.
  SelectionState add(String id) {
    final next = <String>[
      for (final existing in _ids)
        if (existing != id) existing,
      id,
    ];
    return SelectionState._(next);
  }

  /// Remove [id] from the selection. If [id] was primary, the
  /// previous-most-recent id becomes primary. No-op if [id] is not
  /// selected.
  SelectionState remove(String id) {
    if (!_ids.contains(id)) return this;
    return SelectionState._(<String>[
      for (final existing in _ids)
        if (existing != id) existing,
    ]);
  }

  /// Toggle [id]: if selected, remove; otherwise add (and make
  /// primary). Use this for additive-tap interactions
  /// (Cmd/Ctrl+click, Shift+tap).
  SelectionState toggle(String id) => contains(id) ? remove(id) : add(id);

  /// Replace the selection with [ids] verbatim (deduplicated, order
  /// preserved; the last unique id becomes primary).
  SelectionState replaceWith(Iterable<String> ids) {
    final seen = <String>{};
    final next = <String>[
      for (final id in ids)
        if (seen.add(id)) id,
    ];
    return SelectionState._(next);
  }

  /// Empty selection.
  SelectionState clear() => empty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SelectionState) return false;
    if (other._ids.length != _ids.length) return false;
    for (var i = 0; i < _ids.length; i++) {
      if (other._ids[i] != _ids[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_ids);
}
