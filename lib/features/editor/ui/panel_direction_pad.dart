import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../app/theme/app_icons.dart';

/// 3×3 grid of direction cells for offset-based controls (shadow
/// direction today; any future 2D-offset knob).
///
/// Unifies the shape/image shadow `_DirectionPad` pair (geometry
/// adopted verbatim: 132 px grid, sign-based active-cell threshold,
/// rotated single arrow icon) with text's `_ShadowDirectionPad`,
/// whose distinct magnitude rule (self-computed from the offset's
/// own distance rather than a parent-supplied value) and haptics
/// (`EditorHaptics.toggle()` fired internally) move to the call
/// site — this widget stays a pure `offset -> Offset` picker with no
/// side effects, matching the shape/image convention (haptics fire
/// at the call site there too).
///
/// ## RTL fix (deliberate — Phase 4 plan D3)
///
/// The three existing copies build their grid with `GridView.count`
/// / `Row`, so under a right-to-left [Directionality] (this is a
/// Persian-first app) the cell ORDER visually mirrors while
/// [onPick] still emits physical [Offset]s — the cell drawn on the
/// visual left moves the target right. This widget pins its
/// internal layout to LTR so the grid never mirrors regardless of
/// the ambient locale; the emitted offsets are always physical and
/// now always match what the user sees.
class PanelDirectionPad extends StatelessWidget {
  const PanelDirectionPad({
    super.key,
    required this.offset,
    required this.magnitude,
    required this.onPick,
    this.activeThreshold = 0.5,
    this.size = 132,
  });

  /// Current offset, in the same units [onPick] emits (typically
  /// canvas/layer-local px). `Offset.zero` selects the centre cell.
  final Offset offset;

  /// Magnitude applied to the 8 perimeter cells' unit vectors.
  final double magnitude;

  final ValueChanged<Offset> onPick;

  /// Below this absolute value on an axis, that axis reads as "0"
  /// when determining which cell is active.
  final double activeThreshold;

  final double size;

  @override
  Widget build(BuildContext context) {
    const cells = <(int, int)>[
      (-1, -1),
      (0, -1),
      (1, -1),
      (-1, 0),
      (0, 0),
      (1, 0),
      (-1, 1),
      (0, 1),
      (1, 1),
    ];
    final activeCell = _activeCell(offset);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: size,
        child: GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          children: [
            for (final c in cells)
              _DirectionPadCell(
                dx: c.$1,
                dy: c.$2,
                selected: activeCell == c,
                onTap: () => onPick(
                  c.$1 == 0 && c.$2 == 0
                      ? Offset.zero
                      : Offset(c.$1 * magnitude, c.$2 * magnitude),
                ),
              ),
          ],
        ),
      ),
    );
  }

  (int, int)? _activeCell(Offset off) {
    if (off == Offset.zero) return (0, 0);
    final dx = off.dx.abs() < activeThreshold ? 0 : (off.dx > 0 ? 1 : -1);
    final dy = off.dy.abs() < activeThreshold ? 0 : (off.dy > 0 ? 1 : -1);
    return (dx, dy);
  }
}

class _DirectionPadCell extends StatelessWidget {
  const _DirectionPadCell({
    required this.dx,
    required this.dy,
    required this.selected,
    required this.onTap,
  });

  final int dx;
  final int dy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final isCenter = dx == 0 && dy == 0;
    // Nine cells that were focusable, clickable and completely
    // unlabeled: a screen reader heard "unlabeled, button" nine times
    // and could tell neither which direction each one was nor which
    // was active, while the disclosure above promised «… جهت …».
    // Named and state-carrying now, matching the ضخامت and سبک chips.
    return Semantics(
      button: true,
      selected: selected,
      label: _directionLabel(context, dx, dy),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? tokens.accent.withValues(alpha: 0.16)
              : tokens.surfaceMuted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Center(
              child: isCenter
                  ? Icon(
                      AppIcons.offsetCenter,
                      size: 16,
                      color: selected
                          ? tokens.accentText
                          : tokens.textSecondary,
                    )
                  : Transform.rotate(
                      angle: _arrowAngle(dx, dy),
                      child: Icon(
                        AppIcons.offsetDirection,
                        size: 16,
                        color: selected
                            ? tokens.accentText
                            : tokens.textSecondary,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Spoken name for a cell, by offset direction. The pad is spatially
  /// literal — the arrow points where the shadow lands on screen — so
  /// these are left/right, not start/end.
  static String _directionLabel(BuildContext context, int dx, int dy) {
    final l10n = context.l10n;
    if (dx == 0 && dy == 0) return l10n.dirCenter;
    if (dy < 0) {
      return dx < 0
          ? l10n.dirTopStart
          : dx > 0
          ? l10n.dirTopEnd
          : l10n.dirTop;
    }
    if (dy > 0) {
      return dx < 0
          ? l10n.dirBottomStart
          : dx > 0
          ? l10n.dirBottomEnd
          : l10n.dirBottom;
    }
    return dx < 0 ? l10n.dirStart : l10n.dirEnd;
  }

  double _arrowAngle(int dx, int dy) {
    return math.atan2(dy.toDouble(), dx.toDouble()) + math.pi / 2;
  }
}
