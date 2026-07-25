import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/shape_tool_controller.dart';
import '../../presentation/widgets/editor_tool_panel_shell.dart';

/// Per-tool wrapper around the unified [EditorToolPanelShell] for
/// Shape sub-tool panels (Style / Border / Shadow). Twin of
/// [ImagePanelShell], wired to the Shape tool controller.
///
/// **Why this wrapper exists:** it owns the Shape-tool controller
/// binding (close + sibling navigation). Add new Shape-panel
/// behaviour HERE, never in body files.
///
/// Inherits shared height defaults — do not override per tool.
class ShapePanelShell extends ConsumerWidget {
  const ShapePanelShell({
    super.key,
    required this.title,
    required this.icon,
    this.headerValue,
    required this.child,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(shapeToolControllerProvider.notifier);
    return EditorToolPanelShell(
      title: title,
      icon: icon,
      headerValue: headerValue,
      onClose: ctrl.closePanel,
      onPrev: ctrl.openPrevSlot,
      onNext: ctrl.openNextSlot,
      child: child,
    );
  }
}
