import '../../../../core/constants/engine_constants.dart';

/// Capability flags used by the engine to decide which interactions are
/// allowed for a given layer, and what constraints apply. New layer types
/// declare their capabilities without the interaction/rendering code
/// knowing about them specifically.
class LayerCapabilities {
  const LayerCapabilities({
    this.movable = true,
    this.resizable = true,
    this.rotatable = true,
    this.deletable = true,
    this.editable = true,
    this.keepsAspectRatio = false,
    this.minWidth = EngineConstants.minLayerSize,
    this.minHeight = EngineConstants.minLayerSize,
  });

  final bool movable;
  final bool resizable;
  final bool rotatable;
  final bool deletable;

  /// Whether the layer supports a content-editing mode (e.g. tap-to-edit
  /// for text). Purely a capability flag consumed by presentation code —
  /// the interaction engine itself does not read it, since editing is a
  /// module-specific concern.
  final bool editable;

  /// When true, resize handles constrain proportions.
  final bool keepsAspectRatio;

  /// Per-layer minimum size. Engine-wide floor is
  /// [EngineConstants.minLayerSize]; layers that need more (e.g. text that
  /// must fit its shortest word) can raise these.
  final double minWidth;
  final double minHeight;

  /// Capabilities for a [TextResizeMode.scaleText] layer. Aspect ratio
  /// is locked so corner-drag uniformly scales the rendered text via
  /// [FittedBox] without reflowing or wrapping. The box is always
  /// sized to the natural text bounds by `TextToolController`, so the
  /// minimum stays small \u2014 it just guards against a degenerate
  /// zero-size box during a transient empty-content state.
  static const textScale = LayerCapabilities(
    keepsAspectRatio: true,
    minWidth: 8,
    minHeight: 8,
  );

  /// Capabilities for a [TextResizeMode.resizeBox] layer. Aspect is
  /// free so the user can change the wrap width independently of
  /// height. Minimum width is wider than [textScale] to keep the box
  /// useful as a paragraph container; minimum height stays small
  /// because the controller auto-fits height to the wrapped content.
  static const textBox = LayerCapabilities(
    minWidth: 40,
    minHeight: 8,
  );

  /// Backwards-compatible alias \u2014 some callers may still reference
  /// `LayerCapabilities.text`. Resolves to [textScale] (the default
  /// resize mode for new text layers).
  static const text = textScale;
}
