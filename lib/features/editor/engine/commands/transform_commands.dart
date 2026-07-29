import '../core/editor_document.dart';
import '../core/editor_layer.dart';
import '../core/layer_transform.dart';
import 'editor_command.dart';

class AddLayerCommand extends EditorCommand {
  const AddLayerCommand(this.layer, {this.index});
  final EditorLayer layer;

  /// Z-order insertion point (bottom = 0). Null appends to the top —
  /// the right default for user-created layers. [RemoveLayerCommand]'s
  /// inverse sets it so undoing a delete restores the layer at its
  /// original depth instead of on top of everything.
  final int? index;

  @override
  String get label => 'Add ${layer.type}';

  @override
  EditorDocument apply(EditorDocument doc) =>
      index == null ? doc.addLayer(layer) : doc.insertLayer(layer, index!);

  @override
  EditorCommand invert(EditorDocument _) => RemoveLayerCommand(layer.id);

  // Holds a full layer reference — the dominant cost is the layer
  // itself (paint strokes, text content, image source string).
  @override
  int get estimatedByteSize => layer.estimatedByteSize;
}

class RemoveLayerCommand extends EditorCommand {
  const RemoveLayerCommand(this.layerId);
  final String layerId;

  @override
  String get label => 'Remove layer';

  @override
  EditorDocument apply(EditorDocument doc) => doc.removeLayer(layerId);

  @override
  EditorCommand invert(EditorDocument before) {
    final prev = before.layerById(layerId);
    if (prev == null) {
      // Defensive: inverting a no-op remove is itself a no-op.
      return const _NoopCommand();
    }
    // Capture the pre-delete z-index so undo restores the layer at
    // its original depth. In a multi-delete CompositeCommand this
    // composes correctly on its own: each child's inverse captures
    // the index in the document just before that child applied, and
    // the reversed replay re-inserts into exactly those states.
    final add = AddLayerCommand(prev, index: before.indexOf(layerId));
    // `removeLayer` clears basePhotoLayerId as a side effect, so an
    // inverse that only re-adds the layer leaves the document
    // pointing at nothing — the bare command did not round-trip
    // (tb5 4/9 harness). The production delete flow already
    // compensates by bundling SetBasePhotoCommand(null) into its
    // composite; re-pointing here as well is idempotent with that
    // (the composite's own inverse sets the same value), and it
    // makes the command correct on its own.
    if (before.basePhotoLayerId != layerId) return add;
    return CompositeCommand([
      add,
      SetBasePhotoCommand(layerId),
    ], labelOverride: 'Delete layer');
  }
}

/// A single command that swaps a layer's transform – used for move, resize
/// and rotate so the undo stack stays flat instead of exploding into three
/// near-identical commands.
class SetLayerTransformCommand extends EditorCommand {
  const SetLayerTransformCommand({
    required this.layerId,
    required this.transform,
    this.labelOverride,
  });

  final String layerId;
  final LayerTransform transform;
  final String? labelOverride;

  @override
  String get label => labelOverride ?? 'Transform layer';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer == null) return doc;
    return doc.replaceLayer(layer.withTransform(transform));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final prev = before.layerById(layerId);
    if (prev == null) return const _NoopCommand();
    return SetLayerTransformCommand(
      layerId: layerId,
      transform: prev.transform,
      labelOverride: labelOverride,
    );
  }
}

/// Mirror a layer across one of its own axes (tb4 7/14).
///
/// Its own inverse: flipping the same axis twice is the identity, so
/// [invert] returns an identical command. That is the simplest
/// possible inverse and the only one that cannot drift from [apply].
///
/// The flip lives on [LayerTransform] and is applied inside rotation,
/// so a rotated layer mirrors its artwork in place — see
/// docs/flip-transform-design-2026-07.md for why the pose is left
/// alone.
class FlipLayerCommand extends EditorCommand {
  const FlipLayerCommand({required this.layerId, required this.horizontal});

  final String layerId;

  /// `true` mirrors left↔right, `false` top↔bottom.
  final bool horizontal;

  @override
  String get label => horizontal ? 'Flip horizontally' : 'Flip vertically';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer == null) return doc;
    final t = layer.transform;
    return doc.replaceLayer(
      layer.withTransform(
        horizontal ? t.copyWith(flipH: !t.flipH) : t.copyWith(flipV: !t.flipV),
      ),
    );
  }

  @override
  EditorCommand invert(EditorDocument before) =>
      before.layerById(layerId) == null
      ? const _NoopCommand()
      : FlipLayerCommand(layerId: layerId, horizontal: horizontal);
}

class MoveLayerCommand extends SetLayerTransformCommand {
  const MoveLayerCommand({required super.layerId, required super.transform})
    : super(labelOverride: 'Move');
}

class ResizeLayerCommand extends SetLayerTransformCommand {
  const ResizeLayerCommand({required super.layerId, required super.transform})
    : super(labelOverride: 'Resize');
}

class RotateLayerCommand extends SetLayerTransformCommand {
  const RotateLayerCommand({required super.layerId, required super.transform})
    : super(labelOverride: 'Rotate');
}

/// Sets [EditorDocument.basePhotoLayerId] \u2014 the marker naming a
/// photo project's subject, which is what keeps Crop and Look pointed
/// at the imported "main" photo however many stickers, text layers or
/// secondary images sit on top, and whatever is selected. Pass `null`
/// to clear (e.g. when the photo is removed).
///
/// Issued only by the photo-project import flows and by
/// `RemoveLayerCommand.invert`. It is deliberately NOT a user-facing
/// command: the role is fixed by the project kind, so nothing reads
/// the marker as a preference the user could re-aim (contract \u00a710).
class SetBasePhotoCommand extends EditorCommand {
  const SetBasePhotoCommand(this.layerId);
  final String? layerId;

  @override
  String get label => layerId == null ? 'Clear base photo' : 'Set base photo';

  @override
  EditorDocument apply(EditorDocument doc) => doc.basePhotoLayerId == layerId
      ? doc
      : doc.copyWith(basePhotoLayerId: layerId);

  @override
  EditorCommand invert(EditorDocument before) =>
      SetBasePhotoCommand(before.basePhotoLayerId);
}

/// Switches the document's [EditorDocument.projectKind]. Used by
/// the photo-import flow (design -> photo) and the base-photo
/// removal confirm flow (photo -> design, bundled with a Remove in
/// one composite so a single undo restores both).
class SetProjectKindCommand extends EditorCommand {
  const SetProjectKindCommand(this.kind);
  final ProjectKind kind;

  @override
  String get label =>
      kind == ProjectKind.photo ? 'Photo project' : 'Design project';

  @override
  EditorDocument apply(EditorDocument doc) =>
      doc.projectKind == kind ? doc : doc.copyWith(projectKind: kind);

  @override
  EditorCommand invert(EditorDocument before) =>
      SetProjectKindCommand(before.projectKind);
}

class _NoopCommand extends EditorCommand {
  const _NoopCommand();
  @override
  String get label => 'noop';
  @override
  EditorDocument apply(EditorDocument doc) => doc;
  @override
  EditorCommand invert(EditorDocument _) => this;
}

/// Bundles N commands into one undo step. Used by group-drag so a
/// multi-layer move appears as a single entry in history rather than N.
///
/// `apply` walks commands in order. `invert` walks them again in order
/// to thread the document state forward (each command's inverse needs
/// to see the document as it was *just before* that command applied),
/// then reverses the inverse list so undo replays the bundle bottom-up.
class CompositeCommand extends EditorCommand {
  const CompositeCommand(this.commands, {this.labelOverride});
  final List<EditorCommand> commands;
  final String? labelOverride;

  @override
  String get label => labelOverride ?? 'Composite (${commands.length})';

  @override
  EditorDocument apply(EditorDocument doc) {
    var d = doc;
    for (final c in commands) {
      d = c.apply(d);
    }
    return d;
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final inverses = <EditorCommand>[];
    var d = before;
    for (final c in commands) {
      inverses.add(c.invert(d));
      d = c.apply(d);
    }
    return CompositeCommand(
      inverses.reversed.toList(),
      labelOverride: labelOverride,
    );
  }

  // Sum of children. Recursion terminates because real construction
  // sites never nest CompositeCommands (verified by grep across the
  // codebase); even if a future caller did, depth is bounded by
  // user-action structure, not by data size.
  @override
  int get estimatedByteSize {
    var n = 0;
    for (final c in commands) {
      n += c.estimatedByteSize;
    }
    return n;
  }
}
