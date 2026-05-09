import 'dart:ui';

import '../core/editor_document.dart';
import '../modules/paint/paint_layer.dart';
import 'editor_command.dart';

/// Updates style-only properties on a [PaintLayer] in a single
/// undoable step. Mirrors the role [UpdateTextCommand] plays for text:
/// gives the floating quick toolbar a clean atomic undo entry per
/// commit (color pick, stroke width change, fill toggle).
///
/// Each field uses a sentinel-vs-null convention via the constructor:
/// pass [strokeColor] / [strokeWidth] / [resizeMode] only when changing
/// them; pass [setFillColor] = true together with [fillColor] to set
/// a value (including null to clear). This keeps "no change to this
/// property" distinct from "set to null".
class UpdatePaintStyleCommand extends EditorCommand {
  const UpdatePaintStyleCommand({
    required this.layerId,
    this.strokeColor,
    this.strokeWidth,
    this.setFillColor = false,
    this.fillColor,
    this.resizeMode,
  });

  final String layerId;
  final Color? strokeColor;
  final double? strokeWidth;
  final bool setFillColor;
  final Color? fillColor;
  final PaintResizeMode? resizeMode;

  @override
  String get label => 'Paint style';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! PaintLayer) return doc;
    // copyWith uses a private sentinel to distinguish "leave fill
    // alone" from "set fill to null". Branch here to honor that
    // distinction without leaking the sentinel out of the layer.
    final next = setFillColor
        ? layer.copyWith(
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            fillColor: fillColor,
            resizeMode: resizeMode,
          )
        : layer.copyWith(
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            resizeMode: resizeMode,
          );
    if (identical(next, layer) || next == layer) return doc;
    return doc.replaceLayer(next);
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! PaintLayer) return _noop;
    return UpdatePaintStyleCommand(
      layerId: layerId,
      strokeColor: strokeColor == null ? null : layer.strokeColor,
      strokeWidth: strokeWidth == null ? null : layer.strokeWidth,
      setFillColor: setFillColor,
      fillColor: setFillColor ? layer.fillColor : null,
      resizeMode: resizeMode == null ? null : layer.resizeMode,
    );
  }

  /// Coalesce with the immediately-previous entry when it touches the
  /// EXACT same set of fields on the EXACT same layer. Lets the size
  /// sheet's slider stream collapse to one undo step per drag without
  /// the caller having to manage begin/commit boundaries. Different
  /// fields (e.g. width then color) intentionally stay as separate
  /// undo entries so users can step them back independently.
  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (previous is! UpdatePaintStyleCommand) return null;
    if (previous.layerId != layerId) return null;
    if ((previous.strokeColor != null) != (strokeColor != null)) return null;
    if ((previous.strokeWidth != null) != (strokeWidth != null)) return null;
    if (previous.setFillColor != setFillColor) return null;
    if ((previous.resizeMode != null) != (resizeMode != null)) return null;
    return this;
  }
}

/// Switch a [PaintLayer]'s [PaintResizeMode]. Undoable in one step.
/// No transform re-measure is needed (paint geometry stretches with
/// its bounding box; aspect mode change only affects future drags).
class SetPaintResizeModeCommand extends EditorCommand {
  const SetPaintResizeModeCommand({
    required this.layerId,
    required this.mode,
  });

  final String layerId;
  final PaintResizeMode mode;

  @override
  String get label => 'Paint resize behavior';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! PaintLayer) return doc;
    if (layer.resizeMode == mode) return doc;
    return doc.replaceLayer(layer.copyWith(resizeMode: mode));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! PaintLayer) return _noop;
    return SetPaintResizeModeCommand(
      layerId: layerId,
      mode: layer.resizeMode,
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
