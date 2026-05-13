import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/core/editor_document.dart';
import '../engine/core/editor_layer.dart';
import 'document_controller.dart';

/// Mid-gesture overlay applied on top of the committed [EditorDocument].
///
/// The point of this type is to keep 60-fps preview state OUT of
/// [documentControllerProvider]. Without it, every slider tick / drag
/// frame mutates the canonical document and rebuilds every widget that
/// watches it (layers panel, thumbnails, undo rail, …) — even though
/// none of them actually need to react until the gesture commits.
///
/// Three independent kinds of override are tracked so the overlay can
/// express every shape of in-flight edit currently in the codebase:
///
/// * [replacements] — layer-id → in-flight replacement of an existing
///   layer (slider drag, style preview, transform preview).
/// * [additions] — layers staged by an in-flight session that have not
///   yet been committed (Add Text composer's preview layer).
/// * [removals] — layer ids that the in-flight session wants hidden
///   from the merged view. Reserved for future "live delete preview"
///   flows; included now so the merge fold has a single uniform shape.
///
/// The overlay is in-memory only — never serialized, never crash-safe.
/// If the app dies mid-gesture the next launch sees only the committed
/// document, which is the correct outcome.
@immutable
class LiveOverlay {
  const LiveOverlay({
    this.replacements = const {},
    this.additions = const [],
    this.removals = const {},
  });

  /// Layer-id → in-flight replacement layer. Replacements only apply
  /// when the id exists in the committed document; otherwise they are
  /// silently ignored on merge so a stale replacement against a
  /// just-deleted layer does not resurrect a phantom.
  final Map<String, EditorLayer> replacements;

  /// Layers that exist only in the live overlay. Appended to the
  /// committed layer list during merge in insertion order, so an
  /// addition stacks on top of every committed layer (matches the
  /// historical behaviour of `liveReplace(doc.addLayer(...))`).
  final List<EditorLayer> additions;

  /// Layer ids the live session wants suppressed from rendering.
  /// Applied last in the merge fold so a removal trumps a stale
  /// replacement of the same id within the same overlay.
  final Set<String> removals;

  static const LiveOverlay empty = LiveOverlay();

  bool get isEmpty =>
      replacements.isEmpty && additions.isEmpty && removals.isEmpty;

  /// Apply this overlay to [doc] and return the merged document.
  /// Returns [doc] unchanged when the overlay is empty (Riverpod
  /// listeners that compare by identity therefore skip a rebuild).
  EditorDocument applyTo(EditorDocument doc) {
    if (isEmpty) return doc;
    final merged = <EditorLayer>[];
    for (final layer in doc.layers) {
      if (removals.contains(layer.id)) continue;
      merged.add(replacements[layer.id] ?? layer);
    }
    if (additions.isNotEmpty) merged.addAll(additions);
    return doc.copyWith(layers: merged);
  }
}

/// Notifier owning the in-flight [LiveOverlay] for the current
/// editing session. Mutations are fire-and-forget: they update the
/// overlay's identity (so [renderedDocumentProvider] rebuilds) without
/// touching [documentControllerProvider].
///
/// Every public mutator returns synchronously and allocates only the
/// minimum needed to publish a new overlay (single-entry Map, single-
/// element List, etc.) — drag handlers can call them at 60 fps without
/// noticeable allocation pressure.
class LiveOverlayController extends Notifier<LiveOverlay> {
  @override
  LiveOverlay build() => LiveOverlay.empty;

  /// Insert or replace an in-flight layer override. Used by slider
  /// drags / style previews where the COMMITTED layer should remain
  /// untouched until release. Calling with a layer whose id is not in
  /// the committed document silently no-ops on merge — ok for fire-
  /// and-forget gesture handlers.
  void replaceLayer(EditorLayer layer) {
    final next = Map<String, EditorLayer>.of(state.replacements);
    next[layer.id] = layer;
    state = LiveOverlay(
      replacements: next,
      additions: state.additions,
      removals: state.removals,
    );
  }

  /// Stage [layer] as an in-flight addition. Used by the Add Text
  /// composer to make its preview layer visible on the canvas before
  /// the user confirms. Caller is responsible for picking a unique id
  /// (existing flow already assigns a uuid at session start).
  void addLayer(EditorLayer layer) {
    state = LiveOverlay(
      replacements: state.replacements,
      additions: [...state.additions, layer],
      removals: state.removals,
    );
  }

  /// Update an already-staged addition in place, identified by id.
  /// No-op when no addition with that id exists. Used by live add
  /// sessions (e.g. Add Text) where the staged layer's content /
  /// style / transform changes per keystroke or per slider tick — the
  /// preview must mutate the same staged entry rather than appending
  /// duplicates each frame.
  void updateAddedLayer(EditorLayer layer) {
    final idx = state.additions.indexWhere((l) => l.id == layer.id);
    if (idx < 0) return;
    final next = List<EditorLayer>.of(state.additions);
    next[idx] = layer;
    state = LiveOverlay(
      replacements: state.replacements,
      additions: next,
      removals: state.removals,
    );
  }

  /// Hide a committed layer from the merged view for the duration of
  /// the in-flight session. Currently unused by production callers;
  /// kept so the public API of `LiveOverlay` is uniform across all
  /// three override kinds.
  void removeLayer(String id) {
    final next = Set<String>.of(state.removals)..add(id);
    state = LiveOverlay(
      replacements: state.replacements,
      additions: state.additions,
      removals: next,
    );
  }

  /// Drop every in-flight override and return to [LiveOverlay.empty].
  /// Called on commit (the just-pushed undo entry now reflects the
  /// edit) and on cancel (the session's intent is discarded).
  void clear() {
    if (state.isEmpty) return;
    state = LiveOverlay.empty;
  }
}

final liveOverlayProvider =
    NotifierProvider<LiveOverlayController, LiveOverlay>(
  LiveOverlayController.new,
);

/// Merged view: the committed [EditorDocument] with the in-flight
/// [LiveOverlay] applied on top. This is what the canvas, the
/// selection chrome, and any widget that needs to reflect mid-gesture
/// previews should watch.
///
/// Widgets that should ONLY react to committed changes (layers panel,
/// thumbnails, undo rail, autosave) MUST keep watching
/// [documentControllerProvider] / [documentCommitVersionProvider]
/// instead. The whole point of the split is that this provider is
/// allowed to fire 60 times a second; the committed one is not.
final renderedDocumentProvider = Provider<EditorDocument>((ref) {
  final committed = ref.watch(documentControllerProvider);
  final overlay = ref.watch(liveOverlayProvider);
  return overlay.applyTo(committed);
});
