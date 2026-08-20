import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/user_error.dart';

/// Tri-state on purpose: `null` = the stored flag hasn't loaded yet.
/// The old `bool` model defaulted to `false` during the async load,
/// so every cold launch rendered the onboarding Welcome for the first
/// frame(s) and then swapped to Home under a returning user's finger
/// (ux-audit P2-16). The app shell shows a neutral surface for the
/// null frame instead of guessing wrong.
class OnboardingCompleteNotifier extends Notifier<bool?> {
  static const String storageKey = 'onboarding.complete';

  SharedPreferences? _prefs;

  @override
  bool? build() {
    unawaited(_load());
    return null;
  }

  Future<void> complete() => _setComplete(true);

  Future<void> reset() => _setComplete(false);

  Future<SharedPreferences> get _preferences async {
    final cached = _prefs;
    if (cached != null) return cached;
    return _prefs = await SharedPreferences.getInstance();
  }

  Future<void> _load() async {
    try {
      final prefs = await _preferences;
      state = prefs.getBool(storageKey) ?? false;
    } catch (e, st) {
      debugLogError('onboarding/loadComplete', e, st);
      state = false;
    }
  }

  Future<void> _setComplete(bool value) async {
    state = value;
    try {
      final prefs = await _preferences;
      final saved = await prefs.setBool(storageKey, value);
      if (!saved) {
        throw StateError('SharedPreferences refused onboarding.complete');
      }
    } catch (e, st) {
      debugLogError('onboarding/saveComplete', e, st);
    }
  }
}

final onboardingCompleteProvider =
    NotifierProvider<OnboardingCompleteNotifier, bool?>(
      OnboardingCompleteNotifier.new,
    );
