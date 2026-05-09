/// Stable identifier for an editor mode.
///
/// Phase 1 only declares the modes that exist today. New modes
/// (crop, filters, adjust, sticker, …) append to this enum without
/// touching presentation code — the toolbar host resolves them via
/// the registry.
enum ModeId {
  /// Default top-level toolbar (paint / text / add / shape / …).
  main,

  /// Paint mode — owns the paint tool strip and its sub-tools.
  paint,

  /// Text mode — active when a text layer is selected or the user
  /// explicitly entered text editing.
  text,
}
