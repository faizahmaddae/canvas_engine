import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/image_tool_controller.dart';
import '../../presentation/widgets/editor_tool_panel_shell.dart';

/// Per-tool wrapper around the unified [EditorToolPanelShell] for
/// Image sub-tool panels (Shape / Border / Shadow / Style / Adjust /
/// Filters). Centralises the controller wiring (close + sibling
/// navigation) so each body file only declares its title + icon
/// and provides a child.
///
/// **Why this wrapper exists (and is not redundant):** it owns the
/// Image-tool controller binding — onClose, openPrevSlot, openNextSlot.
/// Bodies stay free of provider plumbing and the chrome stays
/// tool-agnostic. **Add new Image-panel behaviour HERE, never in
/// individual body files** — that is what stops the duplication
/// the unified shell removed.
///
/// Inherits the shared height defaults from [EditorToolPanelShell]
/// (no per-tool override).
class ImagePanelShell extends ConsumerWidget {
  const ImagePanelShell({
    super.key,
    required this.title,
    required this.icon,
    this.headerValue,
    required this.child,
    this.bodyPadding,
  });

  final String title;
  final IconData icon;

  /// Live value shown as a small chip in the panel header (tb7 2/7).
  ///
  /// The approved prototype put the current value — `۹۶px`, a hex
  /// colour, `۱۳۵°` — in EVERY panel header, so the number the panel
  /// edits is readable without hunting for the control that owns it.
  /// The chrome supported it from the start; only the text and paint
  /// sub-tools ever passed it, so the object panels shipped without.
  final String? headerValue;

  final Widget child;

  /// Passed through to [EditorToolPanelShell.bodyPadding]. Fixed-
  /// height bodies (e.g. the Filters strip) use it to drop the
  /// default 24dp bottom clearance that only scrolling panels need.
  final EdgeInsetsGeometry? bodyPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(imageToolControllerProvider.notifier);
    return EditorToolPanelShell(
      title: title,
      icon: icon,
      headerValue: headerValue,
      onClose: ctrl.closePanel,
      onPrev: ctrl.openPrevSlot,
      onNext: ctrl.openNextSlot,
      bodyPadding: bodyPadding,
      child: child,
    );
  }
}
