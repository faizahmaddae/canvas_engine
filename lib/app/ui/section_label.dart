import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// App-wide caption/eyebrow label (design doc §4) — small labelled
/// text in [AppTokens.textMuted] at [AppTypeScale.caption].
///
/// Distinct from the editor-scoped `SectionLabel` in
/// `lib/features/editor/presentation/widgets/section_label.dart`,
/// which is `colorScheme`-driven (Material scheme, not `AppTokens`)
/// and follows the editor panel's own section-rhythm spec. The two
/// are never imported into the same file; this one is for app-wide
/// (Home/Onboarding/Templates) surfaces built on the token system.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypeScale.caption.copyWith(
        color: AppTokens.of(context).textMuted,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
