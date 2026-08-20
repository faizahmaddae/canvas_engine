import 'package:flutter/widgets.dart';

import '../effects/editor_effect.dart';
import 'layer_capabilities.dart';
import 'layer_mask.dart';
import 'layer_transform.dart';

/// Base class for any visual layer that can live on the canvas.
///
/// Concrete layer types (text, image, shape, drawing...) extend this and
/// are responsible ONLY for holding their own type-specific data and
/// rendering themselves.
///
/// The interaction/transform system never reads subclass data – it only
/// reads [transform] and [capabilities].
@immutable
abstract class EditorLayer {
  const EditorLayer({
    required this.id,
    required this.transform,
    required this.capabilities,
    this.name,
    this.visible = true,
    this.locked = false,
    this.opacity = 1.0,
    this.effects = EffectStack.empty,
  });

  final String id;
  final LayerTransform transform;
  final LayerCapabilities capabilities;
  final String? name;

  /// Runtime visibility flag. Hidden layers are skipped by rendering and
  /// hit-testing but remain in the document so the user can unhide them.
  final bool visible;

  /// Runtime lock flag. THE lock rule (ux-audit P3-1 — one statement,
  /// stated once, every surface renders and refuses from it):
  ///
  /// **Locked freezes the layer's own content: transform (move /
  /// resize / rotate / flip), style, opacity and align are refused;
  /// structural operations (select via the layers drawer, reorder,
  /// duplicate, delete, lock/unlock, show/hide) remain available.**
  ///
  /// The content half is not enforced here — commands stay pure and
  /// policy-free — but in the gates in front of the command stack:
  /// pointer eligibility in `InteractionController`, align in
  /// `AlignmentController.canMoveLayer`, flip in `LayerActions.canFlip`,
  /// opacity in `LayerOpacityControl.canEdit`. Structural operations
  /// stay lock-agnostic because they act on the layer's PLACE in the
  /// document, not on its content — which is also why a locked layer
  /// can still be selected (from the drawer; canvas hit-testing skips
  /// it) and unlocked again.
  ///
  /// One deliberate carve-out: the protected base photo imports
  /// `locked` purely as structural pinning against canvas gestures
  /// (`EditorDocument.isProtectedBasePhoto`); its opacity and look
  /// stay editable from the Image strip (tb15, c2860db).
  final bool locked;

  /// Layer-level opacity, `0..1`. `1.0` is fully opaque (default) and
  /// renders identically to documents written before this field
  /// existed. Applied as an `Opacity` wrapper inside the renderer so
  /// every layer type honours it without per-type code, and so PNG
  /// export inherits it automatically (the exporter uses the same
  /// widget tree as the canvas).
  ///
  /// Type-specific opacity (e.g. [ShapeLayer.fillOpacity],
  /// [ImageLayer.shadowOpacity]) keeps its current meaning — those
  /// affect a single sub-element of the layer, while [opacity] scales
  /// the whole composite.
  final double opacity;

  /// Non-destructive effect stack applied to this layer at render
  /// time. Empty by default — every legacy document re-encodes
  /// without an `effects` key, so the v2 fixture corpus stays
  /// byte-identical after the schema bump.
  ///
  /// Effects are stored bottom-to-top: `effects[0]` applies first,
  /// `effects[last]` applies last. See `effects/editor_effect.dart`
  /// for the contract.
  final EffectStack effects;

  /// Discriminator used for serialization and debugging.
  String get type;

  /// Returns a copy of this layer with a new [transform]. Subclasses must
  /// override to preserve their own fields.
  EditorLayer withTransform(LayerTransform transform);

  /// Returns a copy with a new [visible] flag.
  EditorLayer withVisibility(bool visible);

  /// Returns a copy with a new [locked] flag.
  EditorLayer withLocked(bool locked);

  /// Returns a copy with a new [opacity], clamped to `0..1`.
  EditorLayer withOpacity(double opacity);

  /// Returns a copy with a new display [name]. Pass `null` to clear
  /// the custom name and fall back to the layer type/content default.
  EditorLayer withName(String? name);

  /// Render the layer inside its own local coordinate system (origin at
  /// top-left, extent equal to `transform.size`). The canvas has already
  /// been translated + rotated.
  Widget buildContent(BuildContext context);

  /// Approximate retained-memory cost of this layer, in bytes. Used by
  /// [HistoryStack] when a command holds a full layer copy
  /// (Add/Remove and their inverses) — that's where the cap actually
  /// matters, since paint strokes can carry tens of thousands of
  /// points and each undo entry would otherwise pin the whole array.
  ///
  /// Default `kLayerBaseBytes` covers the common scalar fields
  /// (transform + capabilities + flags). Subclasses override when
  /// they carry user-content of variable size: paint stroke points,
  /// long text, or image pixel buffers (when those ever live on the
  /// layer; today image pixels live in the OS image cache and the
  /// layer only holds the asset/file/url string).
  ///
  /// Estimates, not exact byte counts. The point is to distinguish
  /// "50 KB" from "50 MB", not to predict the GC trace.
  int get estimatedByteSize => kLayerBaseBytes;

  /// Baseline used by [estimatedByteSize] for the common scalar
  /// fields. Cheap to keep this conservative — the budget is a soft
  /// cap, an overestimate just means slightly shallower history under
  /// pressure (which is the safe direction).
  static const int kLayerBaseBytes = 256;

  /// Serialize this layer to a JSON-friendly map. Implementations must
  /// include a `type` field matching [type] so a registry can dispatch
  /// the right `fromJson` factory on decode. The base shape returned by
  /// [baseJson] covers the common fields — subclasses spread it then add
  /// their own keys.
  Map<String, dynamic> toJson();

  /// Common base serialization shared by every layer subclass: type
  /// discriminator + identity + transform + visibility flags. Subclasses
  /// spread this then add their type-specific fields.
  @protected
  Map<String, dynamic> baseJson() => <String, dynamic>{
    'type': type,
    'id': id,
    'transform': transform.toJson(),
    if (name != null) 'name': name,
    if (!visible) 'visible': false,
    if (locked) 'locked': true,
    // Only persist when non-default so legacy round-trips stay
    // byte-identical and existing thumbnails / hashes are stable.
    if (opacity < 1.0) 'opacity': opacity,
    // Same omit-when-default rule for effects: an empty stack
    // costs zero bytes on disk. This is the gate that keeps the
    // v2 corpus byte-identical under schema v3. The gate reads the
    // raw effects LIST — never a composite emptiness that folds in
    // stackMask — so a stackMask-only stack still omits `effects`.
    if (effects.effects.isNotEmpty) 'effects': effects.toJson(),
    // Additive within schema v3: the stack mask serializes under its
    // own key, gated independently of the effects list, so documents
    // without one keep their exact bytes.
    if (effects.stackMask != null) 'stackMask': effects.stackMask!.toJson(),
  };

  /// Helper for subclass `fromJson` factories: returns the decoded
  /// [EffectStack] combining the `effects` and `stackMask` keys, or
  /// [EffectStack.empty] when both are absent. Centralised so every
  /// layer reads the same keys with the same null/empty handling.
  static EffectStack parseEffects(Map<String, dynamic> json) {
    final stack = EffectStack.fromJson(json['effects']);
    final rawMask = json['stackMask'];
    if (rawMask == null) return stack;
    return EffectStack(stack.effects, stackMask: LayerMask.fromJson(rawMask));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorLayer &&
          other.id == id &&
          other.transform == transform &&
          other.capabilities == capabilities &&
          other.visible == visible &&
          other.locked == locked &&
          other.opacity == opacity &&
          other.name == name &&
          other.effects == effects;

  @override
  int get hashCode => Object.hash(
    id,
    transform,
    capabilities,
    visible,
    locked,
    opacity,
    name,
    effects,
  );
}
