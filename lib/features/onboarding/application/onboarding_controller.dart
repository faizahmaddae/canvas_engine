import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/application/settings_controller.dart';
import '../../templates/domain/template.dart';

/// In-flow snapshot of the user's onboarding choices.
///
/// Onboarding only asks for **goals** now (content language defaults to
/// Persian and is settable from Settings later). The selected category
/// set is what the Goal screen mutates and what Ready / Home read back.
class OnboardingChoices {
  const OnboardingChoices({this.selectedCategories = const {}});

  final Set<TemplateCategory> selectedCategories;

  /// What we actually persist when the user finishes the flow. Empty
  /// selection collapses to "all categories" so Skip and "tap nothing
  /// then continue" produce the same friendly default.
  Set<TemplateCategory> get effectiveCategories => selectedCategories.isEmpty
      ? kDefaultEnabledTemplateCategories
      : selectedCategories;

  OnboardingChoices copyWith({Set<TemplateCategory>? selectedCategories}) {
    return OnboardingChoices(
      selectedCategories: selectedCategories ?? this.selectedCategories,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OnboardingChoices &&
      setEquals(other.selectedCategories, selectedCategories);

  @override
  int get hashCode => Object.hashAllUnordered(selectedCategories);
}

class OnboardingController extends Notifier<OnboardingChoices> {
  @override
  OnboardingChoices build() => const OnboardingChoices();

  void toggleCategory(TemplateCategory category) {
    final next = {...state.selectedCategories};
    if (!next.add(category)) next.remove(category);
    state = state.copyWith(selectedCategories: Set.unmodifiable(next));
  }

  void reset() {
    state = const OnboardingChoices();
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingChoices>(
      OnboardingController.new,
    );
