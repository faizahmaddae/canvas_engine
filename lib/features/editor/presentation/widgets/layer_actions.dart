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
  static Future<void> delete(
    BuildContext context,
    WidgetRef ref,
    EditorLayer layer,
  ) async {
    final doc = ref.read(documentControllerProvider);
    if (doc.indexOf(layer.id) == null) return;

    if (doc.isProtectedBasePhoto(layer.id)) {
      final confirmed = await _confirmRemoveBasePhoto(context);
      if (confirmed != true) return;
      if (!context.mounted) return;
      // Re-read post-await: if the document changed under us
      // (unlikely but possible), bail rather than acting on stale
      // assumptions.
      final fresh = ref.read(documentControllerProvider);
      if (!fresh.isProtectedBasePhoto(layer.id)) return;
      HapticFeedback.selectionClick().catchError((_) {});
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
            ], labelOverride: context.l10n.removeBasePhotoCommand),
          );
    } else {
      HapticFeedback.selectionClick().catchError((_) {});
      ref
          .read(documentControllerProvider.notifier)
          .execute(RemoveLayerCommand(layer.id));
    }

    // Always clear selection after a delete — the user has explicitly
    // removed the object, so promoting the "next" sibling silently is
    // dangerous (they may accidentally edit or delete it next).
    ref.read(selectionControllerProvider.notifier).clear();
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
    return index != null && index < doc.layers.length - 1;
  }

  static bool canSendBackward(WidgetRef ref, EditorLayer layer) {
    final doc = ref.read(documentControllerProvider);
    final index = doc.indexOf(layer.id);
    return index != null && index > 0;
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
