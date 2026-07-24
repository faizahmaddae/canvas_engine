import '../../../../l10n/app_localizations.dart';

/// Localizes a command's engine label for the history browser.
///
/// `EditorCommand.label` is deliberately an English, developer-facing
/// diagnostic string — the engine layer holds no localizations by the
/// repo's layering rule. The history browser is user-facing and the
/// product is Persian-first, so the raw label cannot be shown as-is.
/// This is the one place the two meet: a pure `AppLocalizations →
/// String` map at the presentation boundary, keyed on the stable
/// English label.
///
/// Unmapped labels fall through to the raw string rather than an empty
/// row — a new command with no case is legible in English until its key
/// is added, never invisible. No-op sentinels never reach here (a
/// no-op command produces no history entry), so they are not mapped.
String localizedHistoryLabel(AppLocalizations l10n, String raw) {
  // `Add ${layer.type}` is the only interpolated label; match the four
  // concrete types the modules emit, with a generic fallback.
  if (raw.startsWith('Add ')) {
    return switch (raw) {
      'Add text' => l10n.histAddText,
      'Add image' => l10n.histAddImage,
      'Add shape' => l10n.histAddShape,
      'Add paint' => l10n.histAddPaint,
      _ => l10n.histAddLayer,
    };
  }
  // `Composite (N)` — a bundle with no override falls back to the
  // generic combined-edit phrase; the overrides that matter (Delete,
  // Move, Resize, Rotate) carry their own labels handled below.
  if (raw.startsWith('Composite (')) return l10n.histCombinedEdit;

  return switch (raw) {
    'Delete layer' || 'Remove layer' => l10n.histRemoveLayer,
    'Rename layer' => l10n.histRenameLayer,
    'Reorder layer' => l10n.histReorderLayer,
    'Set layer opacity' => l10n.histOpacity,
    'Lock layer' => l10n.histLock,
    'Unlock layer' => l10n.histUnlock,
    'Show layer' => l10n.histShow,
    'Hide layer' => l10n.histHide,
    'Move' => l10n.histMove,
    'Resize' => l10n.histResize,
    'Rotate' => l10n.histRotate,
    'Transform layer' => l10n.histTransform,
    'Flip horizontally' => l10n.histFlipH,
    'Flip vertically' => l10n.histFlipV,
    'Canvas background' => l10n.histCanvasBg,
    'Canvas background mode' => l10n.histCanvasBgMode,
    'Resize canvas' => l10n.histResizeCanvas,
    'Edit text' => l10n.histEditText,
    'Text direction' => l10n.histTextDirection,
    'Text resize mode' => l10n.histTextResizeMode,
    'Image adjustments' => l10n.histImageAdjust,
    'Image border' => l10n.histImageBorder,
    'Image crop' => l10n.histImageCrop,
    'Image filter' => l10n.histImageFilter,
    'Image fit' => l10n.histImageFit,
    'Image shadow' => l10n.histImageShadow,
    'Image shape' => l10n.histImageShape,
    'Replace image' => l10n.histReplaceImage,
    'Restore image' => l10n.histRestoreImage,
    'Paint style' => l10n.histPaintStyle,
    'Paint resize behavior' => l10n.histPaintResize,
    'Shape fill' => l10n.histShapeFill,
    'Shape stroke' => l10n.histShapeStroke,
    'Shape radius' => l10n.histShapeRadius,
    'Shape shadow' => l10n.histShapeShadow,
    'Shape resize mode' => l10n.histShapeResizeMode,
    'Replace shape' => l10n.histReplaceShape,
    'Vignette' => l10n.histVignette,
    'Delete effect' => l10n.histEffectDelete,
    'Reorder effect' => l10n.histEffectReorder,
    'Restore effect' => l10n.histEffectRestore,
    'Toggle effect' => l10n.histEffectToggle,
    'Set base photo' => l10n.histBasePhotoSet,
    'Clear base photo' => l10n.histBasePhotoClear,
    'Photo project' => l10n.histProjectPhoto,
    'Design project' => l10n.histProjectDesign,
    _ => raw,
  };
}
