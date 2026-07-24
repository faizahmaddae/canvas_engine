/// What the user asked the export flow to *do* — the exit intent they
/// chose in the export sheet, carried through to the preview.
///
/// The sheet offers exactly these two ways out (plus "cancel", which is
/// not an intent — it's the absence of one). Before this existed the
/// preview always presented the same generic action row, so a user who
/// tapped "Preview & Share" had to find and tap Share a second time.
/// The preview now makes the chosen intent its primary action while
/// keeping the other one reachable, so the flow reads as one decision
/// confirmed rather than two decisions taken.
///
/// Lives in the application layer (not next to `ExportPreviewAction`,
/// which is a presentation-level *result*) because it is the export
/// flow's own vocabulary: the sheet, the preview, and any future entry
/// point (a share-sheet shortcut, a "save a copy" menu item) all speak
/// it.
enum ExportIntent {
  /// Hand the bytes to the system share sheet.
  share,

  /// Write the bytes to the device photo library.
  save,
}
