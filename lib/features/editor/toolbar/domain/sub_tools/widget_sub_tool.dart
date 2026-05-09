import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sub_tool.dart';

/// Adapter [SubTool] that renders an arbitrary widget builder.
///
/// Used to migrate existing per-tool body widgets (paint Color,
/// Fill, Tool, Polygon, Opacity, Dash) onto [SubToolSheet] without
/// rewriting them. The benefit: every sub-tool sheet — slider or
/// custom — flows through the same chrome, padding, surface
/// elevation, and Done button. Visual consistency without
/// premature refactor.
class WidgetSubTool extends SubTool {
  const WidgetSubTool({
    required this.headerTitle,
    required this.headerIcon,
    required this.builder,
    bool supportsSiblingSwipe = true,
  }) : _supportsSiblingSwipe = supportsSiblingSwipe;

  @override
  final String headerTitle;
  @override
  final IconData headerIcon;

  // Backing field for the [SubTool.supportsSiblingSwipe] override.
  // Kept private + getter override so this never *shadows* the
  // base getter — it implements it.
  final bool _supportsSiblingSwipe;
  @override
  bool get supportsSiblingSwipe => _supportsSiblingSwipe;

  final Widget Function(BuildContext context, WidgetRef ref) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      builder(context, ref);
}
