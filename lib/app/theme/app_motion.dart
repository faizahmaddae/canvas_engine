import 'package:flutter/widgets.dart';

/// The app's motion vocabulary (tb5 3/9).
///
/// Forty-seven hand-typed `Duration(milliseconds: …)` literals across
/// the editor and the shell had settled — by convergent evolution
/// rather than by decision — on four values and one curve. Naming
/// them makes the convention checkable: a new surface picks a role,
/// not a number, and a reviewer can see when something is off-system
/// instead of having to remember that 160 is "the usual".
///
/// Roles, not sizes. Pick by what the animation IS:
abstract final class AppMotion {
  /// A control acknowledging a tap: chip fills, tile tints, segment
  /// selection. Short enough to read as instant feedback.
  static const Duration state = Duration(milliseconds: 140);

  /// The default for a visible change of state — swatch selection,
  /// strip tint, capsule content swaps. The most-used value.
  static const Duration standard = Duration(milliseconds: 160);

  /// Something growing or collapsing in place: disclosures, inline
  /// expansions, height changes.
  static const Duration reveal = Duration(milliseconds: 180);

  /// A surface arriving or leaving: sheets, panels, overlays.
  static const Duration surface = Duration(milliseconds: 240);

  /// Deceleration curve for everything that arrives.
  static const Curve curve = Curves.easeOutCubic;

  /// Acceleration curve for the rarer case of something leaving.
  static const Curve curveOut = Curves.easeInCubic;

  /// [duration], or zero when the platform asks for reduced motion.
  ///
  /// "Reduce Motion" is an accessibility setting for people who get
  /// motion sickness or vestibular symptoms from animation, and
  /// Flutter surfaces it as `MediaQuery.disableAnimations`. Honouring
  /// it means the END STATE still happens — the panel still opens,
  /// the chip still fills — it just arrives without the tween.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : duration;
}
