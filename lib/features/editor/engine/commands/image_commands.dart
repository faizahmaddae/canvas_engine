import 'package:flutter/painting.dart';

import '../core/editor_document.dart';
import '../core/layer_mask.dart';
import '../effects/editor_effect.dart';
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
    return doc.replaceLayer(layer.copyAll(
      source: source,
      cropRect: ImageLayer.fullCrop,
    ));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    // Capture the pre-apply [cropRect] alongside the source so undo
    // restores BOTH atomically. `apply` deliberately resets crop to
    // [ImageLayer.fullCrop]; without restoring it here, undo would
    // bring back the source but silently leave the user's crop wiped.
    return _RestoreImageSourceCommand(
      layerId: layerId,
      source: layer.source,
      cropRect: layer.cropRect,
    );
  }

  @override
  int get estimatedByteSize => source.estimatedByteSize;
}

/// Internal inverse of [ReplaceImageSourceCommand]. Restores both
/// [ImageLayer.source] and [ImageLayer.cropRect] in one step so the
/// pre-apply state is fully recovered. Not exposed publicly because
/// callers should never want to "set source AND crop" as a forward
/// edit — the only legitimate use is undoing a replace.
class _RestoreImageSourceCommand extends EditorCommand {
  const _RestoreImageSourceCommand({
    required this.layerId,
    required this.source,
    required this.cropRect,
  });

  final String layerId;
  final ImageSource source;
  final Rect cropRect;

  @override
  String get label => 'Restore image';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    if (layer.source == source && layer.cropRect == cropRect) return doc;
    return doc.replaceLayer(layer.copyAll(
      source: source,
      cropRect: cropRect,
    ));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    // The forward of this restore is just a public replace — its own
    // apply will reset crop back to fullCrop, matching the original
    // ReplaceImageSourceCommand behaviour. Redo therefore round-trips
    // exactly, including the crop reset.
    return ReplaceImageSourceCommand(layerId: layerId, source: layer.source);
  }

  @override
  int get estimatedByteSize => source.estimatedByteSize;
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
    return doc.replaceLayer(layer.copyAll(mask: mask));
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
///
/// Set [live] to `true` for streaming slider / colour-picker
/// updates: consecutive `live` commands targeting the same layer
/// + same field-set are coalesced into a single undo entry by
/// [mergeWith]. Discrete edits (palette taps, thickness chips)
/// should leave [live] at its default `false` so each becomes its
/// own history entry.
class SetImageBorderCommand extends EditorCommand {
  const SetImageBorderCommand({
    required this.layerId,
    this.color,
    this.width,
    this.live = false,
  });

  final String layerId;
  final Color? color;
  final double? width;

  /// When true, marks this command as part of a live drag stream
  /// (slider / colour-picker live preview). Successive `live`
  /// commands of the same field-set against the same layer
  /// collapse into a single history entry instead of N-per-frame.
  final bool live;

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
    return doc.replaceLayer(layer.copyAll(
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

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetImageBorderCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    // Field-set must match across the whole stream so a colour
    // drag never silently swallows the trailing edge of a width
    // drag the user just released. Mirrors
    // SetImageAdjustmentsCommand.mergeWith.
    if ((color == null) != (previous.color == null)) return null;
    if ((width == null) != (previous.width == null)) return null;
    return this;
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
///
/// Set [live] to `true` for streaming slider / colour-picker
/// updates: consecutive `live` commands targeting the same layer
/// + same field-set are coalesced into a single undo entry by
/// [mergeWith]. Discrete edits (preset taps, palette taps,
/// direction-pad taps) should leave [live] at its default
/// `false` so each becomes its own history entry.
class SetImageShadowCommand extends EditorCommand {
  const SetImageShadowCommand({
    required this.layerId,
    this.color,
    this.blur,
    this.offset,
    this.opacity,
    this.live = false,
  });

  final String layerId;
  final Color? color;
  final double? blur;
  final Offset? offset;
  final double? opacity;

  /// When true, marks this command as part of a live drag stream
  /// (blur / opacity slider, colour-picker live preview).
  /// Successive `live` commands of the same field-set against the
  /// same layer collapse into a single history entry.
  final bool live;

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
    return doc.replaceLayer(layer.copyAll(
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

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetImageShadowCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    // Field-set must match across the whole stream so a blur drag
    // never silently swallows an opacity drag (or vice versa).
    // Mirrors SetImageAdjustmentsCommand.mergeWith.
    if ((color == null) != (previous.color == null)) return null;
    if ((blur == null) != (previous.blur == null)) return null;
    if ((offset == null) != (previous.offset == null)) return null;
    if ((opacity == null) != (previous.opacity == null)) return null;
    return this;
  }
}

/// Legacy render order of the five derived colour adjustments
/// (exposure → warmth → saturation → contrast → brightness), i.e.
/// the order [ImageAdjustments.toEffectStack] emits. Used to pick a
/// canonical insertion point when a slider gains a value and no live
/// instance of its effect exists on the stack yet.
const Map<String, int> _derivedRank = <String, int>{
  'exposure': 0,
  'warmth': 1,
  'saturation': 2,
  'contrast': 3,
  'brightness': 4,
};

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
    // Read the current per-knob values off the effect stack so an
    // omitted parameter preserves whatever the user already had.
    // This is the moral equivalent of the old
    // `current.copyWith(...)`, just sourced from the canonical
    // location instead of a sibling field.
    final current = ImageAdjustments.fromEffectStack(layer.effects);
    final next = current.copyWith(
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      exposure: exposure,
      warmth: warmth,
    );
    if (next == current) return doc;
    // Surgically edit the live (enabled, unmasked) derived effects in
    // place instead of strip-and-regenerate. The old rebuild deleted
    // every derived-type effect — including *disabled* ones (the
    // eyeball toggle in the Effects panel) and *masked* ones, which
    // [ImageAdjustments.fromEffectStack] never read — so a contrast
    // drag silently destroyed a disabled brightness effect. It also
    // re-sank the derived cluster to the bottom in canonical order,
    // discarding any user reordering from the Effects panel.
    final merged = List<EditorEffect>.of(layer.effects.effects);
    void surgery({
      required String type,
      required double value,
      required double identity,
      required EditorEffect Function(double amount) build,
      required double Function(EditorEffect e) amountOf,
    }) {
      // "Live" = the instance the slider actually drives, mirroring
      // fromEffectStack's read (last enabled, unmasked one wins).
      final idx = merged.lastIndexWhere(
        (e) => e.type == type && e.enabled && e.mask == null,
      );
      if (value == identity) {
        // Identity values are removed, not stored, so "drag the
        // slider back to 0" round-trips byte-identical to never
        // having touched it.
        if (idx >= 0) merged.removeAt(idx);
        return;
      }
      if (idx >= 0) {
        if (amountOf(merged[idx]) != value) merged[idx] = build(value);
        return;
      }
      // No live instance: insert after the last live derived effect
      // that precedes this knob in the legacy render order
      // (exposure → warmth → saturation → contrast → brightness),
      // so an un-reordered stack keeps its canonical shape.
      final rank = _derivedRank[type]!;
      var insertAt = 0;
      for (var i = 0; i < merged.length; i++) {
        final e = merged[i];
        final r = _derivedRank[e.type];
        if (r == null || !e.enabled || e.mask != null) continue;
        if (r < rank) insertAt = i + 1;
      }
      merged.insert(insertAt, build(value));
    }

    surgery(
      type: 'exposure',
      value: next.exposure,
      identity: 0,
      build: (v) => ExposureEffect(amount: v),
      amountOf: (e) => (e as ExposureEffect).amount,
    );
    surgery(
      type: 'warmth',
      value: next.warmth,
      identity: 0,
      build: (v) => WarmthEffect(amount: v),
      amountOf: (e) => (e as WarmthEffect).amount,
    );
    surgery(
      type: 'saturation',
      value: next.saturation,
      identity: 1,
      build: (v) => SaturationEffect(amount: v),
      amountOf: (e) => (e as SaturationEffect).amount,
    );
    surgery(
      type: 'contrast',
      value: next.contrast,
      identity: 1,
      build: (v) => ContrastEffect(amount: v),
      amountOf: (e) => (e as ContrastEffect).amount,
    );
    surgery(
      type: 'brightness',
      value: next.brightness,
      identity: 0,
      build: (v) => BrightnessEffect(amount: v),
      amountOf: (e) => (e as BrightnessEffect).amount,
    );
    // copyWith preserves the stack mask by construction — rebuilding
    // via the bare constructor would silently drop a set stackMask.
    final nextEffects = layer.effects
        .copyWith(effects: List<EditorEffect>.unmodifiable(merged));
    return doc.replaceLayer(layer.copyAll(effects: nextEffects));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    // Restore the entire pre-apply stack verbatim rather than
    // replaying the five knob values: a knob dragged to identity
    // *removes* its effect, and re-inserting it by value on undo
    // would land at the canonical position instead of wherever the
    // user had reordered it. Only a snapshot reproduces `before`
    // exactly (ordering, disabled entries, masks, stack mask).
    return _RestoreEffectsCommand(layerId: layerId, effects: layer.effects);
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

/// Verbatim restore of a layer's whole [EffectStack]. The inverse of
/// [SetImageAdjustmentsCommand]: surgical knob edits can remove or
/// insert effects, so only a full-stack snapshot reproduces the
/// pre-command state — ordering, disabled entries, per-effect masks,
/// and the stack mask — exactly on undo.
class _RestoreEffectsCommand extends EditorCommand {
  const _RestoreEffectsCommand({required this.layerId, required this.effects});

  final String layerId;
  final EffectStack effects;

  @override
  String get label => 'Image adjustments';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    return doc.replaceLayer(layer.copyAll(effects: effects));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    return _RestoreEffectsCommand(layerId: layerId, effects: layer.effects);
  }
}

/// Set or update the [VignetteEffect] on an [ImageLayer]. Each
/// field is nullable so callers can change one knob at a time
/// without resetting the others — the same convention as
/// [SetImageAdjustmentsCommand].
///
/// Vignette is the first non-colour-matrix effect on the stack, so
/// its lifecycle is slightly different: when the resulting effect
/// is the identity (`intensity == 0`), it is *removed* from the
/// stack entirely so byte-identity with a vignette-free document
/// is preserved. Bringing the slider back above 0 inserts a fresh
/// effect at the *end* of the stack (top of the visual order),
/// which matches Snapseed / Lightroom: vignette always renders on
/// top of every other effect.
///
/// [live] follows the same merge rules as
/// [SetImageAdjustmentsCommand]: live drags collapse into a single
/// undo entry per stream as long as the field-set is stable.
class SetImageVignetteCommand extends EditorCommand {
  const SetImageVignetteCommand({
    required this.layerId,
    this.intensity,
    this.feather,
    this.color,
    this.live = false,
  });

  final String layerId;
  final double? intensity;
  final double? feather;
  final Color? color;
  final bool live;

  @override
  String get label => 'Vignette';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    // Locate any existing vignette on the stack. Per the doc-comment
    // above, vignette always sits at the top (= last entry) of the
    // stack; if the user has somehow pushed other effects on top,
    // we still address it positionally and leave the rest alone.
    final existing = layer.effects.effects
        .whereType<VignetteEffect>()
        .cast<VignetteEffect?>()
        .firstWhere((_) => true, orElse: () => null);
    final base = existing ??
        const VignetteEffect(
          intensity: VignetteEffect.defaultIntensity,
          feather: VignetteEffect.defaultFeather,
        );
    final next = base.copyWith(
      intensity: intensity,
      feather: feather,
      color: color,
    );
    if (existing != null && next == existing) return doc;
    final keep = layer.effects.effects
        .where((e) => e is! VignetteEffect)
        .toList(growable: true);
    // Identity vignette = no effect on the stack. This is what keeps
    // a "drag the slider then drag it back to 0" round-trip
    // byte-identical to never having touched the slider.
    final List<EditorEffect> merged = next.contributes
        ? <EditorEffect>[...keep, next]
        : keep;
    if (existing == null && !next.contributes) return doc;
    final nextEffects = layer.effects
        .copyWith(effects: List<EditorEffect>.unmodifiable(merged));
    if (nextEffects == layer.effects) return doc;
    return doc.replaceLayer(layer.copyAll(effects: nextEffects));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    final existing = layer.effects.effects
        .whereType<VignetteEffect>()
        .cast<VignetteEffect?>()
        .firstWhere((_) => true, orElse: () => null);
    // Restore every knob's prior value (including default values
    // when no vignette existed) so undo is a single atomic restore
    // even if the forward command only touched one field.
    final prior = existing ??
        const VignetteEffect(
          intensity: VignetteEffect.defaultIntensity,
          feather: VignetteEffect.defaultFeather,
        );
    return SetImageVignetteCommand(
      layerId: layerId,
      intensity: prior.intensity,
      feather: prior.feather,
      color: prior.color,
    );
  }

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetImageVignetteCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    // Field-set must match across the stream so a feather drag
    // never silently swallows an in-flight intensity drag.
    if ((intensity == null) != (previous.intensity == null)) return null;
    if ((feather == null) != (previous.feather == null)) return null;
    if ((color == null) != (previous.color == null)) return null;
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
    return doc.replaceLayer(layer.copyAll(cropRect: next));
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
    return doc.replaceLayer(layer.copyAll(fit: fit));
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
    return doc.replaceLayer(layer.copyAll(filterPreset: filterPreset));
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

/// Move an effect on an [ImageLayer]'s effect stack from
/// [oldIndex] to [newIndex]. Out-of-range indices and "no-op"
/// moves (`oldIndex == newIndex`) return the document unchanged so
/// the command stream stays clean and undo never grows phantom
/// entries.
///
/// Order matters: colour-matrix effects compose in stack order and
/// custom-paint effects render in stack order, so reordering is a
/// real semantic change — not a cosmetic UI re-sort.
class ReorderEffectCommand extends EditorCommand {
  const ReorderEffectCommand({
    required this.layerId,
    required this.oldIndex,
    required this.newIndex,
  });

  final String layerId;
  final int oldIndex;
  final int newIndex;

  @override
  String get label => 'Reorder effect';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    final effects = layer.effects.effects;
    if (oldIndex < 0 || oldIndex >= effects.length) return doc;
    if (newIndex < 0 || newIndex >= effects.length) return doc;
    if (oldIndex == newIndex) return doc;
    final next = List<EditorEffect>.of(effects);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    return doc.replaceLayer(layer.copyAll(
      effects: layer.effects
          .copyWith(effects: List<EditorEffect>.unmodifiable(next)),
    ));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    final len = layer.effects.length;
    if (oldIndex < 0 || oldIndex >= len) return _noop;
    if (newIndex < 0 || newIndex >= len) return _noop;
    return ReorderEffectCommand(
      layerId: layerId,
      oldIndex: newIndex,
      newIndex: oldIndex,
    );
  }
}

/// Flip the [EditorEffect.enabled] flag on the effect at [index].
/// Out-of-range index → no-op (returns the document unchanged).
class ToggleEffectEnabledCommand extends EditorCommand {
  const ToggleEffectEnabledCommand({
    required this.layerId,
    required this.index,
  });

  final String layerId;
  final int index;

  @override
  String get label => 'Toggle effect';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    final effects = layer.effects.effects;
    if (index < 0 || index >= effects.length) return doc;
    final eff = effects[index];
    final flipped = eff.withEnabled(!eff.enabled);
    final next = List<EditorEffect>.of(effects);
    next[index] = flipped;
    return doc.replaceLayer(layer.copyAll(
      effects: layer.effects
          .copyWith(effects: List<EditorEffect>.unmodifiable(next)),
    ));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    if (index < 0 || index >= layer.effects.length) return _noop;
    // Toggling twice is the identity, so the inverse is the same
    // command — no need for a dedicated restore variant.
    return ToggleEffectEnabledCommand(layerId: layerId, index: index);
  }
}

/// Remove the effect at [index] from an [ImageLayer]'s effect
/// stack. Inverse re-inserts the captured effect at the same index
/// so undo restores both the value AND its position.
class DeleteEffectCommand extends EditorCommand {
  const DeleteEffectCommand({
    required this.layerId,
    required this.index,
  });

  final String layerId;
  final int index;

  @override
  String get label => 'Delete effect';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    final effects = layer.effects.effects;
    if (index < 0 || index >= effects.length) return doc;
    final next = List<EditorEffect>.of(effects)..removeAt(index);
    // copyWith keeps the stack mask when the last effect is deleted —
    // the mask is user state independent of the list's emptiness.
    return doc.replaceLayer(layer.copyAll(
      effects: layer.effects
          .copyWith(effects: List<EditorEffect>.unmodifiable(next)),
    ));
  }

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    if (index < 0 || index >= layer.effects.length) return _noop;
    return _InsertEffectCommand(
      layerId: layerId,
      index: index,
      effect: layer.effects.effects[index],
    );
  }
}

/// Set, replace, or clear ([mask] = null) the stack-level mask that
/// clips the composed output of an [ImageLayer]'s effect stack —
/// docs/effects.md §5's `composite(I_prev over I0 through stackMask)`,
/// rendered by `StackMaskComposite` since A3 Step 1.
///
/// Mergeable family keyed on `(layerId, "stackMask")` per §8: [live]
/// drags of a mask-shape editor collapse into one undo entry, same
/// convention as [SetImageAdjustmentsCommand]. Discrete preset taps
/// leave [live] false so each is its own undo step.
///
/// The writer stamps schema v3 for any document carrying a stack mask
/// (`DocumentCodec._writerVersion`), so documents produced through
/// this command are refused loudly by pre-v3 readers instead of
/// silently dropping the mask on resave.
class SetStackMaskCommand extends EditorCommand {
  const SetStackMaskCommand({
    required this.layerId,
    required this.mask,
    this.live = false,
  });

  final String layerId;
  final LayerMask? mask;
  final bool live;

  @override
  String get label => mask == null ? 'Clear stack mask' : 'Stack mask';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    final effects = layer.effects;
    if (effects.stackMask == mask) return doc;
    return doc.replaceLayer(
      layer.copyAll(effects: effects.withStackMask(mask)),
    );
  }

  // The mask payload dominates (a PathMask can carry many segments);
  // scalars ride on the per-entry overhead.
  @override
  int get estimatedByteSize => mask?.estimatedByteSize ?? 0;

  @override
  EditorCommand invert(EditorDocument before) {
    final layer = before.layerById(layerId);
    if (layer is! ImageLayer) return _noop;
    return SetStackMaskCommand(
      layerId: layerId,
      mask: layer.effects.stackMask,
    );
  }

  @override
  EditorCommand? mergeWith(EditorCommand previous) {
    if (!live) return null;
    if (previous is! SetStackMaskCommand) return null;
    if (!previous.live) return null;
    if (previous.layerId != layerId) return null;
    return this;
  }
}

/// Internal inverse of [DeleteEffectCommand]: re-inserts a captured
/// effect at the original index. Not exposed publicly because
/// callers should add new effects through their own typed commands
/// (Set...Command), not through a generic insert — this exists only
/// to make undo round-trip cleanly.
class _InsertEffectCommand extends EditorCommand {
  const _InsertEffectCommand({
    required this.layerId,
    required this.index,
    required this.effect,
  });

  final String layerId;
  final int index;
  final EditorEffect effect;

  @override
  String get label => 'Restore effect';

  @override
  EditorDocument apply(EditorDocument doc) {
    final layer = doc.layerById(layerId);
    if (layer is! ImageLayer) return doc;
    final effects = layer.effects.effects;
    final clamped = index.clamp(0, effects.length);
    final next = List<EditorEffect>.of(effects)..insert(clamped, effect);
    return doc.replaceLayer(layer.copyAll(
      effects: layer.effects
          .copyWith(effects: List<EditorEffect>.unmodifiable(next)),
    ));
  }

  @override
  EditorCommand invert(EditorDocument before) =>
      DeleteEffectCommand(layerId: layerId, index: index);
}

