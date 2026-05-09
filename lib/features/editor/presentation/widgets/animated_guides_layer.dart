import 'package:flutter/material.dart';

import '../../engine/interaction/snap_engine.dart';
import 'snap_guides_overlay.dart';
import 'spacing_guides_overlay.dart';

/// Holds both guide overlays and applies a short opacity fade on
/// appearance / disappearance so guides don't flash in or out as the
/// engine engages and releases snaps.
///
/// Why a stateful wrapper rather than a stock [AnimatedOpacity]?
///   * As guides come and go, their list contents change every frame.
///     We want the *transition* to fade only on empty↔non-empty
///     boundaries, never between two non-empty frames (which would
///     cause flicker).
///   * When guides go empty we keep painting the **last non-empty**
///     set during the fade-out so the lines visibly recede instead
///     of disappearing instantly.
class AnimatedGuidesLayer extends StatefulWidget {
  const AnimatedGuidesLayer({
    super.key,
    required this.snapGuides,
    required this.spacingGuides,
    required this.viewportScale,
    this.duration = const Duration(milliseconds: 90),
  });

  final List<SnapGuide> snapGuides;
  final List<SpacingGuide> spacingGuides;
  final double viewportScale;
  final Duration duration;

  @override
  State<AnimatedGuidesLayer> createState() => _AnimatedGuidesLayerState();
}

class _AnimatedGuidesLayerState extends State<AnimatedGuidesLayer> {
  /// Last non-empty snapshot — painted during fade-out so the guides
  /// recede smoothly instead of vanishing instantly.
  List<SnapGuide> _lastSnap = const [];
  List<SpacingGuide> _lastSpacing = const [];

  @override
  void didUpdateWidget(AnimatedGuidesLayer old) {
    super.didUpdateWidget(old);
    if (widget.snapGuides.isNotEmpty) _lastSnap = widget.snapGuides;
    if (widget.spacingGuides.isNotEmpty) _lastSpacing = widget.spacingGuides;
  }

  @override
  Widget build(BuildContext context) {
    final hasAny =
        widget.snapGuides.isNotEmpty || widget.spacingGuides.isNotEmpty;
    final snap = widget.snapGuides.isNotEmpty ? widget.snapGuides : _lastSnap;
    final spacing = widget.spacingGuides.isNotEmpty
        ? widget.spacingGuides
        : _lastSpacing;
    return AnimatedOpacity(
      opacity: hasAny ? 1.0 : 0.0,
      duration: widget.duration,
      curve: Curves.easeOut,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (snap.isNotEmpty)
            SnapGuidesOverlay(
              guides: snap,
              viewportScale: widget.viewportScale,
            ),
          if (spacing.isNotEmpty)
            SpacingGuidesOverlay(
              guides: spacing,
              viewportScale: widget.viewportScale,
            ),
        ],
      ),
    );
  }
}
