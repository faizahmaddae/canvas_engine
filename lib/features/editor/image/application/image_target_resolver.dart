// Pure target-resolution logic shared by the main-toolbar's image
// actions (Crop / Filters / Adjust). Lives outside the screen widget
// so it can be unit-tested without pumping the full editor.

import '../../engine/core/editor_document.dart';
import '../../engine/modules/image/image_layer.dart';

/// Outcome of resolving which [ImageLayer] a main-toolbar image
/// action should target.
sealed class ImageTargetResolution {
  const ImageTargetResolution();
}

/// The current selection is already an [ImageLayer]; use it as-is.
class ImageTargetSelected extends ImageTargetResolution {
  const ImageTargetSelected(this.layer);
  final ImageLayer layer;
}

/// No image is selected but the document contains exactly one
/// [ImageLayer]. Callers should auto-select [layer] and then proceed.
class ImageTargetAutoSelect extends ImageTargetResolution {
  const ImageTargetAutoSelect(this.layer);
  final ImageLayer layer;
}

/// Document has no [ImageLayer]s; show 'Add an image first.'.
class ImageTargetNoneAvailable extends ImageTargetResolution {
  const ImageTargetNoneAvailable();
}

/// Document has multiple [ImageLayer]s and no fallback (selection,
/// only-one, or base-photo) applies. The full candidate list is
/// carried so the caller can present a chooser sheet.
class ImageTargetAmbiguous extends ImageTargetResolution {
  const ImageTargetAmbiguous(this.candidates);
  final List<ImageLayer> candidates;
}

/// Resolve which [ImageLayer] (if any) a main-toolbar image action
/// should operate on. See [ImageTargetResolution] subtypes for the
/// four possible outcomes — the resolver itself is pure (no
/// snackbars, no selection mutation) so callers can adapt the
/// outcome to their UI.
///
/// Priority order:
///   1. Selected layer if it is an [ImageLayer].
///   2. The only [ImageLayer] in the document, if exactly one
///      exists.
///   3. The document's *base photo* (set by the import flow on the
///      first imported image) when it still resolves to an
///      [ImageLayer]. This is what keeps Crop / Filters / Adjust
///      pointed at the user's main photo even when they have
///      multiple images and the current selection is a sticker /
///      text overlay.
///   4. [ImageTargetAmbiguous] -- multiple images, no signal which
///      one the user wants. Caller should disambiguate (e.g. show
///      a chooser sheet).
///   5. [ImageTargetNoneAvailable] -- the document has no images
///      at all.
ImageTargetResolution resolveImageTarget(
  EditorDocument doc, {
  required String? selectedId,
}) {
  if (selectedId != null) {
    final selected = doc.layerById(selectedId);
    if (selected is ImageLayer) return ImageTargetSelected(selected);
  }
  final images = doc.layers.whereType<ImageLayer>().toList(growable: false);
  if (images.isEmpty) return const ImageTargetNoneAvailable();
  if (images.length == 1) return ImageTargetAutoSelect(images.single);

  final baseId = doc.basePhotoLayerId;
  if (baseId != null) {
    final base = doc.layerById(baseId);
    if (base is ImageLayer) return ImageTargetAutoSelect(base);
  }
  return ImageTargetAmbiguous(images);
}
