import 'package:flutter/material.dart';

/// Top-level categories for text editing.
///
/// These categories drive the More panel shown above the dock when a
/// text layer is selected. Each one maps to a focused body in the
/// expanded panel.
///
///   * [font]       — language, font family, font size
///   * [style]      — color, B / I / U, opacity
///   * [background] — fill behind the text (color, padding, radius)
///   * [border]     — glyph outline (Canva-style stroke)
///   * [shadow]     — drop shadow (color, blur, offset)
///   * [layout]     — alignment, line height, letter spacing
///   * [behavior]   — resize mode (scale text vs resize box)
enum TextToolCategory {
  font(label: 'Font', icon: Icons.title_rounded),
  style(label: 'Style', icon: Icons.format_bold_rounded),
  background(label: 'Background', icon: Icons.format_color_fill_rounded),
  border(label: 'Border', icon: Icons.border_outer_rounded),
  shadow(label: 'Shadow', icon: Icons.blur_on_rounded),
  layout(label: 'Layout', icon: Icons.format_align_center_rounded),
  behavior(label: 'Behavior', icon: Icons.aspect_ratio_rounded);

  const TextToolCategory({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
