import '../core/editor_document.dart';
import '../core/editor_layer.dart';
import '../core/layer_transform.dart';
import 'editor_command.dart';

class AddLayerCommand extends EditorCommand {
  const AddLayerCommand(this.layer);
  final EditorLayer layer;

  @override
  String get label => 'Add ${layer.type}';

  @override
  EditorDocument apply(EditorDocument doc) => doc.addLayer(layer);

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
    return AddLayerCommand(prev);
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

/// Sets [EditorDocument.basePhotoLayerId] \u2014 the marker the
/// image-target resolver uses to keep Crop / Filters / Adjust
/// pointed at the imported "main" photo even after the user has
/// added stickers, text, or secondary images on top. Pass `null`
/// to clear (e.g. when the photo is removed).
class SetBasePhotoCommand extends EditorCommand {
  const SetBasePhotoCommand(this.layerId);
  final String? layerId;

  @override
  String get label => layerId == null ? 'Clear base photo' : 'Set base photo';

  @override
  EditorDocument apply(EditorDocument doc) =>
      doc.basePhotoLayerId == layerId
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
