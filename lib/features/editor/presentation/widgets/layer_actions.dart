import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/layer_state_commands.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/editor_document.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/core/layer_transform.dart';
import '../../engine/serialization/document_codec.dart';

const _uuid = Uuid();

/// Layer-level structural operations (clone / delete / reorder / lock)
/// shared by every UI surface that needs them — the floating toolbar
/// overflow sheets, the standalone quick-actions overlay (used for
/// layer types without a contextual bar), and any future right-rail
/// or context-menu mounting point.
///
/// Centralising these here avoids three problems:
///   * Drift between surfaces (e.g. duplicate offset 8 px in one
///     surface, 24 px in another).
///   * Repeated `HapticFeedback`/selection-promotion glue.
///   * JSON round-trip cloning being re-discovered (and re-broken)
///     per surface.
///
/// All methods route through existing [EditorCommand]s so undo/redo
/// and the command-history merge protocol are preserved end-to-end.
/// No engine, selection, or interaction logic is duplicated here —
/// this is purely a presentation-side facade.
class LayerActions {
  LayerActions._();

  /// Standard nudge applied to a duplicated layer so the clone sits
  /// visibly under the original. Canvas-pixel space, intentionally
  /// constant regardless of zoom — the user expects a predictable
  /// document-space offset, not a screen-pixel one.
  static const Offset _duplicateOffset = Offset(8, 8);

  /// Clone [layer] via JSON round-trip so we stay agnostic to the
  /// concrete subclass (text / paint / image / shape …). The clone
  /// gets a fresh id + an [_duplicateOffset] nudge and becomes the
  /// new selection — matches Canva / CapCut behaviour.
  ///
  /// Silent no-op when the layer refuses to round-trip (a bug we
  /// can't usefully report from a tap handler) — the original
  /// selection is left untouched.
  static void duplicate(WidgetRef ref, EditorLayer layer) {
    final json = Map<String, dynamic>.from(layer.toJson());
    final newId = _uuid.v4();
    json['id'] = newId;
    // A clone of a locked layer (incl. the protected base photo via
    // Image → More) must start UNLOCKED: the user duplicates to get
    // a copy they can move, and a locked clone is immovable +
    // invisible-to-hit-testing — it reads as "duplicate did nothing".
    json.remove('locked');
    final t = layer.transform;
    json['transform'] = LayerTransform(
      position: t.position + _duplicateOffset,
      size: t.size,
      rotation: t.rotation,
    ).toJson();

    final EditorLayer clone;
    try {
      clone = DocumentCodec.decodeLayer(json);
    } on DocumentDecodeException {
      return;
    }

    HapticFeedback.selectionClick().catchError((_) {});
    ref
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(clone));
    ref.read(selectionControllerProvider.notifier).select(newId);
  }

  /// Remove [layer] and pick the next sensible selection so the user
  /// is not left empty-handed after a common "oops, keep only the
  /// original" flow. Falls back to clearing selection when the
  /// document becomes empty.
  ///
  /// Photo-mode protection: if [layer] is the document's base photo
  /// in a [ProjectKind.photo] project, a confirm dialog is shown
  /// first. Confirming runs Remove + flip-back-to-design as one
  /// composite (single undo restores both photo and project kind).
  /// Cancelling is a silent no-op.
  ///
  /// Split into [confirmDelete] + [deleteWithoutConfirm] so the
  /// overflow sheet can run the canonical sequence (confirm BEFORE
  /// the sheet pops, execute after) while direct callers (quick
  /// pill, layers drawer) keep this one-call form.
  static Future<void> delete(
    BuildContext context,
    WidgetRef ref,
    EditorLayer layer,
  ) async {
    // Capture the l10n label before any await — the awaited dialog
    // may outlive this context in edge cases.
    final removeBasePhotoLabel = context.l10n.removeBasePhotoCommand;
    final confirmed = await confirmDelete(context, ref, layer);
    if (!confirmed) return;
    deleteWithoutConfirm(
      ref,
      layer,
      removeBasePhotoLabel: removeBasePhotoLabel,
    );
  }

  /// Step 1 of the canonical delete sequence: resolve the protected-
  /// base-photo confirm (a dialog) BEFORE any sheet dismissal.
  /// Returns true when the delete may proceed — i.e. the layer is a
  /// normal layer, or the user confirmed removing the base photo.
  static Future<bool> confirmDelete(
    BuildContext context,
    WidgetRef ref,
    EditorLayer layer,
  ) async {
    final doc = ref.read(documentControllerProvider);
    if (doc.indexOf(layer.id) == null) return false;
    if (!doc.isProtectedBasePhoto(layer.id)) return true;
    return await _confirmRemoveBasePhoto(context) == true;
  }

  /// Step 2 of the canonical delete sequence: execute, no dialogs.
  /// [removeBasePhotoLabel] is the history label for the protected-
  /// base-photo composite (captured from l10n by the caller while
  /// its context was alive).
  static void deleteWithoutConfirm(
    WidgetRef ref,
    EditorLayer layer, {
    required String removeBasePhotoLabel,
  }) {
    // Re-read at execute time: if the document changed under the
    // confirm dialog (unlikely but possible), act on fresh state
    // rather than stale assumptions.
    final doc = ref.read(documentControllerProvider);
    if (doc.indexOf(layer.id) == null) return;

    HapticFeedback.selectionClick().catchError((_) {});
    if (doc.isProtectedBasePhoto(layer.id)) {
      ref
          .read(documentControllerProvider.notifier)
          .execute(
            CompositeCommand([
              // Explicit base-photo clear FIRST so its inverse
              // re-points to `layer.id` on undo. (RemoveLayer
              // alone clears the pointer as a side effect, but
              // its inverse re-adds the layer without restoring
              // the pointer -- which would leave the project in a
              // half-restored state after a single undo.)
              const SetBasePhotoCommand(null),
              RemoveLayerCommand(layer.id),
              const SetProjectKindCommand(ProjectKind.design),
            ], labelOverride: removeBasePhotoLabel),
          );
    } else {
      ref
          .read(documentControllerProvider.notifier)
          .execute(RemoveLayerCommand(layer.id));
    }

    // Always clear selection after a delete — the user has explicitly
    // removed the object, so promoting the "next" sibling silently is
    // dangerous (they may accidentally edit or delete it next).
    ref.read(selectionControllerProvider.notifier).clear();
  }

  // ─── batch operations (multi-select) ────────────────────────────
  //
  // Each batch is ONE CompositeCommand → ONE history entry, so a
  // single undo restores the whole group. Closes the audit finding
  // "multi-select has no batch actions".

  /// Delete every layer in [layers] as one undoable step, then clear
  /// the selection. The protected base photo is excluded — removing
  /// it flips the project kind and demands its own confirm, which
  /// belongs to the single-layer flow ([delete]), not to a batch.
  static void deleteMany(
    WidgetRef ref,
    List<EditorLayer> layers, {
    String? label,
  }) {
    final doc = ref.read(documentControllerProvider);
    final removable = [
      for (final layer in layers)
        if (doc.indexOf(layer.id) != null &&
            !doc.isProtectedBasePhoto(layer.id))
          layer,
    ];
    if (removable.isEmpty) return;
    HapticFeedback.selectionClick().catchError((_) {});
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          CompositeCommand([
            for (final layer in removable) RemoveLayerCommand(layer.id),
          ], labelOverride: label),
        );
    ref.read(selectionControllerProvider.notifier).clear();
  }

  /// Duplicate every layer in [layers] as one undoable step and make
  /// the clones the new (multi) selection — so the user can drag the
  /// duplicated group away immediately, mirroring [duplicate].
  static void duplicateMany(
    WidgetRef ref,
    List<EditorLayer> layers, {
    String? label,
  }) {
    final adds = <EditorCommand>[];
    final cloneIds = <String>[];
    for (final layer in layers) {
      final json = Map<String, dynamic>.from(layer.toJson());
      final newId = _uuid.v4();
      json['id'] = newId;
      // Same rule as [duplicate]: clones always start unlocked.
      json.remove('locked');
      final t = layer.transform;
      json['transform'] = LayerTransform(
        position: t.position + _duplicateOffset,
        size: t.size,
        rotation: t.rotation,
      ).toJson();
      final EditorLayer clone;
      try {
        clone = DocumentCodec.decodeLayer(json);
      } on DocumentDecodeException {
        continue; // skip un-cloneable layers, keep the rest
      }
      adds.add(AddLayerCommand(clone));
      cloneIds.add(newId);
    }
    if (adds.isEmpty) return;
    HapticFeedback.selectionClick().catchError((_) {});
    ref
        .read(documentControllerProvider.notifier)
        .execute(CompositeCommand(adds, labelOverride: label));
    ref.read(selectionControllerProvider.notifier).selectMany(cloneIds);
  }

  /// Set the lock flag on every layer in [layers] as one undoable
  /// step. Layers already in the requested state are skipped so the
  /// composite stays minimal and inverts cleanly.
  static void setLockedMany(
    WidgetRef ref,
    List<EditorLayer> layers, {
    required bool locked,
    String? label,
  }) {
    final commands = [
      for (final layer in layers)
        if (layer.locked != locked)
          SetLayerLockCommand(layerId: layer.id, locked: locked),
    ];
    if (commands.isEmpty) return;
    HapticFeedback.selectionClick().catchError((_) {});
    ref
        .read(documentControllerProvider.notifier)
        .execute(CompositeCommand(commands, labelOverride: label));
  }

  static Future<bool?> _confirmRemoveBasePhoto(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.removeBasePhotoTitle),
        content: Text(ctx.l10n.removeBasePhotoBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.keepAction),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.removeAction),
          ),
        ],
      ),
    );
  }

  /// Move [layer] one step up the z-order. Silent no-op when already
  /// topmost — callers should disable the entry-point UI in that
  /// case (see [canBringForward]).
  static void bringForward(WidgetRef ref, EditorLayer layer) {
    final doc = ref.read(documentControllerProvider);
    final index = doc.indexOf(layer.id);
    if (index == null || index >= doc.layers.length - 1) return;
    // The base photo is pinned to the bottom of a photo project; never
    // lift it over user content. (The engine `reorderLayer` clamp is the
    // backstop — this keeps the button and the command in agreement.)
    if (doc.isProtectedBasePhoto(layer.id)) return;
    HapticFeedback.selectionClick().catchError((_) {});
    ref
        .read(documentControllerProvider.notifier)
        .execute(ReorderLayerCommand(from: index, to: index + 1));
  }

  /// Move [layer] one step down the z-order. Silent no-op when
  /// already at the bottom (see [canSendBackward]).
  static void sendBackward(WidgetRef ref, EditorLayer layer) {
    final doc = ref.read(documentControllerProvider);
    final index = doc.indexOf(layer.id);
    if (index == null || index <= 0) return;
    // Don't slide a layer beneath the pinned base photo — it would be
    // fully obscured by the opaque photo (silent content loss). Mirrors
    // the engine `reorderLayer` clamp so the button and command agree.
    if (doc.isProtectedBasePhoto(doc.layers[index - 1].id)) return;
    HapticFeedback.selectionClick().catchError((_) {});
    ref
        .read(documentControllerProvider.notifier)
        .execute(ReorderLayerCommand(from: index, to: index - 1));
  }

  /// Flip the lock flag. The layer stays selected (locked layers can
  /// still be selected via the layers panel and via this surface;
  /// only canvas hit-testing skips them — see `_hitTest` in
  /// `editor_canvas.dart`).
  static void toggleLock(WidgetRef ref, EditorLayer layer) {
    HapticFeedback.selectionClick().catchError((_) {});
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetLayerLockCommand(layerId: layer.id, locked: !layer.locked));
  }

  /// Prompt for a layer display name and commit it through the command
  /// stack. Empty input clears the custom name so default layer labels
  /// remain stable.
  static Future<void> rename(
    BuildContext context,
    WidgetRef ref,
    EditorLayer layer,
  ) async {
    final nextName = await showDialog<String?>(
      context: context,
      builder: (ctx) => _RenameLayerDialog(initialName: layer.name ?? ''),
    );
    if (nextName == null) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetLayerNameCommand(layerId: layer.id, name: nextName));
  }

  static bool canBringForward(WidgetRef ref, EditorLayer layer) {
    final doc = ref.read(documentControllerProvider);
    final index = doc.indexOf(layer.id);
    if (index == null || index >= doc.layers.length - 1) return false;
    // The base photo cannot move up off the bottom.
    return !doc.isProtectedBasePhoto(layer.id);
  }

  static bool canSendBackward(WidgetRef ref, EditorLayer layer) {
    final doc = ref.read(documentControllerProvider);
    final index = doc.indexOf(layer.id);
    if (index == null || index <= 0) return false;
    // Can't send below the pinned base photo directly beneath.
    return !doc.isProtectedBasePhoto(doc.layers[index - 1].id);
  }
}

class _RenameLayerDialog extends StatefulWidget {
  const _RenameLayerDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameLayerDialog> createState() => _RenameLayerDialogState();
}

class _RenameLayerDialogState extends State<_RenameLayerDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void submit() => Navigator.of(context).pop(_controller.text);
    return AlertDialog(
      title: Text(context.l10n.renameLayerTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: context.l10n.renameAction),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(context.l10n.cancelAction),
        ),
        FilledButton(onPressed: submit, child: Text(context.l10n.applyAction)),
      ],
    );
  }
}
