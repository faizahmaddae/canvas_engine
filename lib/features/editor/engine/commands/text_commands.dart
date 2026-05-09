import '../core/editor_document.dart';
import '../core/layer_transform.dart';
import '../modules/text/text_layer.dart';
import 'editor_command.dart';

/// Replaces text-only properties (content/style) on a [TextLayer] and
/// optionally its [LayerTransform] in a single undoable step.
///
/// The optional [transform] is used by the live-edit flow: when content
/// changes the box auto-resizes (height grows to fit wrapped text) and
/// we want the resize to be part of the same undo entry as the content
/// change rather than two separate ones.
class UpdateTextCommand extends EditorCommand {
  const UpdateTextCommand({
    required this.layerId,
    required this.style,
    required this.content,
    this.transform,
  });

  final String layerId;
  final String content;
  final TextStyleSpec style;
  final LayerTransform? transform;

  @override
  String get label => 'Edit text';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! TextLayer) return doc;
    var next = layer.copyWith(content: content, style: style);
    if (transform != null) {
      next = next.withTransform(transform!) as TextLayer;
    }
    return doc.replaceLayer(next);
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! TextLayer) return _noop;
    return UpdateTextCommand(
      layerId: layerId,
      content: layer.content,
      style: layer.style,
      transform: transform == null ? null : layer.transform,
    );
  }

  /// Coalesce a stream of style edits on the same layer (e.g. the
  /// font-size slider firing every frame) into a single undo entry.
  /// Only merges with another [UpdateTextCommand] for the same layer;
  /// the bundled-transform shape must match too so we don't silently
  /// drop or invent a re-measure between merged steps.
  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (previous is! UpdateTextCommand) return null;
    if (previous.layerId != layerId) return null;
    if ((previous.transform != null) != (transform != null)) return null;
    return this;
  }
}

/// Switch a [TextLayer]'s [TextResizeMode]. Undoable in one step;
/// optional [transform] lets the caller bundle a re-measure of the
/// bounding box (the new mode often needs a different natural size)
/// into the same history entry.
class SetTextResizeModeCommand extends EditorCommand {
  const SetTextResizeModeCommand({
    required this.layerId,
    required this.mode,
    this.transform,
  });

  final String layerId;
  final TextResizeMode mode;
  final LayerTransform? transform;

  @override
  String get label => 'Text resize mode';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! TextLayer) return doc;
    if (layer.resizeMode == mode && transform == null) return doc;
    var next = layer.copyWith(resizeMode: mode);
    if (transform != null) {
      next = next.withTransform(transform!) as TextLayer;
    }
    return doc.replaceLayer(next);
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! TextLayer) return _noop;
    return SetTextResizeModeCommand(
      layerId: layerId,
      mode: layer.resizeMode,
      transform: transform == null ? null : layer.transform,
    );
  }
}

const EditorCommand _noop = _NoopCommand();

class _NoopCommand extends EditorCommand {
  const _NoopCommand();
  @override
  String get label => 'noop';
  @override
  EditorDocument apply(EditorDocument doc) => doc;
  @override
  EditorCommand invert(EditorDocument _) => this;
}
