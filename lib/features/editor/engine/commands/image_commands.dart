import 'package:flutter/painting.dart';

import '../core/editor_document.dart';
import '../modules/image/image_layer.dart';
import 'editor_command.dart';

/// Sentinel returned from `invert` when the target layer is gone or
/// has changed type — applying it is a no-op so undo never crashes
/// on a stale id (e.g. a delete-then-undo race).
const EditorCommand _noop = _NoopCommand();

class _NoopCommand extends EditorCommand {
  const _NoopCommand();
  @override
  String get label => 'Noop';
  @override
  EditorDocument apply(EditorDocument doc) => doc;
  @override
  EditorCommand invert(EditorDocument before) => this;
}

/// Builds a fresh [ImageLayer] from [base], overwriting only the
/// fields explicitly passed in. Centralises the verbose constructor
/// call so adding a new field to [ImageLayer] is a one-line change
/// here, not eight identical edits across the command classes.
ImageLayer _rebuild(
  ImageLayer base, {
  ImageSource? source,
  BoxFit? fit,
  ImageMask? mask,
  Color? borderColor,
  double? borderWidth,
  Color? shadowColor,
  double? shadowBlur,
  Offset? shadowOffset,
  double? shadowOpacity,
  ImageAdjustments? adjustments,
  Rect? cropRect,
  ImageFilterPreset? filterPreset,
}) {
  return ImageLayer(
    id: base.id,
    transform: base.transform,
    source: source ?? base.source,
    fit: fit ?? base.fit,
    mask: mask ?? base.mask,
    borderColor: borderColor ?? base.borderColor,
    borderWidth: borderWidth ?? base.borderWidth,
    shadowColor: shadowColor ?? base.shadowColor,
    shadowBlur: shadowBlur ?? base.shadowBlur,
    shadowOffset: shadowOffset ?? base.shadowOffset,
    shadowOpacity: shadowOpacity ?? base.shadowOpacity,
    adjustments: adjustments ?? base.adjustments,
    cropRect: cropRect ?? base.cropRect,
    filterPreset: filterPreset ?? base.filterPreset,
    name: base.name,
    visible: base.visible,
    locked: base.locked,
  );
}

/// Swap an [ImageLayer]'s [ImageSource] in a single undoable step.
///
/// Used by the Image sub-tool's "Replace" action. Transform and all
/// other style fields are preserved so the user only changes the
/// pixels backing the layer, not its position/size on the canvas.
class ReplaceImageSourceCommand extends EditorCommand {
  const ReplaceImageSourceCommand({
    required this.layerId,
    required this.source,
  });

  final String layerId;
  final ImageSource source;

  @override
  String get label => 'Replace image';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    if (layer.source == source) return doc;
    // Replace resets [cropRect] to the full window. Carrying a
    // fractional crop across image swaps almost always lands on
    // the wrong sub-region (the new image has different framing /
    // composition / aspect), and a silent off-centre zoom is much
    // harder to recover from than a crop the user can re-apply.
    return doc.replaceLayer(_rebuild(
      layer,
      source: source,
      cropRect: ImageLayer.fullCrop,
    ));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    return ReplaceImageSourceCommand(layerId: layerId, source: layer.source);
  }
}

/// Swap an [ImageLayer]'s [ImageMask] (visible silhouette) in a
/// single undoable step. Source / transform / fit / border are
/// preserved so re-applying or undoing the mask never disturbs the
/// pixels or the layer's place on the canvas.
class SetImageMaskCommand extends EditorCommand {
  const SetImageMaskCommand({
    required this.layerId,
    required this.mask,
  });

  final String layerId;
  final ImageMask mask;

  @override
  String get label => 'Image shape';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    if (layer.mask == mask) return doc;
    return doc.replaceLayer(_rebuild(layer, mask: mask));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    return SetImageMaskCommand(layerId: layerId, mask: layer.mask);
  }
}

/// Swap an [ImageLayer]'s border colour and/or width in a single
/// undoable step. Either field may be left `null` to keep its
/// current value (e.g. changing colour shouldn't reset width). All
/// other fields (source, transform, fit, mask) are preserved.
class SetImageBorderCommand extends EditorCommand {
  const SetImageBorderCommand({
    required this.layerId,
    this.color,
    this.width,
  });

  final String layerId;
  final Color? color;
  final double? width;

  @override
  String get label => 'Image border';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    final newColor = color ?? layer.borderColor;
    final newWidth = width ?? layer.borderWidth;
    if (newColor == layer.borderColor && newWidth == layer.borderWidth) {
      return doc;
    }
    return doc.replaceLayer(_rebuild(
      layer,
      borderColor: newColor,
      borderWidth: newWidth,
    ));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    return SetImageBorderCommand(
      layerId: layerId,
      color: layer.borderColor,
      width: layer.borderWidth,
    );
  }
}

/// Swap an [ImageLayer]'s drop-shadow fields in a single undoable
/// step. All four fields (color/blur/offset/opacity) are nullable
/// so callers can change one knob at a time without disturbing the
/// others — picking a colour shouldn't reset the offset, sliding
/// blur shouldn't reset opacity, etc.
///
/// All other layer fields (source/transform/mask/border) are
/// preserved so toggling shadow leaves the rest of the image alone.
class SetImageShadowCommand extends EditorCommand {
  const SetImageShadowCommand({
    required this.layerId,
    this.color,
    this.blur,
    this.offset,
    this.opacity,
  });

  final String layerId;
  final Color? color;
  final double? blur;
  final Offset? offset;
  final double? opacity;

  @override
  String get label => 'Image shadow';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    final newColor = color ?? layer.shadowColor;
    final newBlur = blur ?? layer.shadowBlur;
    final newOffset = offset ?? layer.shadowOffset;
    final newOpacity = opacity ?? layer.shadowOpacity;
    if (newColor == layer.shadowColor &&
        newBlur == layer.shadowBlur &&
        newOffset == layer.shadowOffset &&
        newOpacity == layer.shadowOpacity) {
      return doc;
    }
    return doc.replaceLayer(_rebuild(
      layer,
      shadowColor: newColor,
      shadowBlur: newBlur,
      shadowOffset: newOffset,
      shadowOpacity: newOpacity,
    ));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    return SetImageShadowCommand(
      layerId: layerId,
      color: layer.shadowColor,
      blur: layer.shadowBlur,
      offset: layer.shadowOffset,
      opacity: layer.shadowOpacity,
    );
  }
}

/// Swap an [ImageLayer]'s colour-adjustment knobs (brightness /
/// contrast / saturation / exposure / warmth) in a single undoable
/// step. Each field is nullable so callers can change one knob at
/// a time without resetting the others — sliding contrast
/// shouldn't touch the brightness value the user just dialed in.
///
/// Set [live] to `true` for streaming slider updates: consecutive
/// `live` commands targeting the same layer + same field-set are
/// coalesced into a single undo entry by [mergeWith]. Preset taps
/// and final settle commands should leave [live] at its default
/// `false` so they push fresh history entries.
///
/// All other layer fields (source/transform/mask/border/shadow/
/// crop/filter) are preserved so adjustments compose cleanly with
/// every other Image sub-tool.
class SetImageAdjustmentsCommand extends EditorCommand {
  const SetImageAdjustmentsCommand({
    required this.layerId,
    this.brightness,
    this.contrast,
    this.saturation,
    this.exposure,
    this.warmth,
    this.live = false,
  });

  final String layerId;
  final double? brightness;
  final double? contrast;
  final double? saturation;
  final double? exposure;
  final double? warmth;

  /// When true, marks this command as part of a live drag stream
  /// (e.g. an adjustment slider). Successive `live` commands of
  /// the same field-set against the same layer collapse into a
  /// single history entry instead of N-per-pixel-of-drag.
  final bool live;

  @override
  String get label => 'Image adjustments';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    final current = layer.adjustments;
    final next = current.copyWith(
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      exposure: exposure,
      warmth: warmth,
    );
    if (next == current) return doc;
    return doc.replaceLayer(_rebuild(layer, adjustments: next));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    final adj = layer.adjustments;
    return SetImageAdjustmentsCommand(
      layerId: layerId,
      brightness: adj.brightness,
      contrast: adj.contrast,
      saturation: adj.saturation,
      exposure: adj.exposure,
      warmth: adj.warmth,
    );
  }

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetImageAdjustmentsCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    // Field-set must match across the whole stream so a brightness
    // drag never silently swallows the trailing edge of a contrast
    // drag the user just released.
    if ((brightness == null) != (previous.brightness == null)) return null;
    if ((contrast == null) != (previous.contrast == null)) return null;
    if ((saturation == null) != (previous.saturation == null)) return null;
    if ((exposure == null) != (previous.exposure == null)) return null;
    if ((warmth == null) != (previous.warmth == null)) return null;
    return this;
  }
}

/// Swap an [ImageLayer]'s [ImageLayer.cropRect] in a single
/// undoable step. The rect is normalised (0..1 on each axis) and
/// is clamped to that range here so misbehaving callers can't
/// store an invalid crop.
///
/// All other layer fields (source/transform/fit/mask/border/
/// shadow/adjustments/filter) are preserved so cropping never
/// disturbs the rest of the layer's appearance or its place on the
/// canvas.
class SetImageCropCommand extends EditorCommand {
  const SetImageCropCommand({
    required this.layerId,
    required this.cropRect,
  });

  final String layerId;
  final Rect cropRect;

  @override
  String get label => 'Image crop';

  Rect _sanitise(Rect r) {
    final l = r.left.clamp(0.0, 1.0);
    final t = r.top.clamp(0.0, 1.0);
    final right = r.right.clamp(0.0, 1.0);
    final b = r.bottom.clamp(0.0, 1.0);
    // Reject zero-area rects by snapping to the full window — the
    // renderer also guards against this, but keeping the document
    // model self-consistent avoids surprising edge cases on
    // serialisation / undo round-trips.
    if (right <= l || b <= t) return ImageLayer.fullCrop;
    return Rect.fromLTRB(l, t, right, b);
  }

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    final next = _sanitise(cropRect);
    if (next == layer.cropRect) return doc;
    return doc.replaceLayer(_rebuild(layer, cropRect: next));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    return SetImageCropCommand(layerId: layerId, cropRect: layer.cropRect);
  }
}

/// Swap an [ImageLayer]'s [BoxFit] in a single undoable step. Used
/// by the Crop tab's Fill / Fit chips so the user can flip how the
/// image lands inside the crop window without resizing the layer.
class SetImageFitCommand extends EditorCommand {
  const SetImageFitCommand({
    required this.layerId,
    required this.fit,
  });

  final String layerId;
  final BoxFit fit;

  @override
  String get label => 'Image fit';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    if (layer.fit == fit) return doc;
    return doc.replaceLayer(_rebuild(layer, fit: fit));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    return SetImageFitCommand(layerId: layerId, fit: layer.fit);
  }
}

/// Swap an [ImageLayer]'s curated colour-grade [ImageFilterPreset]
/// in a single undoable step. Filter is independent of the
/// brightness/contrast/etc. adjustment knobs — selecting a preset
/// never overwrites the user's manual tuning, and clearing a
/// preset (passing [ImageFilterPreset.none]) doesn't disturb the
/// adjustments either.
///
/// All other layer fields (source/transform/fit/mask/border/
/// shadow/crop) are preserved.
class SetImageFilterCommand extends EditorCommand {
  const SetImageFilterCommand({
    required this.layerId,
    required this.filterPreset,
  });

  final String layerId;
  final ImageFilterPreset filterPreset;

  @override
  String get label => 'Image filter';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    if (layer.filterPreset == filterPreset) return doc;
    return doc.replaceLayer(_rebuild(layer, filterPreset: filterPreset));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    return SetImageFilterCommand(
      layerId: layerId,
      filterPreset: layer.filterPreset,
    );
  }
}
