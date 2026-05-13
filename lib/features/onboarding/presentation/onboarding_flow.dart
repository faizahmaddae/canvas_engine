import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/user_error.dart';
import '../../settings/application/settings_controller.dart';
import '../../templates/domain/template.dart';
import '../application/onboarding_complete_provider.dart';
import '../application/onboarding_controller.dart';
import 'screens/goal_screen.dart';
import 'screens/ready_screen.dart';
import 'screens/welcome_screen.dart';
import 'widgets/onboarding_style.dart';

/// Three-screen onboarding: Welcome → Goal → Ready → Home.
///
/// Language selection is removed entirely — the app ships Persian by
/// default; users can change it later in Settings. Welcome and Goal
/// can be skipped (skip on Goal selects every category). Ready has
/// no skip because the user has already invested in the flow.
///
/// Each transition uses an in-place fade + horizontal slide via
/// [PageRouteBuilder] / [AnimatedSwitcher] rather than a [PageView]
/// so screen state (animation controllers, render layers) is fully
/// torn down between screens — keeping the GPU budget for the active
/// screen alone.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Step { welcome, goal, ready }

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  _Step _step = _Step.welcome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingPalette.backgroundBottom,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_step),
          child: switch (_step) {
            _Step.welcome => WelcomeScreen(
              onGetStarted: () => _go(_Step.goal),
              onSkip: _skipAll,
            ),
            _Step.goal => GoalScreen(
              onContinue: _continueFromGoals,
              onSkip: _skipGoals,
            ),
            _Step.ready => ReadyScreen(onStart: _complete),
          },
        ),
      ),
    );
  }

  void _go(_Step step) => setState(() => _step = step);

  Future<void> _skipAll() async {
    await _saveSafely('onboarding/skipAll', () async {
      final settings = ref.read(settingsControllerProvider.notifier);
      await settings.setEnabledCategories(kDefaultEnabledTemplateCategories);
    });
    await _complete();
  }

  Future<void> _continueFromGoals() async {
    final choices = ref.read(onboardingControllerProvider);
    await _saveCategories(choices.effectiveCategories);
    _go(_Step.ready);
  }

  Future<void> _skipGoals() async {
    await _saveCategories(kDefaultEnabledTemplateCategories);
    // Reflect the auto-pick in shared state so Ready shows the full
    // selected preview set rather than an empty confirmation.
    final controller = ref.read(onboardingControllerProvider.notifier);
    for (final c in kDefaultEnabledTemplateCategories) {
      // toggleCategory adds when missing — Skip arrives with an empty
      // selection, so this fills the set.
      if (!ref
          .read(onboardingControllerProvider)
          .selectedCategories
          .contains(c)) {
        controller.toggleCategory(c);
      }
    }
    _go(_Step.ready);
  }

  Future<void> _saveCategories(Set<TemplateCategory> categories) async {
    await _saveSafely('onboarding/saveGoals', () async {
      await ref
          .read(settingsControllerProvider.notifier)
          .setEnabledCategories(categories);
    });
  }

  Future<void> _complete() async {
    ref.read(onboardingControllerProvider.notifier).reset();
    await ref.read(onboardingCompleteProvider.notifier).complete();
  }

  Future<void> _saveSafely(String label, Future<void> Function() save) async {
    try {
      await save();
    } catch (e, st) {
      debugLogError(label, e, st);
    }
  }
}
