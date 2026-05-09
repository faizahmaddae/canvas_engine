/// Output-resolution presets surfaced to the user. Each maps to a
/// `pixelRatio` passed straight to [DocumentPngExporter] — the engine
/// stays mode-agnostic; selection logic lives entirely in the UI.
///
/// Definitions are deliberately literal so users can reason about the
/// result up-front:
///
///   * [original] — `1×` — exported pixel dimensions equal the logical
///     canvas dimensions exactly. Smallest file, fastest export.
///   * [high] — `2×` — doubles each axis (4× pixel count). Good for
///     retina screens and most social platforms.
///   * [ultra] — `3×` — triples each axis (9× pixel count). Print or
///     billboard-grade output.
enum ExportQuality {
  original(1.0, 'Original size'),
  high(2.0, 'High quality'),
  ultra(3.0, 'Ultra quality');

  const ExportQuality(this.pixelRatio, this.label);

  final double pixelRatio;
  final String label;

  /// Short multiplier badge — e.g. `"1×"`, `"2×"`, `"3×"`.
  String get multiplier => '${pixelRatio.toStringAsFixed(0)}×';
}
