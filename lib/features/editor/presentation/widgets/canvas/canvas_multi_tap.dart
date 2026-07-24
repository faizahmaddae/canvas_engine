import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../settings/application/settings_controller.dart';
import '../../../application/document_controller.dart';
import '../../../application/edit_session_registry.dart';
import '../../../application/editing_controller.dart';
import '../../../application/interaction_controller.dart';
import '../../../paint/application/paint_tool_controller.dart';

// ------------------------------------------------------------------
// Multi-finger tap shortcuts (Procreate-style):
//   * 2-finger tap → undo
//   * 3-finger tap → redo
//
// Implemented at the outer Listener so we observe every pointer
// regardless of which deeper recogniser claims it. We disambiguate
// tap from pinch using the standard `kTouchSlop` movement bound and
// a short time window — identical heuristic to a single-finger tap,
// just with a peak-pointer-count check.
//
// Aborted (no undo/redo fired) when:
//   * any pointer moves > kTouchSlop (it's a pan/pinch, not a tap)
//   * peak pointer count exceeds 3
//   * the interaction controller becomes active during the window
//     (an object body recogniser claimed it — that's not a viewport
//     tap, it's an object gesture)
//   * paint or inline-edit mode is active (those modes own the
//     surface entirely)
//   * total duration exceeds [CanvasMultiTapRecognizer._maxDuration]
// ------------------------------------------------------------------

/// Recognises the 2-/3-finger tap shortcuts on the editor canvas.
///
/// Owns nothing but its own bookkeeping: the canvas' outer [Listener]
/// forwards every raw pointer event here, in addition to the raw
/// sequence tracking the gesture router does for claim predicates.
class CanvasMultiTapRecognizer {
  CanvasMultiTapRecognizer(this._ref);

  final WidgetRef _ref;

  /// Maximum total duration from first pointer down to last pointer up
  /// for a multi-finger sequence to count as a tap. Beyond this it is
  /// considered a deliberate gesture (slow drag, rest-fingers, etc.).
  static const Duration _maxDuration = Duration(milliseconds: 250);

  /// Mirror of `kTouchSlop` for our movement check. Centralised here so
  /// the helpers below stay readable.
  static const double _moveSlop = kTouchSlop;

  final Map<int, _MultiTapPointer> _pointers = <int, _MultiTapPointer>{};
  int _peak = 0;
  DateTime? _firstDownAt;
  bool _aborted = false;

  /// Aborts the in-flight multi-tap window without resetting it. The
  /// finalize step still runs on the final pointer-up but does nothing.
  /// Cheaper and safer than clearing mid-sequence.
  void _abort() {
    _aborted = true;
  }

  void onPointerDown(PointerDownEvent e) {
    // A brand-new physical sequence must not inherit an abort
    // latched by a fully-gated previous one: the gates below abort
    // BEFORE registering the pointer, so [_finalize] (the
    // only reset point) never ran for that sequence and the flag
    // stayed true — silently swallowing the first legitimate tap
    // after e.g. a mask session ended (surfaced by the tb2 13/16
    // registry-gate pin).
    if (_pointers.isEmpty && _firstDownAt == null) {
      _aborted = false;
    }
    // Feature flag: the 2-/3-finger tap shortcuts are opt-in. When
    // disabled (the default), we abort the window on every pointer-
    // down so no amount of subsequent lifts can trigger undo/redo.
    // The body / viewport recognisers are unaffected — they receive
    // the same pointers via their own listeners.
    if (!_ref.read(appSettingsProvider).multiFingerUndoRedoEnabled) {
      _abort();
      return;
    }
    // Surface-ownership gates: paint and inline-edit own the canvas
    // entirely; we must not consume their touches with an undo
    // shortcut. These are NOT draft sessions (paint is a live mode,
    // inline edit is the on-canvas caret) so they stay as their own
    // reads rather than folding into the registry below.
    if (_ref.read(paintToolControllerProvider).activeTool != null) {
      _abort();
      return;
    }
    if (_ref.read(editingControllerProvider) != null) {
      _abort();
      return;
    }
    // Session registry (contract §6): while ANY draft session is
    // open the shortcut is inert. Replaces the old mask-only read —
    // mask rides on the live canvas so it was the visible offender,
    // but crop / text compose / edit / export must be equally
    // protected (their modal barriers cover most of the screen, not
    // the edge cases where a pointer still lands on the canvas).
    if (_ref.read(anyDraftSessionOpenProvider)) {
      _abort();
      return;
    }
    // NOTE: we deliberately do NOT abort here when an interaction
    // session is already active. With the active-transform-surface
    // model, the body recogniser eagerly claims pointer-down whenever
    // a layer is selected — so `isActive` becomes true synchronously
    // for every gesture, including legitimate 2-/3-finger taps that
    // the user means as undo/redo. Movement is the real
    // disambiguator: the per-pointer slop check in
    // [onPointerMove] aborts the tap window the moment any
    // finger actually drags, leaving the body session in charge. If
    // no finger moves and the sequence finalises cleanly as a tap,
    // [_finalize] cancels the phantom session before firing
    // the shortcut.
    _pointers[e.pointer] = _MultiTapPointer(e.position);
    _firstDownAt ??= DateTime.now();
    if (_pointers.length > _peak) {
      _peak = _pointers.length;
    }
    // Anything beyond 3 fingers is not a known shortcut — abort early
    // to avoid a 4-finger pinch ever firing redo on lift.
    if (_peak > 3) {
      _abort();
    }
  }

  void onPointerMove(PointerMoveEvent e) {
    final p = _pointers[e.pointer];
    if (p == null) return;
    if ((e.position - p.downPosition).distance > _moveSlop) {
      _abort();
    }
    // Movement is the sole gesture-vs-tap discriminator. We do NOT
    // abort on `interactionController.isActive` here because the body
    // recogniser claims on pointer-down for every selected-layer
    // gesture — doing so would kill the undo/redo shortcut whenever
    // anything is selected. As long as no finger crosses the slop
    // bound, the sequence remains a candidate tap.
  }

  void onPointerUp(PointerUpEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) {
      _finalize();
    }
  }

  void onPointerCancel(PointerCancelEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers.remove(e.pointer);
    _abort();
    if (_pointers.isEmpty) {
      _finalize();
    }
  }

  void _finalize() {
    final firstDown = _firstDownAt;
    final peak = _peak;
    final aborted = _aborted;
    _firstDownAt = null;
    _peak = 0;
    _aborted = false;
    if (aborted || firstDown == null) return;
    if (DateTime.now().difference(firstDown) > _maxDuration) return;
    if (peak != 2 && peak != 3) return;
    final docCtl = _ref.read(documentControllerProvider.notifier);
    final isUndo = peak == 2;
    if (isUndo ? !docCtl.canUndo : !docCtl.canRedo) return;
    // The active-transform-surface body recogniser may have claimed
    // these pointers and started a phantom session on pointer-down.
    // No finger ever moved (we just verified above), so no document
    // mutation has occurred — cancelling cleanly discards the live
    // (== initial) transform without committing. This is what makes
    // the undo/redo shortcut survive the eager-claim policy.
    _ref.read(interactionControllerProvider.notifier).cancel();
    if (isUndo) {
      docCtl.undo();
    } else {
      docCtl.redo();
    }
    HapticFeedback.lightImpact().catchError((_) {});
  }
}

/// One pointer being tracked by the multi-finger tap heuristic. Only
/// stores what we need to disambiguate tap vs drag — no need to keep
/// the live position because we re-derive movement against the down
/// position on every move event.
class _MultiTapPointer {
  _MultiTapPointer(this.downPosition);
  final Offset downPosition;
}
