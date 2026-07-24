/// Template photo slots — image layers that ship inside a template
/// carrying bundled placeholder pixels until the user drops their own
/// photo in.
///
/// **Why there is no persisted `isPlaceholder` field.** "Placeholder"
/// is not a property the document needs to remember: it is entirely
/// derivable from the layer's own [ImageSource]. A slot is unfilled
/// exactly while it still points at one of our bundled placeholder
/// assets, and the existing [ReplaceImageSourceCommand] swaps that
/// source for an [ImageSource.file] — so the state flips as a side
/// effect of the replace the user already performs, with no second
/// field to keep in sync, no schema bump, and no undo path that could
/// restore the pixels but not the flag.
///
/// The trade is that a user who deliberately picks the placeholder art
/// *as content* keeps the affordance. That is acceptable: the asset is
/// not reachable from the image picker, only from a template.
library;

import '../../editor/engine/core/editor_layer.dart';
import '../../editor/engine/modules/image/image_layer.dart';

/// Directory holding every bundled placeholder image. Membership in
/// this directory — not an allow-list of individual files — is what
/// marks a source as a placeholder, so adding a second slot artwork
/// stays a one-file change.
const String kTemplatePlaceholderAssetDir = 'assets/templates/_placeholder/';

/// The default photo-slot artwork: a warm paper-neutral tile with a
/// quiet framed-photo glyph, low-contrast on purpose so template text
/// composed over it stays readable before the swap.
const String kTemplatePhotoSlotAsset =
    '${kTemplatePlaceholderAssetDir}photo_slot.png';

/// True when [source] still points at bundled placeholder pixels.
bool isTemplatePlaceholderSource(ImageSource source) {
  final asset = source.assetName;
  return asset != null && asset.startsWith(kTemplatePlaceholderAssetDir);
}

/// True when [layer] is an image layer whose slot the user has not
/// filled yet. Accepts any [EditorLayer] so canvas chrome can map over
/// the whole layer list without pre-filtering by type.
bool isTemplatePlaceholderImage(EditorLayer layer) =>
    layer is ImageLayer && isTemplatePlaceholderSource(layer.source);
