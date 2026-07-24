import 'package:flutter/material.dart';

import '../../engine/modules/text/text_layer.dart';

/// Snapshot of the user's current text-tool configuration.
///
/// Holds **two** distinct concerns:
///   * Mode state: whether the text panel is open (`panelOpen`).
///   * Default style: [defaultStyle] — applied to NEW text layers
///     created while in text mode. Changing it without an active
///     selection updates the default; with a selection, the controller
///     also pushes the change to the selected layer (see
///     `TextToolController.applyStyleChange`).
///
/// Adding a new style dimension (font family, stroke, shadow, …) is a
/// single field on [TextStyleSpec] + a single setter on the
/// controller.
///
/// Split out of `text_tool_controller.dart` (roadmap 5.6): this is the
/// dock's UI state *model*; the mutators that drive it stay on
/// `TextToolController`, mirroring the `EditorDocument` /
/// `DocumentController` split used everywhere else in the editor.
@immutable
class TextSession {
  const TextSession({
    this.panelOpen = false,
    this.openSheet,
    this.defaultStyle = const TextStyleSpec(),
    this.recentColors = const <Color>[],
    this.selectedSizePreset,
  });

  static const TextSession initial = TextSession();

  /// Whether the text-mode dock is currently shown.
  final bool panelOpen;

  /// Identifier of the tool sheet currently rendered inside the
  /// dock's expanded slot (e.g. `'style'`, `'background'`,
  /// `'border'`, `'size'`, …). `null` means no sheet is open and
  /// the dock collapses to just the tile strip. The sheet is
  /// rendered **inline** in the dock so the canvas reflows above
  /// it instead of being overlaid — mirrors Canva's mobile UX.
  final String? openSheet;

  /// Style applied to newly-added text layers. Also represents the
  /// "last known good" style when nothing is selected — the toolbar
  /// always renders against this when there's no selected text layer.
  final TextStyleSpec defaultStyle;

  /// MRU list of colours the user picked from the picker. Capped at
  /// [recentsCap]; index 0 is the most recently used. Same convention
  /// as paint, so the picker UX feels identical between modes.
  final List<Color> recentColors;

  /// Sticky highlight for the Text Size sub-tool's S/M/L/XL/XXL chip
  /// row. Stored here (rather than in a transient `StatefulWidget`
  /// inside the sheet) because the sheet body widget can be
  /// dismounted and remounted across rebuilds — e.g. when the
  /// selected text layer momentarily goes null between a
  /// `setFontSize` write and the resulting auto-resize. Keyed by
  /// the layer id so switching to a different text layer does not
  /// inherit the previous layer's pinned preset. Cleared by any
  /// non-preset font-size mutation (A+/A−/slider/exact px).
  final ({String label, String layerId})? selectedSizePreset;

  static const int recentsCap = 8;

  TextSession copyWith({
    bool? panelOpen,
    String? openSheet,
    bool clearOpenSheet = false,
    TextStyleSpec? defaultStyle,
    List<Color>? recentColors,
    ({String label, String layerId})? selectedSizePreset,
    bool clearSelectedSizePreset = false,
  }) {
    return TextSession(
      panelOpen: panelOpen ?? this.panelOpen,
      openSheet: clearOpenSheet ? null : (openSheet ?? this.openSheet),
      defaultStyle: defaultStyle ?? this.defaultStyle,
      recentColors: recentColors ?? this.recentColors,
      selectedSizePreset: clearSelectedSizePreset
          ? null
          : (selectedSizePreset ?? this.selectedSizePreset),
    );
  }
}
