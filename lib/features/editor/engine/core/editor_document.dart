import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'background_fill.dart';
import 'editor_layer.dart';

export 'background_fill.dart';

/// Default canvas background fill. White matches every existing
/// document on disk — the codec omits the field on serialise when
/// the value matches this constant so old snapshots stay byte-for-
/// byte stable.
const Color kDefaultCanvasBackground = Color(0xFFFFFFFF);

/// Default [BackgroundFill] — a solid white fill, equivalent to the
/// historical `backgroundColor: kDefaultCanvasBackground` default.
const BackgroundFill kDefaultCanvasBackgroundFill = SolidBackground(
  color: kDefaultCanvasBackground,
);

/// What the user is editing.
///
/// * [design] -- a blank or templated canvas with freely-arranged
///   layers (text, shapes, stickers, multiple images). The classic
///   Canva / Figma model. This is the default; every existing on-
///   disk document loads as [design] because the field is omitted
///   on serialise when it matches.
/// * [photo] -- the project IS an imported photograph. The base
///   photo defines the canvas size + aspect, sits at the bottom of
///   the z-order locked by default, and protects itself from one-
///   tap deletion. Stickers / text / overlays still sit on top as
///   normal layers. This is the Snapseed / Lightroom / Instagram /
///   Canva-photo-mode model.
///
/// Photo-mode behaviour is enforced cooperatively across:
///   * [DocumentController.newDocument] (entry-point selects kind)
///   * `_addImage` / Home import (creates the base photo locked)
///   * `LayerActions.delete` (asks for confirm + flips kind on yes)
///   * The image-target resolver (already prefers basePhotoLayerId)
enum ProjectKind { design, photo }

const ProjectKind kDefaultProjectKind = ProjectKind.design;

/// What the canvas backdrop is.
///
/// * [color] -- a solid fill picked by the user (defaults to white).
///   This is the historical behaviour and remains the default for
///   every existing on-disk document because the codec omits the
///   field on serialise when it matches.
/// * [transparent] -- no fill. The canvas background is alpha = 0,
///   so anywhere a layer does not cover, the exported PNG is
///   transparent and the editor renders a checkerboard preview so
///   the user can see what "empty" means.
///
/// Mode is independent from [EditorDocument.backgroundColor]: the
/// colour value is preserved so toggling back and forth in the
/// Canvas tool restores the user's previous palette pick. JPEG
/// export always composites over an opaque colour because the
/// format has no alpha channel -- see `DocumentJpgExporter`.
enum CanvasBackgroundMode { color, transparent }

const CanvasBackgroundMode kDefaultCanvasBackgroundMode =
    CanvasBackgroundMode.color;

/// The canvas document: ordered list of layers + a size. Z-order is
/// defined by list order: last element renders on top.
@immutable
class EditorDocument {
  EditorDocument({
    required List<EditorLayer> layers,
    this.width = 1080,
    this.height = 1080,
    BackgroundFill? background,
    @Deprecated('Use background: SolidBackground(color: ...) instead')
    Color? backgroundColor,
    this.backgroundMode = kDefaultCanvasBackgroundMode,
    this.basePhotoLayerId,
    this.projectKind = kDefaultProjectKind,
  }) : background =
           background ??
           (backgroundColor != null
               ? SolidBackground(color: backgroundColor)
               : kDefaultCanvasBackgroundFill),
       // Skip the wrap if the caller already handed us an
       // unmodifiable view (the common path: copyWith re-passes
       // `this.layers`, which is already wrapped). This preserves
       // reference identity so `next.layers == doc.layers` stays
       // an `identical` match for unchanged copies — a real
       // performance contract relied on by hot equality checks.
       //
       // Wrap with `UnmodifiableListView` rather than
       // `List.unmodifiable` so the wrap is O(1) and the wrapper
       // type is publicly named — production callers always hand
       // us a freshly built list (`[...layers, x]`) that no other
       // code retains a reference to, so the view's read-through
       // semantics are not a leak.
       layers = layers is UnmodifiableListView<EditorLayer>
           ? layers
           : UnmodifiableListView<EditorLayer>(layers),
       _layerIndex = {for (var i = 0; i < layers.length; i++) layers[i].id: i};

  /// Z-ordered list of layers (bottom = 0, top = last). The list is
  /// wrapped with [List.unmodifiable] at construction so callers
  /// cannot mutate the document state behind its back — every change
  /// must flow through [copyWith] / [addLayer] / [removeLayer] /
  /// [replaceLayer] and produce a new [EditorDocument]. See AGENTS.md
  /// "EditorDocument is immutable" for the rationale.
  final List<EditorLayer> layers;
  final double width;
  final double height;

  /// How the canvas backdrop is filled when [backgroundMode] is
  /// [CanvasBackgroundMode.color]. May be a [SolidBackground] (the
  /// historical default) or a gradient variant. Preserved across
  /// transparent-mode toggles so flipping back restores the user's
  /// last fill choice. See [BackgroundFill] for the variant model.
  final BackgroundFill background;

  /// The dominant colour of [background] — returns the solid colour
  /// for [SolidBackground], the gradient start for
  /// [LinearGradientBackground], or the centre colour for
  /// [RadialGradientBackground]. Provided for code that predates the
  /// gradient engine; new code should switch on [background] directly.
  @Deprecated(
    'Use background. For gradients returns the start/center color as '
    'an approximation of the dominant tone.',
  )
  Color get backgroundColor => switch (background) {
    SolidBackground(:final color) => color,
    LinearGradientBackground(:final startColor) => startColor,
    RadialGradientBackground(:final centerColor) => centerColor,
  };

  /// Whether the canvas backdrop is a solid colour or transparent.
  /// See [CanvasBackgroundMode] for the rationale.
  final CanvasBackgroundMode backgroundMode;

  /// Id of the document's *base photo* — the imported gallery image
  /// that defines the project. The image-target resolver falls back
  /// to this layer when the user invokes a photo-action (Crop /
  /// Filters / Adjust) without an image selection, even if the
  /// document also contains stickers, text, or secondary images on
  /// top. `null` for projects that were never seeded from a photo
  /// (blank canvas, all-shape compositions). Set automatically by
  /// the import flow on the first added image and cleared whenever
  /// the referenced layer is removed.
  final String? basePhotoLayerId;

  /// What kind of project this is. See [ProjectKind] for behaviour
  /// implications. Defaults to [ProjectKind.design] for backward
  /// compatibility with every existing on-disk document.
  final ProjectKind projectKind;
  final Map<String, int> _layerIndex;

  static final EditorDocument empty = EditorDocument(layers: const []);

  /// True iff [id] names a layer that is the photo-mode base photo
  /// of this document. Used by UI to gate destructive actions and
  /// surface protective UX (delete-confirm, badge in layers panel).
  bool isProtectedBasePhoto(String id) =>
      projectKind == ProjectKind.photo && id == basePhotoLayerId;

  EditorLayer? layerById(String id) {
    final i = _layerIndex[id];
    if (i == null) return null;
    return layers[i];
  }

  int? indexOf(String id) => _layerIndex[id];

  EditorDocument copyWith({
    List<EditorLayer>? layers,
    double? width,
    double? height,
    BackgroundFill? background,
    @Deprecated('Use background: SolidBackground(color: ...) instead')
    Color? backgroundColor,
    CanvasBackgroundMode? backgroundMode,
    Object? basePhotoLayerId = _sentinel,
    ProjectKind? projectKind,
  }) {
    final BackgroundFill nextBackground =
        background ??
        (backgroundColor != null
            ? SolidBackground(color: backgroundColor)
            : this.background);
    return EditorDocument(
      layers: layers ?? this.layers,
      width: width ?? this.width,
      height: height ?? this.height,
      background: nextBackground,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      basePhotoLayerId: identical(basePhotoLayerId, _sentinel)
          ? this.basePhotoLayerId
          : basePhotoLayerId as String?,
      projectKind: projectKind ?? this.projectKind,
    );
  }

  EditorDocument addLayer(EditorLayer layer) =>
      copyWith(layers: [...layers, layer]);

  /// Insert [layer] at [index] in z-order (bottom = 0, top = length).
  /// The index is clamped to the valid range rather than thrown on:
  /// the main caller is [RemoveLayerCommand]'s inverse, whose captured
  /// index may exceed the list length by the time undo runs if other
  /// layers were removed in between — restoring the layer at the top
  /// beats crashing the undo.
  EditorDocument insertLayer(EditorLayer layer, int index) {
    final i = index.clamp(0, layers.length);
    return copyWith(layers: [...layers]..insert(i, layer));
  }

  EditorDocument removeLayer(String id) {
    final nextLayers = layers.where((l) => l.id != id).toList(growable: false);
    // Clear the base-photo pointer if its target was just removed —
    // otherwise the resolver would dereference a ghost id and the
    // JSON would persist a dangling reference.
    final nextBase = (basePhotoLayerId == id) ? null : basePhotoLayerId;
    return copyWith(layers: nextLayers, basePhotoLayerId: nextBase);
  }

  EditorDocument replaceLayer(EditorLayer updated) {
    final i = _layerIndex[updated.id];
    if (i == null) return this;
    final next = [...layers];
    next[i] = updated;
    return copyWith(layers: next);
  }

  /// Reorder [layers] by moving the item at [from] to [to]. Both indices
  /// are into [layers] (bottom = 0, top = length-1). No-op if either
  /// index is out of range or equal.
  ///
  /// Base-photo invariant: in a [ProjectKind.photo] project the base
  /// photo IS the project and stays pinned to the bottom of the z-order
  /// (index 0, painted first by `DocumentView`). Any reorder that would
  /// lift the base photo off the bottom, or slide another layer beneath
  /// it, is refused — otherwise Send-backward or a layers-panel drag
  /// would silently bury user content under the opaque photo. This is
  /// the single choke-point every reorder surface (toolbar + panel drag)
  /// funnels through, so guarding here protects all of them at once and
  /// mirrors the delete-protection [isProtectedBasePhoto] already
  /// enforces. Design projects (no base photo) are unaffected.
  EditorDocument reorderLayer(int from, int to) {
    if (from == to) return this;
    if (from < 0 || from >= layers.length) return this;
    if (to < 0 || to >= layers.length) return this;
    final baseId = basePhotoLayerId;
    if (projectKind == ProjectKind.photo && baseId != null) {
      final baseIndex = _layerIndex[baseId];
      if (baseIndex != null && (from == baseIndex || to <= baseIndex)) {
        return this;
      }
    }
    final next = [...layers];
    final moved = next.removeAt(from);
    next.insert(to, moved);
    return copyWith(layers: next);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorDocument &&
          other.width == width &&
          other.height == height &&
          other.background == background &&
          other.backgroundMode == backgroundMode &&
          other.basePhotoLayerId == basePhotoLayerId &&
          other.projectKind == projectKind &&
          listEquals(other.layers, layers);

  @override
  int get hashCode => Object.hash(
    width,
    height,
    background,
    backgroundMode,
    basePhotoLayerId,
    projectKind,
    Object.hashAll(layers),
  );
}

const Object _sentinel = Object();
