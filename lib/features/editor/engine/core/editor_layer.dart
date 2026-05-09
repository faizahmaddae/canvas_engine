import 'package:flutter/widgets.dart';

import 'layer_capabilities.dart';
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
  });

  final String id;
  final LayerTransform transform;
  final LayerCapabilities capabilities;
  final String? name;

  /// Runtime visibility flag. Hidden layers are skipped by rendering and
  /// hit-testing but remain in the document so the user can unhide them.
  final bool visible;

  /// Runtime lock flag. Locked layers cannot be moved, resized, rotated,
  /// or hit-tested by pointer gestures. They can still be selected from
  /// the layers panel and unlocked from there.
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

  /// Render the layer inside its own local coordinate system (origin at
  /// top-left, extent equal to `transform.size`). The canvas has already
  /// been translated + rotated.
  Widget buildContent(BuildContext context);

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
      };

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
          other.name == name;

  @override
  int get hashCode =>
      Object.hash(id, transform, capabilities, visible, locked, opacity, name);
}
