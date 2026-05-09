import 'package:flutter/painting.dart';

import '../../engine/commands/editor_command.dart';
import '../../engine/core/editor_document.dart';

/// Swap the document's [EditorDocument.backgroundColor] in a single
/// undoable step.
///
/// Set [live] to `true` for streaming updates from a continuous
/// picker (e.g. a hue slider drag) so successive commands collapse
/// into one history entry. Tapping a swatch should leave [live] at
/// its default `false` so each tap is its own undoable click.
class SetCanvasBackgroundCommand extends EditorCommand {
  const SetCanvasBackgroundCommand({
    required this.color,
    this.live = false,
  });

  final Color color;
  final bool live;

  @override
  String get label => 'Canvas background';

  @override
  EditorDocument apply(EditorDocument doc) {
    if (doc.backgroundColor == color) return doc;
    return doc.copyWith(backgroundColor: color);
  }

  @override
  EditorCommand invert(EditorDocument before) =>
      SetCanvasBackgroundCommand(color: before.backgroundColor);

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetCanvasBackgroundCommand) return null;
    if (!previous.live) return null;
    return this;
  }
}

/// Swap the document's [EditorDocument.backgroundMode] in a single
/// undoable step. Independent from the colour value: flipping to
/// transparent does not erase the previous colour pick, so toggling
/// back restores the user's last palette choice without a redo.
class SetCanvasBackgroundModeCommand extends EditorCommand {
  const SetCanvasBackgroundModeCommand(this.mode);

  final CanvasBackgroundMode mode;

  @override
  String get label => 'Canvas background mode';

  @override
  EditorDocument apply(EditorDocument doc) {
    if (doc.backgroundMode == mode) return doc;
    return doc.copyWith(backgroundMode: mode);
  }

  @override
  EditorCommand invert(EditorDocument before) =>
      SetCanvasBackgroundModeCommand(before.backgroundMode);
}

/// Resize the document canvas in a single undoable step.
///
/// Used by the photo-project Crop pipeline so committing a crop
/// shrinks the canvas to match the cropped photo's pixel
/// proportions, never leaving white gaps. No layer transforms are
/// touched here -- callers that want to reposition layers along
/// with the canvas resize should bundle this command into a
/// [CompositeCommand].
class SetCanvasSizeCommand extends EditorCommand {
  const SetCanvasSizeCommand({required this.width, required this.height});

  final double width;
  final double height;

  @override
  String get label => 'Resize canvas';

  @override
  EditorDocument apply(EditorDocument doc) {
    if (doc.width == width && doc.height == height) return doc;
    return doc.copyWith(width: width, height: height);
  }

  @override
  EditorCommand invert(EditorDocument before) =>
      SetCanvasSizeCommand(width: before.width, height: before.height);
}
