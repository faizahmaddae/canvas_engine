import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of the in-dock state for the Canvas tool. The actual
/// document background lives on `EditorDocument.backgroundColor`;
/// this controller only owns whether the bottom-dock panel is
/// expanded so the chip strip can highlight its tab and the dock
/// can decide whether to render the panel body.
@immutable
class CanvasToolSession {
  const CanvasToolSession({this.panelOpen = false});

  static const CanvasToolSession initial = CanvasToolSession();

  final bool panelOpen;

  CanvasToolSession copyWith({bool? panelOpen}) =>
      CanvasToolSession(panelOpen: panelOpen ?? this.panelOpen);
}

class CanvasToolController extends Notifier<CanvasToolSession> {
  @override
  CanvasToolSession build() => CanvasToolSession.initial;

  /// Flip the panel open/closed. Mirrors the image-tool toggle so
  /// re-tapping the Canvas chip dismisses the panel without an
  /// explicit close gesture.
  void togglePanel() {
    state = state.copyWith(panelOpen: !state.panelOpen);
  }

  void closePanel() {
    if (!state.panelOpen) return;
    state = state.copyWith(panelOpen: false);
  }
}

final canvasToolControllerProvider =
    NotifierProvider<CanvasToolController, CanvasToolSession>(
      CanvasToolController.new,
    );
