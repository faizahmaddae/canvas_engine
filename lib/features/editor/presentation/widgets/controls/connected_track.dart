// Shared control kit: the connected segment track — one bordered
// container whose full-height segments are split by hairlines. The
// Text Studio bench established the grammar (aspect row, type-spec
// cluster); this is the reusable form for panel rows, so option
// groups read as ONE instrument instead of loose chips, and every
// segment's tap target is the track's whole height (44dp floor by
// construction — the thin-chip bug cannot recur here).

import 'package:flutter/material.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/utils/haptics.dart';

/// One segment of a [ConnectedTrack].
class TrackSegmentSpec {
  const TrackSegmentSpec({
    this.key,
    required this.semanticLabel,
    required this.active,
    required this.onTap,
    required this.child,
    this.flex = 1,
  });

  final Key? key;
  final String semanticLabel;
  final bool active;
  final VoidCallback onTap;

  /// The segment's visual content (icon / label / state dots). Its
  /// semantics are excluded — [semanticLabel] is the announcement.
  final Widget child;
  final int flex;
}

/// A row of mutually-related options rendered as one bordered track.
/// The parent sizes the height (44dp minimum per the repo touch
/// floor); segments stretch to fill it.
class ConnectedTrack extends StatelessWidget {
  const ConnectedTrack({super.key, required this.segments});

  final List<TrackSegmentSpec> segments;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: tokens.border.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        // Stretch, never center: the tap target is the track's full
        // height, not the content's intrinsic height.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: tokens.border.withValues(alpha: 0.55),
              ),
            Expanded(
              flex: segments[i].flex,
              child: _Segment(spec: segments[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.spec});

  final TrackSegmentSpec spec;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: spec.semanticLabel,
      selected: spec.active,
      child: Material(
        color: spec.active
            ? tokens.accent.withValues(alpha: 0.16)
            : Colors.transparent,
        child: InkWell(
          key: spec.key,
          onTap: () {
            EditorHaptics.tap();
            spec.onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: ExcludeSemantics(child: spec.child)),
          ),
        ),
      ),
    );
  }
}
