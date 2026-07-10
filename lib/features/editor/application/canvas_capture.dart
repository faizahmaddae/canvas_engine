import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [GlobalKey] attached to the [RepaintBoundary] wrapping the
/// logical canvas board inside `EditorCanvas`.
///
/// Owned by a provider (rather than registered by the canvas
/// widget) so consumers — today only the colour picker's
/// eyedropper — can reach the board without a registration
/// handshake: the key simply has a `currentContext` while an editor
/// is on screen and none otherwise.
///
/// The boundary sits **inside** the viewport transform, so
/// `toImage(pixelRatio: 1)` yields one pixel per logical canvas
/// unit regardless of zoom, and `RenderBox.globalToLocal` on the
/// same box maps a screen touch straight into canvas coordinates.
final canvasBoardBoundaryKeyProvider = Provider<GlobalKey>(
  (ref) => GlobalKey(debugLabel: 'canvas-board-boundary'),
);
