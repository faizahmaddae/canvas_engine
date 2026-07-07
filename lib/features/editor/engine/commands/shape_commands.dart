import 'package:flutter/painting.dart';

import '../core/editor_document.dart';
import '../modules/shape/shape_layer.dart';
import 'editor_command.dart';

const EditorCommand _noop = _NoopCommand();

class _NoopCommand extends EditorCommand {
  const _NoopCommand();
  @override
  String get label => 'Noop';
  @override
  EditorDocument apply(EditorDocument doc) => doc;
  @override
  EditorCommand invert(EditorDocument before) => this;
}

/// Swap a [ShapeLayer]'s fill colour and/or fill opacity in a single
/// undoable step. Both fields are nullable so callers can change one
/// at a time without disturbing the other (e.g. dragging the opacity
/// slider must not reset the colour the user just picked).
///
/// All other fields (transform / kind / stroke / cornerRadius) are
/// preserved.
class SetShapeFillCommand extends EditorCommand {
  const SetShapeFillCommand({
    required this.layerId,
    this.color,
    this.opacity,
    this.live = false,
  });

  final String layerId;
  final Color? color;
  final double? opacity;

  /// When true, marks this command as part of a live drag stream
  /// (e.g. the opacity slider). Successive `live` commands of the
  /// same shape with the same edited field-set merge into a single
  /// undo entry whose inverse still restores the pre-stream state.
  /// Discrete edits (palette taps, custom-picker commits) leave
  /// this `false` so each becomes its own history entry.
  final bool live;

  @override
  String get label => 'Shape fill';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ShapeLayer) return doc;
    final newColor = color ?? layer.fillColor;
    final newOpacity = (opacity ?? layer.fillOpacity).clamp(0.0, 1.0);
    if (newColor == layer.fillColor && newOpacity == layer.fillOpacity) {
      return doc;
    }
    return doc.replaceLayer(
      layer.copyWith(fillColor: newColor, fillOpacity: newOpacity),
    );
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ShapeLayer) return _noop;
    return SetShapeFillCommand(
      layerId: layerId,
      color: layer.fillColor,
      opacity: layer.fillOpacity,
    );
  }

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetShapeFillCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    // Field-set must match so a colour drag never silently swallows
    // an opacity drag (or vice versa).
    if ((color == null) != (previous.color == null)) return null;
    if ((opacity == null) != (previous.opacity == null)) return null;
    return this;
  }
}

/// Swap a [ShapeLayer]'s stroke colour and/or width in a single
/// undoable step. Pass [clearColor]: true to remove the outline
/// regardless of the current colour. Width 0 also reads as no
/// stroke at render time.
///
/// All other fields (transform / kind / fill / cornerRadius) are
/// preserved so toggling the outline doesn't disturb the rest of
/// the shape.
class SetShapeStrokeCommand extends EditorCommand {
  const SetShapeStrokeCommand({
    required this.layerId,
    this.color,
    this.clearColor = false,
    this.width,
    this.live = false,
  });

  final String layerId;
  final Color? color;
  final bool clearColor;
  final double? width;
  final bool live;

  @override
  String get label => 'Shape stroke';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ShapeLayer) return doc;
    final newColor = clearColor ? null : (color ?? layer.strokeColor);
    final newWidth = width ?? layer.strokeWidth;
    if (newColor == layer.strokeColor && newWidth == layer.strokeWidth) {
      return doc;
    }
    return doc.replaceLayer(
      layer.copyWith(
        strokeColor: clearColor ? null : newColor,
        clearStroke: clearColor,
        strokeWidth: newWidth,
      ),
    );
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ShapeLayer) return _noop;
    return SetShapeStrokeCommand(
      layerId: layerId,
      color: layer.strokeColor,
      clearColor: layer.strokeColor == null,
      width: layer.strokeWidth,
    );
  }

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetShapeStrokeCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    if (previous.clearColor != clearColor) return null;
    if ((color == null) != (previous.color == null)) return null;
    if ((width == null) != (previous.width == null)) return null;
    return this;
  }
}

/// Swap a [ShapeLayer]'s [cornerRadius] in a single undoable step.
/// No-op for [ShapeKind.circle] (circles ignore radius at render
/// time, but we still skip the document mutation so the undo stack
/// stays clean).
///
/// All other fields are preserved.
class SetShapeRadiusCommand extends EditorCommand {
  const SetShapeRadiusCommand({
    required this.layerId,
    required this.radius,
    this.live = false,
  });

  final String layerId;
  final double radius;
  final bool live;

  @override
  String get label => 'Shape radius';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ShapeLayer) return doc;
    if (layer.kind == ShapeKind.circle) return doc;
    final clamped = radius < 0 ? 0.0 : radius;
    if (clamped == layer.cornerRadius) return doc;
    return doc.replaceLayer(layer.copyWith(cornerRadius: clamped));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ShapeLayer) return _noop;
    return SetShapeRadiusCommand(layerId: layerId, radius: layer.cornerRadius);
  }

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetShapeRadiusCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    return this;
  }
}

/// Swap a [ShapeLayer]'s [ShapeKind] in a single undoable step,
/// preserving transform, fill, stroke and corner radius. Used by the
/// Replace tab in the shape toolbar so the user can morph an existing
/// shape (e.g. rectangle → star) without losing position, size,
/// rotation, palette pick, or border choices.
///
/// No-op when the new kind matches the current one.
class ReplaceShapeKindCommand extends EditorCommand {
  const ReplaceShapeKindCommand({required this.layerId, required this.kind});

  final String layerId;
  final ShapeKind kind;

  @override
  String get label => 'Replace shape';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ShapeLayer) return doc;
    if (layer.kind == kind) return doc;
    return doc.replaceLayer(layer.copyWith(kind: kind));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ShapeLayer) return _noop;
    return ReplaceShapeKindCommand(layerId: layerId, kind: layer.kind);
  }
}

/// Swap a [ShapeLayer]'s drop-shadow fields in a single undoable
/// step. All four fields (color/blur/offset/opacity) are nullable
/// so callers can change one knob at a time without disturbing the
/// others — picking a colour shouldn't reset the offset, sliding
/// blur shouldn't reset opacity, etc.
///
/// All other layer fields (transform/kind/fill/stroke/cornerRadius)
/// are preserved so toggling shadow leaves the rest of the shape
/// alone.
class SetShapeShadowCommand extends EditorCommand {
  const SetShapeShadowCommand({
    required this.layerId,
    this.color,
    this.blur,
    this.offset,
    this.opacity,
    this.live = false,
  });

  final String layerId;
  final Color? color;
  final double? blur;
  final Offset? offset;
  final double? opacity;

  /// When true, marks this command as part of a live drag stream
  /// (e.g. blur / opacity slider). Successive `live` commands of
  /// the same shape with the same edited field-set merge into a
  /// single undo entry whose inverse still restores the pre-stream
  /// state. Discrete edits (preset taps, palette taps, direction-
  /// pad taps) leave this `false` so each becomes its own history
  /// entry.
  final bool live;

  @override
  String get label => 'Shape shadow';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ShapeLayer) return doc;
    final newColor = color ?? layer.shadowColor;
    final newBlur = blur ?? layer.shadowBlur;
    final newOffset = offset ?? layer.shadowOffset;
    final newOpacity = (opacity ?? layer.shadowOpacity).clamp(0.0, 1.0);
    if (newColor == layer.shadowColor &&
        newBlur == layer.shadowBlur &&
        newOffset == layer.shadowOffset &&
        newOpacity == layer.shadowOpacity) {
      return doc;
    }
    return doc.replaceLayer(
      layer.copyWith(
        shadowColor: newColor,
        shadowBlur: newBlur,
        shadowOffset: newOffset,
        shadowOpacity: newOpacity,
      ),
    );
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ShapeLayer) return _noop;
    return SetShapeShadowCommand(
      layerId: layerId,
      color: layer.shadowColor,
      blur: layer.shadowBlur,
      offset: layer.shadowOffset,
      opacity: layer.shadowOpacity,
    );
  }

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetShapeShadowCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    // Field-set must match so a blur drag never silently swallows an
    // opacity drag (or vice versa).
    if ((color == null) != (previous.color == null)) return null;
    if ((blur == null) != (previous.blur == null)) return null;
    if ((offset == null) != (previous.offset == null)) return null;
    if ((opacity == null) != (previous.opacity == null)) return null;
    return this;
  }
}

/// Swap a [ShapeLayer]'s [ShapeLayer.resizeMode] in a single
/// undoable step. Mirrors `SetPaintResizeModeCommand` so the user-
/// facing toggle in the floating toolbar behaves the same way for
/// both layer kinds.
///
/// All other fields (transform / kind / fill / stroke / shadow /
/// cornerRadius) are preserved so flipping the toggle never
/// disturbs the rest of the shape.
class SetShapeResizeModeCommand extends EditorCommand {
  const SetShapeResizeModeCommand({required this.layerId, required this.mode});

  final String layerId;

  /// Target stored resize mode. `null` clears the per-instance override
  /// so the layer falls back to its kind default
  /// ([ShapeLayer.effectiveResizeMode]). Nullable — not `effectiveResizeMode`
  /// — because the stored field is what serialization and undo must
  /// reproduce exactly: capturing the resolved default in [invert] would
  /// convert a byte-omitted `null` into an explicit value, corrupting
  /// round-trip byte-identity and leaving undo unable to restore the
  /// original state.
  final ShapeResizeMode? mode;

  @override
  String get label => 'Shape resize mode';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ShapeLayer) return doc;
    // Compare against the raw stored field so null (kind-default) and an
    // explicit value that happens to equal the default are distinct
    // states — otherwise undo could never round-trip back to `null`.
    if (layer.resizeMode == mode) return doc;
    // copyAll honours an explicit `null` (its sentinel default is a
    // private token, not null), so this can clear the override; copyWith
    // could not.
    return doc.replaceLayer(layer.copyAll(resizeMode: mode));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ShapeLayer) return _noop;
    return SetShapeResizeModeCommand(layerId: layerId, mode: layer.resizeMode);
  }
}
