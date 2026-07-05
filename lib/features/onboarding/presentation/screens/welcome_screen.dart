import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/app_primary_button.dart';
import '../../../../app/ui/saffron_diamond.dart';
import '../../../../app/ui/skip_text_button.dart';
import '../../../../l10n/l10n.dart';

/// First onboarding screen — design direction v2
/// (docs/design-direction-v2-calligraphy-2026-07.md): Persian
/// calligraphy IS the hero. Large nastaliq «طرحی نو» on warm paper
/// (deep ink in dark), a thin saffron flourish, a quiet clean-sans
/// subtitle, and an ink/cream CTA pinned to the bottom. Editorial,
/// rooted, unmistakably Persian.
///
/// The v1 template-card showcase and its violet hero are gone; the
/// contrast between ornate script and restrained modern UI carries
/// the whole aesthetic. Fully token-driven — the screen recolours
/// with the palette and needs no per-mode branching.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.onGetStarted,
    required this.onSkip,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSkip;

  /// The brand gesture — a fixed Persian phrase ("a new design"),
  /// deliberately NOT localized: it renders in nastaliq as the
  /// identity artwork in every locale, the way a wordmark would.
  static const heroWord = 'طرحی نو';

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entryOpacity;
  late final Animation<Offset> _entryOffset;

  /// The app's own nastaliq face from the bundled font catalog.
  /// Nastaliq hangs deep below the baseline — the generous height
  /// keeps descenders unclipped (design doc: ≈1.8–2.0).
  static const _nastaliqFamily = 'IranNastaliq';

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    final curve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entryOpacity = curve;
    _entryOffset = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ColoredBox(
      color: tokens.pageBg,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageGutter,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SaffronDiamond(),
                      SkipTextButton(
                        key: const ValueKey('onboarding-welcome-skip'),
                        label: l10n.onboardingSkip,
                        onPressed: widget.onSkip,
                      ),
                    ],
                  ),
                  Expanded(
                    child: FadeTransition(
                      opacity: _entryOpacity,
                      child: SlideTransition(
                        position: _entryOffset,
                        child: Center(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  WelcomeScreen.heroWord,
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    fontFamily: _nastaliqFamily,
                                    fontSize: compact ? 52 : 64,
                                    height: 1.9,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                                SizedBox(
                                  height: compact
                                      ? AppSpacing.sm
                                      : AppSpacing.md,
                                ),
                                // Thin saffron flourish under the
                                // calligraphy (design doc: ≈38×2).
                                Container(
                                  width: 38,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: tokens.accent,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                                SizedBox(
                                  height: compact
                                      ? AppSpacing.lg
                                      : AppSpacing.xl,
                                ),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 320,
                                  ),
                                  child: Text(
                                    l10n.onboardingWelcomeSubtitle,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypeScale.body.copyWith(
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AppPrimaryButton(
                    key: const ValueKey('onboarding-get-started'),
                    label: l10n.onboardingGetStarted,
                    onPressed: widget.onGetStarted,
                  ),
                  SizedBox(height: bottomInset + 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
