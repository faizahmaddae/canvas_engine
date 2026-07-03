import '../core/editor_document.dart';
import 'editor_command.dart';

/// Moves a layer from [from] to [to] inside [EditorDocument.layers].
/// Both indices are into the layer list (bottom=0, top=length-1).
class ReorderLayerCommand extends EditorCommand {
  const ReorderLayerCommand({required this.from, required this.to});

  final int from;
  final int to;

  @override
  String get label => 'Reorder layer';

  @override
  EditorDocument apply(EditorDocument doc) => doc.reorderLayer(from, to);

  @override
  EditorCommand invert(EditorDocument _) =>
      ReorderLayerCommand(from: to, to: from);
}

/// Sets the runtime [EditorLayer.visible] flag on a layer.
class SetLayerVisibilityCommand extends EditorCommand {
  const SetLayerVisibilityCommand({
    required this.layerId,
    required this.visible,
  });

  final String layerId;
  final bool visible;

  @override
  String get label => visible ? 'Show layer' : 'Hide layer';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer == null || layer.visible == visible) return doc;
    return doc.replaceLayer(layer.withVisibility(visible));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final prev = before.layerById(layerId);
    if (prev == null) return _NoopLayerCommand.instance;
    return SetLayerVisibilityCommand(layerId: layerId, visible: prev.visible);
  }
}

/// Sets the runtime [EditorLayer.locked] flag on a layer.
class SetLayerLockCommand extends EditorCommand {
  const SetLayerLockCommand({required this.layerId, required this.locked});

  final String layerId;
  final bool locked;

  @override
  String get label => locked ? 'Lock layer' : 'Unlock layer';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer == null || layer.locked == locked) return doc;
    return doc.replaceLayer(layer.withLocked(locked));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final prev = before.layerById(layerId);
    if (prev == null) return _NoopLayerCommand.instance;
    return SetLayerLockCommand(layerId: layerId, locked: prev.locked);
  }
}

/// Sets the layer-level [EditorLayer.opacity] (0..1). Mirrors the
/// visibility / lock command pattern so undo/redo, history coalescing
/// and notification all behave identically. The slider in the layers
/// panel dispatches this on change-end (interactive previews during
/// drag are routed through `DocumentController.liveReplace` to keep
/// the undo stack tidy).
class SetLayerOpacityCommand extends EditorCommand {
  const SetLayerOpacityCommand({required this.layerId, required this.opacity});

  final String layerId;
  final double opacity;

  @override
  String get label => 'Set layer opacity';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer == null) return doc;
    final clamped = opacity.clamp(0.0, 1.0);
    if (layer.opacity == clamped) return doc;
    return doc.replaceLayer(layer.withOpacity(clamped));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final prev = before.layerById(layerId);
    if (prev == null) return _NoopLayerCommand.instance;
    return SetLayerOpacityCommand(layerId: layerId, opacity: prev.opacity);
  }
}

/// Sets the optional display name for a layer. Empty / whitespace-only
/// names are normalised to `null`, which preserves the existing default
/// naming behaviour in the layers panel and avoids serialising empty names.
class SetLayerNameCommand extends EditorCommand {
  const SetLayerNameCommand({required this.layerId, required this.name});

  final String layerId;
  final String? name;

  String? get _normalisedName {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  @override
  String get label => 'Rename layer';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer == null) return doc;
    final nextName = _normalisedName;
    if (layer.name == nextName) return doc;
    return doc.replaceLayer(layer.withName(nextName));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final prev = before.layerById(layerId);
    if (prev == null) return _NoopLayerCommand.instance;
    return SetLayerNameCommand(layerId: layerId, name: prev.name);
  }
}

class _NoopLayerCommand extends EditorCommand {
  const _NoopLayerCommand();
  static const instance = _NoopLayerCommand();
  @override
  String get label => 'noop';
  @override
  EditorDocument apply(EditorDocument doc) => doc;
  @override
  EditorCommand invert(EditorDocument _) => this;
}
