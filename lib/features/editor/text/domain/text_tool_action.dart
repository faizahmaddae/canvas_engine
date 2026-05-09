import 'package:flutter/material.dart';

/// Toolbar control identifiers shown while the user is in **text mode**.
///
/// Modeled as an enum (rather than ad-hoc widgets) so:
///   * The toolbar can iterate over a single source of truth.
///   * Future controls plug in with one entry per addition — no other
///     call-site changes.
///   * Tests can assert which controls are exposed.
enum TextToolAction {
  color(label: 'Color', icon: Icons.format_color_text_rounded),
  size(label: 'Size', icon: Icons.format_size_rounded),
  bold(label: 'Bold', icon: Icons.format_bold_rounded),
  italic(label: 'Italic', icon: Icons.format_italic_rounded),
  align(label: 'Align', icon: Icons.format_align_center_rounded),
  letterSpacing(label: 'Spacing', icon: Icons.space_bar_rounded),
  lineHeight(label: 'Line', icon: Icons.format_line_spacing_rounded);

  const TextToolAction({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
