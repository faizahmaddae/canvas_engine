import 'package:flutter/material.dart';

/// Minimum tappable square (dp) for editor chrome controls.
///
/// Apple HIG / Material both converge on 44dp as the floor for a
/// reliable thumb target. Defined here (tb1 17/17, decision D-f) as
/// the single named constant; today's chrome is audited against it
/// in Stage 2, where the compact tiles and header chips adopt it —
/// nothing reads it yet, deliberately, so introducing the constant
/// is a zero-pixel change.
const double kMinHitTarget = 44;

/// Single source of truth for the editor's responsive size classes
/// (tb1 17/17 — replaces the six hand-copied `shortestSide < 380`
/// rules that had already begun to drift in comment wording).
///
/// Two axes:
///  * **compact** — small phones and ANY landscape orientation:
///    strips drop to 64dp and tiles to their narrow variant.
///  * **wide** — tablet-class (shortestSide ≥ 600, decision D-f):
///    defined now so Stage 2 consumers (side-docked panels, two-
///    column sheets) share one boundary. No consumer reads it yet;
///    adopting it must not change any phone layout.
///
/// The `*For` variants are pure (no MediaQuery) for unit tests and
/// for callers that already hold a Size/Orientation pair — e.g.
/// [FloatingToolbarPositioner.dockHeight], which is deliberately
/// context-free. The context variants read the full `MediaQuery.of`
/// (not `.sizeOf`) to keep the exact rebuild scope every replaced
/// call site already had — this extraction is byte-gated as
/// behavior-preserving.
abstract final class EditorBreakpoints {
  /// Below this shortest-side the editor is a "compact" phone.
  static const double compactMaxShortestSide = 380;

  /// At or above this shortest-side the editor is "wide" (tablet).
  static const double wideMinShortestSide = 600;

  /// Dock chip-strip height on regular phones.
  static const double stripHeightRegular = 80;

  /// Dock chip-strip height in compact mode.
  static const double stripHeightCompact = 64;

  /// Compact rule: small screen OR any landscape phone. Pure.
  static bool isCompactFor({
    required Size size,
    required Orientation orientation,
  }) {
    return size.shortestSide < compactMaxShortestSide ||
        orientation == Orientation.landscape;
  }

  /// Compact rule against the ambient [MediaQuery].
  static bool isCompact(BuildContext context) {
    final media = MediaQuery.of(context);
    return isCompactFor(size: media.size, orientation: media.orientation);
  }

  /// Wide/tablet rule. Pure. No consumer yet — see class doc.
  static bool isWideFor(Size size) => size.shortestSide >= wideMinShortestSide;

  /// Wide/tablet rule against the ambient [MediaQuery].
  static bool isWide(BuildContext context) =>
      isWideFor(MediaQuery.of(context).size);

  /// Dock strip height for an explicit geometry. Pure.
  static double stripHeightFor({
    required Size size,
    required Orientation orientation,
  }) {
    return isCompactFor(size: size, orientation: orientation)
        ? stripHeightCompact
        : stripHeightRegular;
  }

  /// Dock strip height against the ambient [MediaQuery].
  static double stripHeight(BuildContext context) =>
      isCompact(context) ? stripHeightCompact : stripHeightRegular;
}
