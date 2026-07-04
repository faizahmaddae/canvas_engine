import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';

/// App-wide primary CTA (design doc §4) — full-width, `brand` fill,
/// `onBrand` text, radius [AppRadii.primaryButton], weight 700, with
/// a subtle press-scale.
///
/// Replaces `OnboardingPrimaryButton` going forward. Existing call
/// sites (Goal/Ready screens) migrate to this as each screen is
/// rebuilt on tokens — `OnboardingPrimaryButton` stays in place
/// until then (design doc §6).
class AppPrimaryButton extends StatefulWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
          borderRadius: BorderRadius.circular(AppRadii.primaryButton),
          child: Ink(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              color: tokens.brand,
              borderRadius: BorderRadius.circular(AppRadii.primaryButton),
            ),
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: tokens.onBrand,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
