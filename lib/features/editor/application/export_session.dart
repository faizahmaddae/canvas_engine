import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` while export is inside its render + save/share critical
/// section (contract §6: producing bytes registers as a draft
/// session — the document must not mutate under the renderer).
///
/// Set by the export surfaces around their busy spans (the sheet's
/// `_renderBytes`, the preview's save/share) and unioned into
/// `anyDraftSessionOpenProvider`. Idempotent begin/end so multiple
/// reset paths (catch, finally, dispose) can all call [end] safely.
class ExportSessionController extends Notifier<bool> {
  @override
  bool build() => false;

  void begin() {
    if (!state) state = true;
  }

  void end() {
    if (state) state = false;
  }
}

final exportSessionControllerProvider =
    NotifierProvider<ExportSessionController, bool>(
      ExportSessionController.new,
    );
