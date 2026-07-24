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
    this.sides,
    this.blurSigma,
    this.kind,
    this.resizeMode,
    this.live = false,
  });

  final String layerId;
  final Color? strokeColor;
  final double? strokeWidth;
  final bool setFillColor;
  final Color? fillColor;

  /// Polygon side count. Meaningful for [PaintKind.polygon]; the
  /// codec drops it for kinds that ignore it.
  final int? sides;

  /// Gaussian sigma for [PaintKind.blur].
  final double? blurSigma;

  /// Restyle the layer's [PaintKind] (tb4 3/14). Constrained: the
  /// target must be a peer of the layer's current kind
  /// ([paintKindPeers]) or the change is dropped, so a restyle can
  /// never invalidate the geometry the layer was drawn with.
  final PaintKind? kind;

  final PaintResizeMode? resizeMode;

  /// When true, marks this command as part of a sanctioned burst
  /// stream (repeat-fire steppers — none exist in Paint today; the
  /// flag matches the shape/image convention so a future stepper
  /// coalesces without another engine change). All current paint
  /// commits — the preview channels' settle commands, discrete
  /// setter mirrors, toggles — leave this `false`: gesture fencing
  /// is structural (contract §3), so the history window must never
  /// glue two separate interactions together.
  final bool live;

  @override
  String get label => 'Paint style';

  /// The kind this command actually installs on [layer], or `null`
  /// for "leave it alone" — which also covers a rejected switch to a
  /// non-peer kind.
  PaintKind? _targetKind(PaintLayer layer) {
    final target = kind;
    if (target == null || target == layer.kind) return null;
    return paintKindPeers(layer.kind).contains(target) ? target : null;
  }

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! PaintLayer) return doc;
    final nextKind = _targetKind(layer);
    // `copyAll` uses a private sentinel to distinguish "leave fill
    // alone" from "set fill to null". Branch here to honor that
    // distinction without leaking the sentinel out of the layer.
    // (`kind` is copyAll-only — copyWith cannot reach it.)
    final next = setFillColor
        ? layer.copyAll(
            kind: nextKind,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            fillColor: fillColor,
            sides: sides,
            blurSigma: blurSigma,
            resizeMode: resizeMode,
          )
        : layer.copyAll(
            kind: nextKind,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            sides: sides,
            blurSigma: blurSigma,
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
      sides: sides == null ? null : layer.sides,
      blurSigma: blurSigma == null ? null : layer.blurSigma,
      // Restoring the pre-command kind is always a peer of the kind
      // this command installed (peer groups are symmetric), so the
      // inverse can never be rejected.
      kind: _targetKind(layer) == null ? null : layer.kind,
      resizeMode: resizeMode == null ? null : layer.resizeMode,
    );
  }

  /// Coalesce a sanctioned `live` burst with the immediately-previous
  /// entry when BOTH are `live: true` and touch the EXACT same set of
  /// fields on the EXACT same layer (contract §3 — slider drags now
  /// commit once structurally via the overlay preview channels, so
  /// non-live commands never merge: two discrete edits stay two undo
  /// entries no matter how close in time). Different fields (e.g.
  /// width then color) intentionally stay as separate undo entries so
  /// users can step them back independently.
  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! UpdatePaintStyleCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    if ((previous.strokeColor != null) != (strokeColor != null)) return null;
    if ((previous.strokeWidth != null) != (strokeWidth != null)) return null;
    if (previous.setFillColor != setFillColor) return null;
    if ((previous.sides != null) != (sides != null)) return null;
    if ((previous.blurSigma != null) != (blurSigma != null)) return null;
    if ((previous.kind != null) != (kind != null)) return null;
    if ((previous.resizeMode != null) != (resizeMode != null)) return null;
    return this;
  }
}

/// Switch a [PaintLayer]'s [PaintResizeMode]. Undoable in one step.
/// No transform re-measure is needed (paint geometry stretches with
/// its bounding box; aspect mode change only affects future drags).
class SetPaintResizeModeCommand extends EditorCommand {
  const SetPaintResizeModeCommand({required this.layerId, required this.mode});

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
    return SetPaintResizeModeCommand(layerId: layerId, mode: layer.resizeMode);
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
