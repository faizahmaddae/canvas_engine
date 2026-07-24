import 'dart:math' as math;
import 'dart:ui';

import '../core/layer_transform.dart';

/// Axis a snap guide line is drawn along. A [SnapAxis.vertical] guide is
/// a vertical line at some X coordinate (runs top-to-bottom), and vice
/// versa. This matches how designers read "vertical center guide".
enum SnapAxis { vertical, horizontal }

/// A single snap target / visible alignment line. [coord] is the canvas-
/// space coordinate on the [axis] perpendicular: for a vertical guide
/// (SnapAxis.vertical), [coord] is the X coordinate. The optional
/// [start]/[end] are the other axis' extents used to draw a short guide
/// only as long as both aligned objects + the canvas demand — rather than
/// always edge-to-edge.
class SnapGuide {
  const SnapGuide({
    required this.axis,
    required this.coord,
    required this.start,
    required this.end,
  });

  final SnapAxis axis;
  final double coord;
  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapGuide &&
          other.axis == axis &&
          other.coord == coord &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(axis, coord, start, end);
}

/// Result of a snap query: an (optionally) adjusted position plus a set of
/// guides that were activated. Empty guides means nothing was within range
/// and the original position was returned unchanged.
class SnapResult {
  const SnapResult({required this.position, required this.guides});

  final Offset position;
  final List<SnapGuide> guides;

  static const none = SnapResult(position: Offset.zero, guides: <SnapGuide>[]);
}

/// Visual marker for an "equal-spacing" snap: the moved rect has just
/// landed between two peers with equal gap on either side. A guide
/// describes the two equal gap segments so the painter can draw the
/// classic Figma `=` brackets between the rects, optionally with a
/// pixel-distance label.
///
/// The two gap segments share the same [gap] value; the painter renders
/// each segment as a short line at [crossCoord] on the perpendicular
/// axis, with bracket end-caps anchored to the rect edges.
///
/// * For [SnapAxis.vertical] (a horizontal row of rects sharing Y):
///   the gaps run along X; [crossCoord] is the shared Y midline; the
///   four `*Start`/`*End` values are X coordinates.
/// * For [SnapAxis.horizontal] (a vertical column of rects sharing X):
///   the gaps run along Y; [crossCoord] is the shared X midline; the
///   four `*Start`/`*End` values are Y coordinates.
class SpacingGuide {
  const SpacingGuide({
    required this.axis,
    required this.gap,
    required this.crossCoord,
    required this.fromStart,
    required this.fromEnd,
    required this.toStart,
    required this.toEnd,
  });

  /// Axis along which the gaps run. Note: this matches the alignment
  /// guide convention (vertical axis = vertical line / X varies).
  final SnapAxis axis;

  /// Pixel size of each of the two equal gaps (post-snap).
  final double gap;

  /// Perpendicular coordinate to draw the gap line at (the row's Y for
  /// vertical-axis spacing, the column's X for horizontal-axis spacing).
  final double crossCoord;

  /// Leading-segment range along [axis]: from the trailing edge of the
  /// "before" peer to the leading edge of the moved rect.
  final double fromStart;
  final double fromEnd;

  /// Trailing-segment range along [axis]: from the trailing edge of the
  /// moved rect to the leading edge of the "after" peer.
  final double toStart;
  final double toEnd;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpacingGuide &&
          other.axis == axis &&
          other.gap == gap &&
          other.crossCoord == crossCoord &&
          other.fromStart == fromStart &&
          other.fromEnd == fromEnd &&
          other.toStart == toStart &&
          other.toEnd == toEnd;

  @override
  int get hashCode =>
      Object.hash(axis, gap, crossCoord, fromStart, fromEnd, toStart, toEnd);
}

/// Result of an equal-spacing snap query: an adjusted position plus the
/// set of [SpacingGuide]s that engaged. When no snap engages the
/// returned position equals the proposed input and [guides] is empty.
class SpacingSnapResult {
  const SpacingSnapResult({required this.position, required this.guides});

  final Offset position;
  final List<SpacingGuide> guides;
}

/// Pure, stateless alignment snapping.
///
/// Given a proposed position for the *moved* layer's unrotated bounding
/// rect, this engine checks three axis-aligned targets per axis
/// (near-edge, far-edge, center) against:
///   * the canvas edges and centers,
///   * each peer layer's axis-aligned bounding box edges and centers.
///
/// The closest target within [threshold] pixels wins on each axis
/// independently, so horizontal + vertical snap work together without
/// interfering. Only the target's *own-axis* extents (projected onto the
/// other axis) contribute to the guide's start/end so the painted line
/// stays tight, Figma-style.
///
/// Kept engine-only: no widgets, no providers. All inputs are plain data.
class SnapEngine {
  const SnapEngine({this.threshold = 6.0});

  /// Maximum pixel distance between an edge/center pair for a snap to
  /// engage. Small enough to feel intentional, large enough to pull in
  /// reliably on a trackpad.
  final double threshold;

  /// Snap a [proposed] top-left position against peer layers and the
  /// canvas. [size] is the moved layer's size. [peerRects] are each peer
  /// layer's axis-aligned bounding rect (peers should exclude the layer
  /// being moved). Rotated peers contribute their [unrotatedRect] — the
  /// goal is good-enough alignment, not geometric perfection on rotated
  /// content, which is rarely what the user is after anyway.
  ///
  /// [threshold] optionally overrides the engine's default for this call
  /// only — used by the controller to scale the snap radius by the
  /// current viewport zoom so the magnetic feel stays constant in screen
  /// pixels.
  ///
  /// Returns the possibly-adjusted top-left plus any guides to draw.
  ///
  /// **Hysteresis.** When [previous] is supplied, the targets matching
  /// last frame's guide coords are evaluated with a wider tolerance
  /// ([threshold] × [releaseFactor]). This keeps a guide engaged while
  /// the pointer is still "near" it, preventing the on/off flicker
  /// that happens when the cursor lingers exactly at the threshold
  /// boundary. New (non-sticky) candidates still need to fall inside
  /// the base [threshold] to engage, and a *closer* non-sticky
  /// candidate inside the base threshold beats a sticky one outside —
  /// so deliberate moves to a new target still feel responsive.
  SnapResult snapPosition({
    required Offset proposed,
    required Size size,
    required List<Rect> peerRects,
    required Size canvasSize,
    double? threshold,
    SnapResult? previous,
    double releaseFactor = 1.6,
  }) {
    final effectiveThreshold = threshold ?? this.threshold;
    final releaseThreshold = effectiveThreshold * releaseFactor;
    double? prevVCoord;
    double? prevHCoord;
    if (previous != null) {
      for (final g in previous.guides) {
        if (g.axis == SnapAxis.vertical) prevVCoord = g.coord;
        if (g.axis == SnapAxis.horizontal) prevHCoord = g.coord;
      }
    }
    final left = proposed.dx;
    final top = proposed.dy;
    final right = left + size.width;
    final bottom = top + size.height;
    final cx = left + size.width / 2;
    final cy = top + size.height / 2;

    final vTargets = <_SnapTarget>[
      // Canvas targets (vertical lines).
      _SnapTarget(coord: 0, peerStart: 0, peerEnd: canvasSize.height),
      _SnapTarget(
        coord: canvasSize.width / 2,
        peerStart: 0,
        peerEnd: canvasSize.height,
      ),
      _SnapTarget(
        coord: canvasSize.width,
        peerStart: 0,
        peerEnd: canvasSize.height,
      ),
      for (final r in peerRects) ...[
        _SnapTarget(coord: r.left, peerStart: r.top, peerEnd: r.bottom),
        _SnapTarget(
          coord: r.left + r.width / 2,
          peerStart: r.top,
          peerEnd: r.bottom,
        ),
        _SnapTarget(coord: r.right, peerStart: r.top, peerEnd: r.bottom),
      ],
    ];

    final hTargets = <_SnapTarget>[
      _SnapTarget(coord: 0, peerStart: 0, peerEnd: canvasSize.width),
      _SnapTarget(
        coord: canvasSize.height / 2,
        peerStart: 0,
        peerEnd: canvasSize.width,
      ),
      _SnapTarget(
        coord: canvasSize.height,
        peerStart: 0,
        peerEnd: canvasSize.width,
      ),
      for (final r in peerRects) ...[
        _SnapTarget(coord: r.top, peerStart: r.left, peerEnd: r.right),
        _SnapTarget(
          coord: r.top + r.height / 2,
          peerStart: r.left,
          peerEnd: r.right,
        ),
        _SnapTarget(coord: r.bottom, peerStart: r.left, peerEnd: r.right),
      ],
    ];

    // Candidate values on the moved rect: left / center-x / right, and
    // top / center-y / bottom. Each carries the *own extent* (top..bottom
    // for vertical candidates) used to bound the guide line span.
    final vCandidates = <_SnapCandidate>[
      _SnapCandidate(value: left, ownStart: top, ownEnd: bottom),
      _SnapCandidate(value: cx, ownStart: top, ownEnd: bottom),
      _SnapCandidate(value: right, ownStart: top, ownEnd: bottom),
    ];
    final hCandidates = <_SnapCandidate>[
      _SnapCandidate(value: top, ownStart: left, ownEnd: right),
      _SnapCandidate(value: cy, ownStart: left, ownEnd: right),
      _SnapCandidate(value: bottom, ownStart: left, ownEnd: right),
    ];

    final vMatch = _bestMatch(
      vCandidates,
      vTargets,
      effectiveThreshold,
      stickyCoord: prevVCoord,
      releaseThreshold: releaseThreshold,
    );
    final hMatch = _bestMatch(
      hCandidates,
      hTargets,
      effectiveThreshold,
      stickyCoord: prevHCoord,
      releaseThreshold: releaseThreshold,
    );

    var dx = 0.0;
    var dy = 0.0;
    final guides = <SnapGuide>[];
    if (vMatch != null) {
      dx = vMatch.target.coord - vMatch.candidate.value;
      final start = math.min(
        vMatch.candidate.ownStart + dy,
        vMatch.target.peerStart,
      );
      final end = math.max(vMatch.candidate.ownEnd + dy, vMatch.target.peerEnd);
      guides.add(
        SnapGuide(
          axis: SnapAxis.vertical,
          coord: vMatch.target.coord,
          start: start,
          end: end,
        ),
      );
    }
    if (hMatch != null) {
      dy = hMatch.target.coord - hMatch.candidate.value;
      final start = math.min(
        hMatch.candidate.ownStart + dx,
        hMatch.target.peerStart,
      );
      final end = math.max(hMatch.candidate.ownEnd + dx, hMatch.target.peerEnd);
      guides.add(
        SnapGuide(
          axis: SnapAxis.horizontal,
          coord: hMatch.target.coord,
          start: start,
          end: end,
        ),
      );
    }

    return SnapResult(
      position: Offset(left + dx, top + dy),
      // Const when empty: interaction state stores this list every
      // move tick, and the canvas' Riverpod selects compare lists by
      // IDENTITY — a fresh empty allocation per tick read as "guides
      // changed" and re-ran the whole canvas build on every drag
      // frame with no snap engaged.
      guides: guides.isEmpty ? const <SnapGuide>[] : guides,
    );
  }

  _SnapMatch? _bestMatch(
    List<_SnapCandidate> candidates,
    List<_SnapTarget> targets,
    double threshold, {
    double? stickyCoord,
    double releaseThreshold = 0,
  }) {
    _SnapMatch? best;
    var bestDist = threshold;
    for (final c in candidates) {
      for (final t in targets) {
        final d = (c.value - t.coord).abs();
        // Sticky targets carry over the previous frame's engaged coord
        // and may exceed the base threshold up to [releaseThreshold].
        // Non-sticky candidates still need to fall inside [threshold]
        // to engage. Closest wins among survivors — but the `best == null`
        // branch lets a sticky candidate outside [threshold] become the
        // first match, so a closer non-sticky inside [threshold] can
        // still overtake it. Hysteresis only *retains* an engagement,
        // never traps the user inside it.
        final isSticky =
            stickyCoord != null && (t.coord - stickyCoord).abs() < 0.001;
        final tol = isSticky ? releaseThreshold : threshold;
        if (d > tol) continue;
        if (best == null || d < bestDist) {
          bestDist = d;
          best = _SnapMatch(candidate: c, target: t);
        }
      }
    }
    return best;
  }

  /// Equal-spacing snap: detect when the moved rect sits between two
  /// peers along an axis, where the two peers also overlap the moved
  /// rect on the perpendicular axis (i.e. they're "in the same row /
  /// column"). When the difference between the two gaps is within
  /// [threshold], snap the moved rect's position so the gaps become
  /// exactly equal — and emit a [SpacingGuide] per axis describing the
  /// two equal segments so the painter can render Figma-style `=`
  /// brackets.
  ///
  /// X axis and Y axis are evaluated independently so a snap on X does
  /// not preclude a snap on Y. Within an axis, the candidate with the
  /// smallest correction wins.
  ///
  /// Compose with [snapPosition] by calling that first and feeding its
  /// result here only on axes whose alignment guides are absent — the
  /// controller does this so a strong edge-alignment is never
  /// overridden by a weaker spacing snap.
  ///
  /// **Hysteresis.** When [previous] is supplied, the gap value held
  /// last frame gets a wider tolerance — same flicker-prevention
  /// scheme as [snapPosition].
  SpacingSnapResult findSpacingSnap({
    required Offset proposed,
    required Size size,
    required List<Rect> peerRects,
    double? threshold,
    SpacingSnapResult? previous,
    double releaseFactor = 1.6,
  }) {
    if (peerRects.length < 2) {
      return SpacingSnapResult(position: proposed, guides: const []);
    }
    final tol = threshold ?? this.threshold;
    final releaseTol = tol * releaseFactor;
    final moved = proposed & size;

    double? prevVGap;
    double? prevHGap;
    if (previous != null) {
      for (final g in previous.guides) {
        if (g.axis == SnapAxis.vertical) prevVGap = g.gap;
        if (g.axis == SnapAxis.horizontal) prevHGap = g.gap;
      }
    }

    // Axis = vertical means vertical guide-axis convention (X varies),
    // i.e. the row of rects is laid out horizontally and the gaps run
    // along X. We name the locals to match that.
    final xSnap = _spacingAxisSnap(
      moved: moved,
      peers: peerRects,
      tolerance: tol,
      horizontal: true,
      stickyGap: prevVGap,
      releaseTolerance: releaseTol,
    );
    final ySnap = _spacingAxisSnap(
      moved: moved,
      peers: peerRects,
      tolerance: tol,
      horizontal: false,
      stickyGap: prevHGap,
      releaseTolerance: releaseTol,
    );

    final guides = <SpacingGuide>[];
    var dx = 0.0;
    var dy = 0.0;
    if (xSnap != null) {
      dx = xSnap.delta;
      guides.add(xSnap.guide);
    } else {
      // No "between two peers" match on X — try pattern detection:
      // if two peers in the row already have a gap G, snap moved
      // before / after the row to extend that rhythm.
      final pat = _patternSpacing(
        moved: moved,
        peers: peerRects,
        tolerance: tol,
        horizontal: true,
        stickyGap: prevVGap,
        releaseTolerance: releaseTol,
      );
      if (pat != null) {
        dx = pat.delta;
        guides.add(pat.guide);
      }
    }
    if (ySnap != null) {
      dy = ySnap.delta;
      guides.add(ySnap.guide);
    } else {
      final pat = _patternSpacing(
        moved: moved,
        peers: peerRects,
        tolerance: tol,
        horizontal: false,
        stickyGap: prevHGap,
        releaseTolerance: releaseTol,
      );
      if (pat != null) {
        dy = pat.delta;
        guides.add(pat.guide);
      }
    }
    return SpacingSnapResult(
      position: proposed.translate(dx, dy),
      // Same identity contract as SnapResult: const when empty so
      // per-tick stores don't defeat the canvas' select granularity.
      guides: guides.isEmpty ? const <SpacingGuide>[] : guides,
    );
  }

  /// Pattern spacing: detect an established gap rhythm among row-mate
  /// peers (those overlapping the moved rect on the perpendicular
  /// axis) and snap the moved rect to extend that rhythm immediately
  /// before the leftmost peer or after the rightmost peer.
  ///
  /// "Established" means *any* adjacent-pair gap value G > 0 in the
  /// sorted row — even a 2-peer row qualifies, matching Figma's
  /// behaviour where a single visible gap is enough rhythm to extend.
  /// We only consider extension snaps when the moved rect lies
  /// entirely outside the row's span on the active axis — otherwise
  /// the between-peers logic in [_spacingAxisSnap] is the right tool.
  _SpacingMatch? _patternSpacing({
    required Rect moved,
    required List<Rect> peers,
    required double tolerance,
    required bool horizontal,
    double? stickyGap,
    double releaseTolerance = 0,
  }) {
    // Filter to row-mates: peers overlapping moved on the
    // perpendicular axis.
    final row = <Rect>[];
    for (final p in peers) {
      final perpOverlap = horizontal
          ? p.bottom > moved.top && p.top < moved.bottom
          : p.right > moved.left && p.left < moved.right;
      if (perpOverlap) row.add(p);
    }
    if (row.length < 2) return null;
    row.sort(
      (a, b) => horizontal ? a.left.compareTo(b.left) : a.top.compareTo(b.top),
    );

    // Compute adjacent-pair gaps. Skip zero / negative gaps: a 0-gap
    // candidate would snap moved into edge-overlap with the leftmost
    // or rightmost row peer, which is never the rhythm the user
    // intended.
    final gaps = <double>[];
    for (var i = 0; i < row.length - 1; i++) {
      final gap = horizontal
          ? row[i + 1].left - row[i].right
          : row[i + 1].top - row[i].bottom;
      if (gap > 0) gaps.add(gap);
    }
    if (gaps.isEmpty) return null;

    // Moved must lie fully outside the row's span on the active axis;
    // otherwise the between-peers logic should have handled it.
    final rowFirst = row.first;
    final rowLast = row.last;
    final mLead = horizontal ? moved.left : moved.top;
    final mTrail = horizontal ? moved.right : moved.bottom;
    final rowLeadEdge = horizontal ? rowFirst.left : rowFirst.top;
    final rowTrailEdge = horizontal ? rowLast.right : rowLast.bottom;
    final isAfter = mLead >= rowTrailEdge;
    final isBefore = mTrail <= rowLeadEdge;
    if (!isAfter && !isBefore) return null;

    // For each candidate gap value G, propose moved.lead = rowTrailEdge + G
    // (after) or moved.trail = rowLeadEdge - G (before). Snap if within
    // tolerance. Sticky gap widens tolerance for hysteresis.
    _SpacingMatch? best;
    var bestCorrection = tolerance;
    for (final g in gaps) {
      final isSticky = stickyGap != null && (g - stickyGap).abs() < 0.5;
      final tol = isSticky ? releaseTolerance : tolerance;
      double targetLead;
      if (isAfter) {
        targetLead = rowTrailEdge + g;
      } else {
        targetLead = rowLeadEdge - g - (mTrail - mLead);
      }
      final correction = (mLead - targetLead).abs();
      if (correction > tol) continue;
      if (best != null && correction > bestCorrection) continue;

      final delta = targetLead - mLead;
      // Build guide for the single visible gap segment between the
      // moved rect and the nearest row peer, plus an "echo" segment
      // showing the established rhythm on the opposite side of the
      // adjacent row peer — matches Figma's two-bracket convention.
      final crossCoord = horizontal
          ? (rowFirst.center.dy + moved.center.dy + rowLast.center.dy) / 3.0
          : (rowFirst.center.dx + moved.center.dx + rowLast.center.dx) / 3.0;
      final rowLastLead = horizontal ? rowLast.left : rowLast.top;
      final rowFirstTrail = horizontal ? rowFirst.right : rowFirst.bottom;
      final double fromStart, fromEnd, toStart, toEnd;
      if (isAfter) {
        // Visible gap: between rowLast and moved.
        fromStart = rowTrailEdge;
        fromEnd = mLead + delta;
        // Echo gap: between row[-2] and rowLast (the rhythm we matched).
        final priorPeer = row[row.length - 2];
        final priorTrail = horizontal ? priorPeer.right : priorPeer.bottom;
        toStart = priorTrail;
        toEnd = rowLastLead;
      } else {
        // Visible gap: between moved and rowFirst.
        fromStart = mTrail + delta;
        fromEnd = rowLeadEdge;
        // Echo gap: between rowFirst and row[1].
        final nextPeer = row[1];
        final nextLead = horizontal ? nextPeer.left : nextPeer.top;
        toStart = rowFirstTrail;
        toEnd = nextLead;
      }

      bestCorrection = correction;
      best = _SpacingMatch(
        delta: delta,
        guide: SpacingGuide(
          axis: horizontal ? SnapAxis.vertical : SnapAxis.horizontal,
          gap: g,
          crossCoord: crossCoord,
          fromStart: fromStart,
          fromEnd: fromEnd,
          toStart: toStart,
          toEnd: toEnd,
        ),
      );
    }
    return best;
  }

  _SpacingMatch? _spacingAxisSnap({
    required Rect moved,
    required List<Rect> peers,
    required double tolerance,
    required bool horizontal,
    double? stickyGap,
    double releaseTolerance = 0,
  }) {
    _SpacingMatch? best;
    var bestCorrection = tolerance;
    for (var i = 0; i < peers.length; i++) {
      for (var j = 0; j < peers.length; j++) {
        if (i == j) continue;
        final a = peers[i];
        final b = peers[j];

        // Require `a` strictly before `b` on the active axis.
        // Require both peers to overlap the moved rect on the
        // *perpendicular* axis — that's what "in the same row" means
        // visually. We also require the moved rect to sit strictly
        // between a and b on the active axis, so we are inserting it
        // into a gap rather than measuring something nonsensical.
        late final double aTrail, bLead, mLead, mTrail;
        late final bool perpOverlap;
        if (horizontal) {
          aTrail = a.right;
          bLead = b.left;
          mLead = moved.left;
          mTrail = moved.right;
          perpOverlap =
              a.bottom > moved.top &&
              a.top < moved.bottom &&
              b.bottom > moved.top &&
              b.top < moved.bottom;
        } else {
          aTrail = a.bottom;
          bLead = b.top;
          mLead = moved.top;
          mTrail = moved.bottom;
          perpOverlap =
              a.right > moved.left &&
              a.left < moved.right &&
              b.right > moved.left &&
              b.left < moved.right;
        }
        if (!perpOverlap) continue;
        // a strictly before b
        if (aTrail > bLead) continue;
        // moved strictly between a and b
        if (mLead < aTrail || mTrail > bLead) continue;

        final gapLeft = mLead - aTrail;
        final gapRight = bLead - mTrail;
        if (gapLeft < 0 || gapRight < 0) continue;
        final diff = (gapLeft - gapRight).abs();
        // The correction needed to equalize is half the diff (we shift
        // the moved rect by ±diff/2 toward the wider gap's side).
        final correction = diff / 2;
        final equalGap = (gapLeft + gapRight) / 2;
        // Sticky widening: a candidate whose resulting equal-gap
        // matches the gap value held last frame may exceed the base
        // tolerance up to [releaseTolerance]. Closer non-sticky still
        // beats farther sticky (we sort strictly by [correction]) —
        // hysteresis only *retains* an engagement, never traps it.
        final isSticky =
            stickyGap != null && (equalGap - stickyGap).abs() < 0.5;
        final tol = isSticky ? releaseTolerance : tolerance;
        if (correction > tol) continue;
        // Closest wins among survivors. The null check lets sticky
        // candidates outside [tolerance] but inside [releaseTolerance]
        // become the first match; later non-sticky candidates within
        // base [tolerance] can still overtake them by being closer.
        if (best != null && correction > bestCorrection) continue;

        // Shift moved toward the wider gap so both gaps converge to
        // the mean. When gapLeft is wider, we move *backward* along
        // the axis (negative delta), which shrinks gapLeft and grows
        // gapRight by the same amount until they meet in the middle.
        final delta = gapLeft > gapRight ? -correction : correction;
        if (equalGap < 0 || !equalGap.isFinite) continue;

        // Build the guide. crossCoord is the midline shared by all
        // three rects on the perpendicular axis — pick the average of
        // the three centres so the bracket sits visually centred.
        final double crossCoord;
        final double fromStart, fromEnd, toStart, toEnd;
        if (horizontal) {
          crossCoord = (a.center.dy + moved.center.dy + b.center.dy) / 3.0;
          fromStart = a.right;
          fromEnd = mLead + delta;
          toStart = mTrail + delta;
          toEnd = b.left;
        } else {
          crossCoord = (a.center.dx + moved.center.dx + b.center.dx) / 3.0;
          fromStart = a.bottom;
          fromEnd = mLead + delta;
          toStart = mTrail + delta;
          toEnd = b.top;
        }
        bestCorrection = correction;
        best = _SpacingMatch(
          delta: delta,
          guide: SpacingGuide(
            axis: horizontal ? SnapAxis.vertical : SnapAxis.horizontal,
            gap: equalGap,
            crossCoord: crossCoord,
            fromStart: fromStart,
            fromEnd: fromEnd,
            toStart: toStart,
            toEnd: toEnd,
          ),
        );
      }
    }
    return best;
  }
}

class _SnapCandidate {
  const _SnapCandidate({
    required this.value,
    required this.ownStart,
    required this.ownEnd,
  });
  final double value;
  final double ownStart;
  final double ownEnd;
}

class _SnapTarget {
  const _SnapTarget({
    required this.coord,
    required this.peerStart,
    required this.peerEnd,
  });
  final double coord;
  final double peerStart;
  final double peerEnd;
}

class _SnapMatch {
  const _SnapMatch({required this.candidate, required this.target});
  final _SnapCandidate candidate;
  final _SnapTarget target;
}

class _SpacingMatch {
  const _SpacingMatch({required this.delta, required this.guide});

  /// Signed shift along the active axis required to equalize the gaps.
  final double delta;
  final SpacingGuide guide;
}

/// Convenience: build the list of peer rects (excluding the moving layer)
/// from a document snapshot. Callers in the application layer do this; the
/// engine stays decoupled from [EditorLayer].
extension SnapPeerBuilder on List<LayerTransform> {
  List<Rect> asPeerRects() {
    return <Rect>[for (final t in this) t.unrotatedRect];
  }
}
