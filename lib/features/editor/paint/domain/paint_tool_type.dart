import 'package:flutter/material.dart';

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
  freestyle(label: 'Freestyle', icon: Icons.gesture_rounded, available: true),
  arrow(label: 'Arrow', icon: Icons.arrow_right_alt_rounded, available: true),
  line(label: 'Line', icon: Icons.show_chart_rounded, available: true),
  rectangle(
    label: 'Rectangle',
    icon: Icons.crop_square_rounded,
    available: true,
  ),
  circle(label: 'Circle', icon: Icons.circle_outlined, available: true),
  eraser(
    label: 'Eraser',
    icon: Icons.cleaning_services_outlined,
    available: true,
  ),
  dashLine(
    label: 'Dash line',
    icon: Icons.linear_scale_rounded,
    available: true,
  ),
  dashDotLine(
    label: 'Dash-dot',
    icon: Icons.more_horiz_rounded,
    available: true,
  ),
  hexagon(label: 'Hexagon', icon: Icons.hexagon_outlined, available: true),
  polygon(label: 'Polygon', icon: Icons.pentagon_outlined, available: true),
  blur(label: 'Blur', icon: Icons.blur_on_rounded, available: true);

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
