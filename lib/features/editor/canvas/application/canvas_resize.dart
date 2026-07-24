import 'package:flutter/painting.dart';

import '../../engine/commands/editor_command.dart';
import '../../engine/commands/transform_commands.dart';
import '../../engine/core/editor_document.dart';
import 'canvas_commands.dart';

/// Builds the single undoable step behind the Canvas panel's Size
/// section (tb4 4/14).
///
/// [SetCanvasSizeCommand] alone only moves the canvas edges — every
/// layer keeps its top-left canvas coordinate, so growing a canvas
/// pushes the artwork into the top-left corner. That is exactly what
/// the crop pipeline needs (the cropped photo is already positioned
/// against the new bounds) and exactly what a user does NOT expect
/// from "make this a story".
///
/// **Anchor policy — why the two entry points differ.**
///   * **Aspect presets recentre** ([recenterLayers] `true`). The
///     user is reframing a finished composition for another surface;
///     the artwork should stay optically where it was, so every
///     layer shifts by half the size delta and the composition's
///     centre stays the canvas centre. The moves and the size change
///     ride in ONE [CompositeCommand] so a single undo restores both
///     — a resize that needed N+1 undos would read as broken.
///   * **Custom sizes keep the top-left anchor** ([recenterLayers]
///     `false`). Typing exact numbers is a precision act: the user
///     is targeting a known output size and reasons in absolute
///     canvas coordinates ("this logo sits at 40,40"). Silently
///     translating every layer would invalidate those coordinates
///     and force a manual correction pass.
///
/// **Known consequence:** shrinking a canvas can strand layers
/// wholly or partly outside it. They are not lost — layers stay in
/// the document, selectable from the layer list, and the viewport
/// guardrails (tb3 7/7) always keep a canvas edge on screen, so the
/// user can pan back to them and drag them in. Clamping instead
/// would destroy authored positions on a resize the user may well
/// undo.
///
/// Pure function: no providers, no side effects. Callers dispatch
/// the returned command through `documentControllerProvider`.
EditorCommand buildCanvasResize(
  EditorDocument doc, {
  required double width,
  required double height,
  required bool recenterLayers,
}) {
  final resize = SetCanvasSizeCommand(width: width, height: height);
  if (!recenterLayers || doc.layers.isEmpty) return resize;

  // Half the growth in each axis: shifting every layer by this keeps
  // the old canvas centre coincident with the new one.
  final delta = Offset((width - doc.width) / 2, (height - doc.height) / 2);
  if (delta == Offset.zero) return resize;

  final moves = <EditorCommand>[];
  for (final layer in doc.layers) {
    final next = layer.transform.position + delta;
    if (next == layer.transform.position) continue;
    moves.add(
      MoveLayerCommand(
        layerId: layer.id,
        transform: layer.transform.copyWith(position: next),
      ),
    );
  }
  if (moves.isEmpty) return resize;

  // Moves first, then the size change: each move's inverse is
  // captured against the pre-resize document, which is the state
  // undo replays into.
  return CompositeCommand([...moves, resize], labelOverride: 'Resize canvas');
}
