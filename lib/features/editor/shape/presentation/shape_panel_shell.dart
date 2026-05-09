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
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(shapeToolControllerProvider.notifier);
    return EditorToolPanelShell(
      title: title,
      icon: icon,
      onClose: ctrl.closePanel,
      onPrev: ctrl.openPrevSlot,
      onNext: ctrl.openNextSlot,
      child: child,
    );
  }
}
