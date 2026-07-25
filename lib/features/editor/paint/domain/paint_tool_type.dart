import 'package:flutter/material.dart';
import '../../../../app/theme/app_icons.dart';

/// Catalog of every paint / annotation tool the editor will eventually
/// support.
///
/// Each entry carries its own UI metadata (`icon`, `label`) and a phase
/// flag (`available`) so that "coming soon" tools can be surfaced in the
/// sub-tool panel without each call-site re-deriving that knowledge.
///
/// Adding a new tool is a single-line change here — the panel, the
/// controller, persistence, and any future tool routing all key off
/// this enum.
enum PaintToolType {
  freestyle(label: 'Freestyle', icon: AppIcons.freehandTool, available: true),
  arrow(label: 'Arrow', icon: AppIcons.shapeArrow, available: true),
  line(label: 'Line', icon: AppIcons.lineTool, available: true),
  rectangle(label: 'Rectangle', icon: AppIcons.squareShape, available: true),
  circle(label: 'Circle', icon: AppIcons.shapeCircle, available: true),
  eraser(label: 'Eraser', icon: AppIcons.eraserTool, available: true),
  dashLine(label: 'Dash line', icon: AppIcons.dashStyle, available: true),
  dashDotLine(label: 'Dash-dot', icon: AppIcons.moreActions, available: true),
  hexagon(label: 'Hexagon', icon: AppIcons.shapeHexagon, available: true),
  polygon(label: 'Polygon', icon: AppIcons.polygonTool, available: true),
  blur(label: 'Blur', icon: AppIcons.blur, available: true);

  const PaintToolType({
    required this.label,
    required this.icon,
    required this.available,
  });

  final String label;
  final IconData icon;

  /// Whether the tool is wired up in the current build phase.
  /// Disabled tools render as dimmed placeholders.
  final bool available;
}
