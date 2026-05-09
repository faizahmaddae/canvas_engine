/// Image format the user can export the document as. Lives in the
/// application layer because the engine has separate per-format
/// exporters ([DocumentPngExporter], [DocumentJpgExporter]) and the
/// UI needs a single value to switch between them.
enum ExportFormat {
  png('PNG', 'png'),
  jpg('JPG', 'jpg');

  const ExportFormat(this.label, this.extension);

  /// Display label for the picker (e.g. "PNG").
  final String label;

  /// Lowercase file extension *without* the leading dot — used by
  /// filename builders and MIME lookup.
  final String extension;

  String get mimeType => switch (this) {
        ExportFormat.png => 'image/png',
        ExportFormat.jpg => 'image/jpeg',
      };

  /// True when the format supports a quality / compression knob. UI
  /// uses this to decide whether to reveal the quality slider.
  bool get supportsQuality => switch (this) {
        ExportFormat.png => false,
        ExportFormat.jpg => true,
      };
}
