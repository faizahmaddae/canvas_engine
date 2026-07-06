import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/widgets/dock_sheet_chrome.dart';

/// Interface for a sub-tool body rendered inside the dock's
/// expanded region (or a modal, depending on the slot's
/// [SlotPresentation]).
///
/// Phase 1 declares the contract only — no concrete sub-tools are
/// implemented yet. Existing paint/text bodies continue to live in
/// their feature folders and are migrated to this contract in later
/// phases without touching the toolbar host.
abstract class SubTool {
  const SubTool();

  /// Title rendered in the sheet header.
  String get headerTitle;

  /// Icon rendered in the sheet header.
  IconData get headerIcon;

  /// Optional live value rendered as a small chip at the header's
  /// end (e.g. "24px" on Size, "80%" on Background). Null hides the
  /// chip — most panels have no single canonical readout.
  String? get headerValue => null;

  /// Maximum height of the body as a fraction of screen height.
  /// Defaults to the unified [kEditorPanelMaxHeightFraction] so
  /// every panel — Text, Paint, Image, Shape, Sticker, Canvas —
  /// reads the same height. Override only if a specific sub-tool
  /// genuinely needs a different envelope; the dp ceiling
  /// ([kEditorPanelMaxHeightDp]) still clamps it.
  double get maxHeightFraction => kEditorPanelMaxHeightFraction;

  /// Whether horizontal swipe inside the sheet should navigate to
  /// sibling slots in the same mode.
  bool get supportsSiblingSwipe => true;

  /// Build the sub-tool's body. Implementations should be pure
  /// widget composition — value reads/writes go through `ref`.
  Widget build(BuildContext context, WidgetRef ref);
}
