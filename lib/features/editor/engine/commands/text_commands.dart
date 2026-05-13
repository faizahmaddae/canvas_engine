import '../core/editor_document.dart';
import '../core/layer_transform.dart';
import '../modules/text/text_layer.dart';
import 'editor_command.dart';

/// Replaces text-only properties (content and/or style) on a
/// [TextLayer] and optionally its [LayerTransform] in a single
/// undoable step.
///
/// `content` and `style` are nullable — pass non-null only for the
/// fields you are actually editing, leaving the rest at `null`. This
/// follows the same convention as [UpdatePaintStyleCommand] and is
/// what makes the conservative [mergeWith] check below work: the
/// touched-field set is encoded directly in the call site instead of
/// having to be inferred from value comparisons against the document.
///
/// The optional [transform] is used by the live-edit flow: when
/// content changes the box auto-resizes (height grows to fit wrapped
/// text) and we want the resize to be part of the same undo entry as
/// the content change rather than two separate ones.
class UpdateTextCommand extends EditorCommand {
  const UpdateTextCommand({
    required this.layerId,
    this.content,
    this.style,
    this.transform,
  });

  final String layerId;
  final String? content;
  final TextStyleSpec? style;
  final LayerTransform? transform;

  @override
  String get label => 'Edit text';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! TextLayer) return doc;
    var next = layer.copyWith(
      content: content ?? layer.content,
      style: style ?? layer.style,
    );
    if (transform != null) {
      next = next.withTransform(transform!) as TextLayer;
    }
    return doc.replaceLayer(next);
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! TextLayer) return _noop;
    // Capture only the fields THIS command is actually touching so
    // that the inverse has the same touched-field shape — required
    // by `mergeWith` symmetry on undo→redo.
    return UpdateTextCommand(
      layerId: layerId,
      content: content == null ? null : layer.content,
      style: style == null ? null : layer.style,
      transform: transform == null ? null : layer.transform,
    );
  }

  /// Coalesce a stream of edits on the same layer (e.g. the font-size
  /// slider firing every frame, or the user typing into the content
  /// box) into a single undo entry. Conservative — only merges when:
  ///
  ///   * both commands target the same layer,
  ///   * both commands have the SAME touched-field shape across
  ///     `{content, style, transform}` — i.e. each field is non-null
  ///     in both or null in both.
  ///
  /// Mirrors [UpdatePaintStyleCommand.mergeWith]: a content-edit
  /// command (style=null) and a style-edit command (content=null)
  /// have different shapes and therefore stay as separate undo
  /// entries, so the user can step each back independently. See
  /// rule 4 in `commands.instructions.md`.
  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (previous is! UpdateTextCommand) return null;
    if (previous.layerId != layerId) return null;
    if ((previous.content != null) != (content != null)) return null;
    if ((previous.style != null) != (style != null)) return null;
    if ((previous.transform != null) != (transform != null)) return null;
    return this;
  }

  // Only [content] scales with user input; style and transform are
  // small bounded structs that fold into the per-entry overhead.
  @override
  int get estimatedByteSize => (content?.length ?? 0) * 2;
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
