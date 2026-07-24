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
    this.live = false,
  });

  final String layerId;
  final String? content;
  final TextStyleSpec? style;
  final LayerTransform? transform;

  /// When true, marks this command as part of a sanctioned burst
  /// stream — stepper/nudge repeat-fire (A+/A−, ±10%), the only
  /// text surface still allowed to coalesce via the history window
  /// (contract §3; slider drags ride the style-drag session and
  /// commit exactly once). Discrete edits — swatch taps, toggles,
  /// preset applies, session-seal commits — leave this `false`, so
  /// two taps are two undo entries no matter how close in time.
  final bool live;

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

  /// Coalesce a sanctioned `live` burst (stepper/nudge repeat-fire)
  /// on the same layer into a single undo entry. Conservative —
  /// only merges when:
  ///
  ///   * BOTH commands are `live: true` (contract §3: everything
  ///     else is gesture-fenced structurally — one commit per
  ///     interaction — so the history window must never glue two
  ///     discrete edits together),
  ///   * both commands target the same layer,
  ///   * both commands have the SAME touched-field shape across
  ///     `{content, style, transform}` — i.e. each field is non-null
  ///     in both or null in both.
  ///
  /// Mirrors the shape/image convention exactly. A content-edit
  /// command (style=null) and a style-edit command (content=null)
  /// have different shapes and therefore stay as separate undo
  /// entries, so the user can step each back independently. See
  /// rule 4 in `commands.instructions.md`.
  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! UpdateTextCommand) return null;
    if (!previous.live) return null;
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

/// Switch a [TextLayer]'s base paragraph direction mode. Undoable in
/// one step; optional [transform] lets the caller bundle a re-measure
/// when a forced direction changes wrapped layout metrics.
class SetTextDirectionModeCommand extends EditorCommand {
  const SetTextDirectionModeCommand({
    required this.layerId,
    required this.mode,
    this.transform,
  });

  final String layerId;
  final TextDirectionMode mode;
  final LayerTransform? transform;

  @override
  String get label => 'Text direction';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! TextLayer) return doc;
    if (layer.textDirectionMode == mode && transform == null) return doc;
    var next = layer.copyWith(textDirectionMode: mode);
    if (transform != null) {
      next = next.withTransform(transform!) as TextLayer;
    }
    return doc.replaceLayer(next);
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! TextLayer) return _noop;
    return SetTextDirectionModeCommand(
      layerId: layerId,
      mode: layer.textDirectionMode,
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
