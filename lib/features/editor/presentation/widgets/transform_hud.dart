import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/core/layer_transform.dart';
import '../../engine/core/selection_state.dart';
import '../../engine/core/viewport_state.dart';
import '../../../../core/utils/editor_value_format.dart';

/// Heads-up display shown above the active layer during a resize or
/// rotation gesture. Rendered in **screen space** (above the viewport
/// transform) so the chip stays a constant size regardless of document
/// size or zoom.
class TransformHud extends StatelessWidget {
  const TransformHud({
    super.key,
    required this.transform,
    required this.viewport,
    required this.activeHandle,
  });

  final LayerTransform transform;
  final ViewportState viewport;

  /// Handle currently being driven. Drives the choice between size label
  /// (for corner resize) and angle label (for rotate).
  final InteractionHandle? activeHandle;

  @override
  Widget build(BuildContext context) {
    final handle = activeHandle;
    if (handle == null) return const SizedBox.shrink();

    final String? label = _labelFor(
      handle,
      transform,
      EditorValueFormat.of(context),
    );
    if (label == null) return const SizedBox.shrink();

    // Anchor in screen space, above the layer's top-mid corner.
    final pos = transform.position;
    final size = transform.size;
    final centerCanvas = transform.center;
    final rot = transform.rotation;
    final c = math.cos(rot);
    final s = math.sin(rot);
    final dx = (pos.dx + size.width / 2) - centerCanvas.dx;
    final dy = pos.dy - centerCanvas.dy;
    final topMidCanvas = Offset(
      centerCanvas.dx + dx * c - dy * s,
      centerCanvas.dy + dx * s + dy * c,
    );
    final topMidScreen = topMidCanvas * viewport.scale + viewport.translation;

    const chipWidth = 120.0;
    const chipHeight = 24.0;
    // Sits clear of the top edge + corner-handle touch box so the
    // chip never overlaps the selection chrome.
    const chipOffsetY = 64.0;

    return Positioned(
      left: topMidScreen.dx - chipWidth / 2,
      top: topMidScreen.dy - chipOffsetY,
      width: chipWidth,
      height: chipHeight,
      child: IgnorePointer(
        child: Center(child: _HudChip(label: label)),
      ),
    );
  }

  String? _labelFor(
    InteractionHandle handle,
    LayerTransform t,
    EditorValueFormat f,
  ) {
    switch (handle) {
      case InteractionHandle.rotate:
        final deg = t.rotation * 180 / math.pi;
        var norm = deg % 360;
        if (norm > 180) norm -= 360;
        if (norm <= -180) norm += 360;
        return f.degrees(norm.round());
      case InteractionHandle.topLeft:
      case InteractionHandle.topRight:
      case InteractionHandle.bottomLeft:
      case InteractionHandle.bottomRight:
      case InteractionHandle.gesture:
        final w = t.size.width.round();
        final h = t.size.height.round();
        return f.dimensions(w, h);
      case InteractionHandle.body:
        return null;
    }
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontFeatures: [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
