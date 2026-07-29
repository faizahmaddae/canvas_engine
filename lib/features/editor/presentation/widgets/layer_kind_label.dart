import 'package:flutter/widgets.dart';

import '../../../../l10n/l10n.dart';
import '../../engine/core/editor_layer.dart';
import '../../engine/modules/text/text_layer.dart';

/// Localized, human-facing names for layers.
///
/// [EditorLayer.type] is an engine identifier (`image`, `text`, …) that
/// belongs in the wire format, not on screen. The Layers drawer used to
/// print it verbatim — and to build unnamed layers' fallback names from
/// it — which surfaced `image` and `Image #1` in Latin script inside an
/// otherwise fully Persian RTL panel. Both now resolve through the ARB.
///
/// Kept as free functions on a shared file because the drawer, the
/// overflow sheet and the accessibility label all have to agree: an
/// unnamed layer's "#3" must read the same wherever it is spoken or
/// shown.
String layerKindLabel(BuildContext context, EditorLayer layer) {
  final l10n = context.l10n;
  return switch (layer.type) {
    'image' => l10n.layerKindImage,
    'text' =>
      (layer is TextLayer && layer.isSticker)
          ? l10n.layerKindSticker
          : l10n.layerKindText,
    'shape' => l10n.layerKindShape,
    'paint' => l10n.layerKindPaint,
    _ => l10n.layerKindGeneric,
  };
}

/// Display name for a layer row: the user's own name when they set one,
/// a text layer's own content when they didn't, else `<kind> <n>` with
/// the index localized (Persian digits under `fa`).
///
/// [modelIndex] is the layer's index in the document, so the number the
/// user reads matches the number the semantics label speaks.
String layerDisplayName(
  BuildContext context,
  EditorLayer layer,
  int modelIndex,
) {
  final name = layer.name;
  if (name != null && name.isNotEmpty) return name;
  if (layer is TextLayer && !layer.isSticker) {
    final t = layer.content.trim();
    if (t.isNotEmpty) return t.length > 28 ? '${t.substring(0, 28)}…' : t;
  }
  return context.l10n.layerAutoName(
    layerKindLabel(context, layer),
    modelIndex + 1,
  );
}
