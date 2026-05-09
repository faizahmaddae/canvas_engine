import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/widgets/editor_tool_panel_shell.dart';
import '../application/sticker_tool_controller.dart';

/// Per-tool wrapper around the unified [EditorToolPanelShell] for
/// Sticker sub-tool panels (Size / Style / Replace). Twin of
/// [ImagePanelShell] / [ShapePanelShell], wired to the Sticker
/// tool controller. Adds a 420-px max body width so the grid
/// reads on tablets without stretching.
///
/// **Sibling-swipe is intentionally NOT wired** for Sticker. Only
/// three slots in the strip; the chip strip is faster than swipe
/// at that size and the cost of a mis-swipe (jumping to a tab the
/// user didn't mean) is higher than the benefit. If Sticker grows
/// past ~5 slots, reconsider.
class StickerPanelShell extends ConsumerWidget {
  const StickerPanelShell({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.bodyPadding,
    this.maxBodyWidth = 420,
  });

  final String title;
  final IconData icon;
  final Widget child;

  /// Override the shell body padding. Defaults to the unified
  /// panel default (12 / 12 / 12 / 24). Pass
  /// `EdgeInsets.fromLTRB(0, t, 0, b)` for full-bleed carousels
  /// that own their own internal horizontal rhythm.
  final EdgeInsets? bodyPadding;

  /// Override the body width cap. Pass `null` for true full-bleed
  /// rows (e.g. the Style preset carousel) that must reach the
  /// panel edge on tablets too.
  final double? maxBodyWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(stickerToolControllerProvider.notifier);
    return EditorToolPanelShell(
      title: title,
      icon: icon,
      maxBodyWidth: maxBodyWidth,
      bodyPadding: bodyPadding,
      onClose: ctrl.closePanel,
      child: child,
    );
  }
}
