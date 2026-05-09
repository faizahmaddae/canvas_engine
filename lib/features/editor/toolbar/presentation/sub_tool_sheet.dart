import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/widgets/editor_tool_panel_shell.dart';
import '../domain/sub_tool.dart';

/// Single sheet host for every [SubTool] in the editor.
///
/// Thin adapter over [EditorToolPanelShell] (the unified panel
/// shell shared by every editor mode). All sub-tools — paint
/// slider, text style, future filters — render through this widget
/// so close behaviour, height capping, sibling-swipe and undo all
/// stay uniform with the controller-driven Image / Shape / Canvas /
/// Sticker panels.
///
/// Closing rules (enforced by the shared chrome):
///   * tap the drag handle
///   * swipe down on the handle area
///   * tap the header ✕ chip when [showCloseAction] is true
///   * tap the strip tile again through the controller's `closeSlot`
///
/// **No "Done" pill by default.** Sub-tools that don't actually
/// commit on exit get the honest neutral ✕ icon. Pass
/// [onConfirm] + [confirmLabel] only when tapping the chip really
/// commits state (e.g. "Apply effect").
class SubToolSheet extends ConsumerWidget {
  const SubToolSheet({
    super.key,
    required this.subTool,
    required this.onClose,
    this.onUndo,
    this.onPrev,
    this.onNext,
    this.onConfirm,
    this.confirmLabel,
    this.showCloseAction = true,
  });

  final SubTool subTool;

  /// Closes the sheet for the currently open slot. Should resolve
  /// to `controller.closeSlot()` for the owning mode.
  final VoidCallback onClose;

  /// Optional undo handler. When non-null an undo chip shows in the
  /// header and supports long-press peek (handled by chrome).
  final VoidCallback? onUndo;

  /// Optional sibling navigation handlers. Wired only when
  /// [SubTool.supportsSiblingSwipe] is true.
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  /// True commit-and-exit handler. When supplied alongside
  /// [confirmLabel], a filled primary pill is rendered in the
  /// header. Use only for genuine commit semantics; otherwise
  /// rely on the default ✕ close chip.
  final VoidCallback? onConfirm;

  /// Label for the optional confirm pill (e.g. `'Apply'`).
  final String? confirmLabel;

  /// Whether to render the neutral ✕ close icon in the header.
  /// Defaults to true — matches every other panel. Set false in
  /// modes whose host owns a separate floating exit pill and
  /// wants the sheet header minimal.
  final bool showCloseAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swipe = subTool.supportsSiblingSwipe;
    return EditorToolPanelShell(
      title: subTool.headerTitle,
      icon: subTool.headerIcon,
      maxHeightFraction: subTool.maxHeightFraction,
      onClose: onClose,
      onUndo: onUndo,
      onPrev: swipe ? onPrev : null,
      onNext: swipe ? onNext : null,
      onConfirm: onConfirm,
      confirmLabel: confirmLabel,
      showCloseAction: showCloseAction,
      // Wider gutters than the default panel padding for slider
      // readability \u2014 see [kEditorSubToolBodyPadding] doc.
      bodyPadding: kEditorSubToolBodyPadding,
      child: subTool.build(context, ref),
    );
  }
}
