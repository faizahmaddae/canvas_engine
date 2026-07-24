import 'dart:math' as math;

import '../engine/core/editor_document.dart';

/// The canvas size every hand-tuned preset in the dock was authored
/// against — the app's default document (1080 × 1080).
const double kPresetReferenceCanvasSide = 1080;

/// Scale a preset value authored on the reference canvas to the
/// document actually open (tb4 6/14).
///
/// Sticker sizes, corner radii and shadow blur/offset were all
/// absolute pixel numbers. They read correctly on a 1080 square and
/// nowhere else: on a 4000px print canvas the "XL" sticker landed at
/// a tenth of the size the label promises, and on a 400px canvas
/// "Soft" shadow swallowed the layer. Every preset row that names a
/// SIZE (rather than a ratio) resolves through this so the words keep
/// meaning the same thing at any document scale.
///
/// Uses the shorter side so a wide banner doesn't inflate presets
/// past its own height.
double canvasScaledPreset(double reference, EditorDocument doc) {
  final side = math.min(doc.width, doc.height);
  if (side <= 0) return reference;
  return reference * (side / kPresetReferenceCanvasSide);
}
