import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks which layer (if any) is currently in "content editing" mode.
///
/// Content editing is distinct from selection: a layer can be selected
/// without being in edit mode. Only layers whose
/// [LayerCapabilities.editable] flag is true should be allowed to enter
/// this mode \u2014 the controller itself stays generic and does not inspect
/// layer types.
///
/// Kept tiny on purpose: the payload is a single nullable id. Per-type
/// modules (e.g. text) observe this provider and render their own
/// editor widgets when the id matches.
class EditingController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Begin editing the layer with the given id. No-op if already editing
  /// that id \u2014 avoids unwanted rebuild / focus-churn when the same
  /// gesture fires twice in quick succession.
  void start(String id) {
    if (state == id) return;
    state = id;
  }

  void stop() {
    if (state == null) return;
    state = null;
  }
}

final editingControllerProvider = NotifierProvider<EditingController, String?>(
  EditingController.new,
);
