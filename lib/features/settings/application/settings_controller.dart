import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../editor/application/export_quality.dart';

/// Plain-data snapshot of every user-tunable preference in the app.
///
/// Lives outside any widget so it can be hashed for equality, serialised
/// to JSON, and watched reactively by both Home and Editor surfaces.
class AppSettings {
  const AppSettings({
    this.canvasPanEnabled = true,
    this.canvasZoomEnabled = true,
    this.canvasRotationEnabled = true,
    this.defaultExportQuality = ExportQuality.original,
    this.snapToGuides = true,
    this.showSpacingGuides = true,
    this.multiFingerUndoRedoEnabled = false,
    this.rightHandedToolbar = false,
  });

  /// Sentinel used while preferences load from disk.
  static const AppSettings defaults = AppSettings();

  final bool canvasPanEnabled;
  final bool canvasZoomEnabled;
  final bool canvasRotationEnabled;
  final ExportQuality defaultExportQuality;
  final bool snapToGuides;
  final bool showSpacingGuides;

  /// Opt-in Procreate-style tap shortcuts:
  ///   * 2-finger tap on the canvas → undo
  ///   * 3-finger tap on the canvas → redo
  ///
  /// Disabled by default because the gesture competes with legitimate
  /// 2-/3-finger interactions (pinch-to-zoom on empty canvas,
  /// multi-touch on a selection) and some users find it triggers
  /// unintentionally. Power users can enable it from Settings.
  final bool multiFingerUndoRedoEnabled;

  /// When true the bottom tool strip aligns to the **right** edge
  /// (when its tools fit in the viewport) so the row sits closest
  /// to the right thumb. **Tool order is never reversed** —
  /// primary tools (Font, Styles, Color, …) always appear in the
  /// same sequence regardless of handedness; only the row's
  /// alignment / placement changes. Default false (left/center).
  final bool rightHandedToolbar;

  AppSettings copyWith({
    bool? canvasPanEnabled,
    bool? canvasZoomEnabled,
    bool? canvasRotationEnabled,
    ExportQuality? defaultExportQuality,
    bool? snapToGuides,
    bool? showSpacingGuides,
    bool? multiFingerUndoRedoEnabled,
    bool? rightHandedToolbar,
  }) {
    return AppSettings(
      canvasPanEnabled: canvasPanEnabled ?? this.canvasPanEnabled,
      canvasZoomEnabled: canvasZoomEnabled ?? this.canvasZoomEnabled,
      canvasRotationEnabled:
          canvasRotationEnabled ?? this.canvasRotationEnabled,
      defaultExportQuality:
          defaultExportQuality ?? this.defaultExportQuality,
      snapToGuides: snapToGuides ?? this.snapToGuides,
      showSpacingGuides: showSpacingGuides ?? this.showSpacingGuides,
      multiFingerUndoRedoEnabled:
          multiFingerUndoRedoEnabled ?? this.multiFingerUndoRedoEnabled,
      rightHandedToolbar:
          rightHandedToolbar ?? this.rightHandedToolbar,
    );
  }

  Map<String, Object?> toJson() => {
        'canvasPanEnabled': canvasPanEnabled,
        'canvasZoomEnabled': canvasZoomEnabled,
        'canvasRotationEnabled': canvasRotationEnabled,
        'defaultExportQuality': defaultExportQuality.name,
        'snapToGuides': snapToGuides,
        'showSpacingGuides': showSpacingGuides,
        'multiFingerUndoRedoEnabled': multiFingerUndoRedoEnabled,
        'rightHandedToolbar': rightHandedToolbar,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final qualityName = json['defaultExportQuality'] as String?;
    final quality = ExportQuality.values.firstWhere(
      (q) => q.name == qualityName,
      orElse: () => ExportQuality.original,
    );
    return AppSettings(
      canvasPanEnabled: json['canvasPanEnabled'] as bool? ?? true,
      canvasZoomEnabled: json['canvasZoomEnabled'] as bool? ?? true,
      canvasRotationEnabled:
          json['canvasRotationEnabled'] as bool? ?? true,
      defaultExportQuality: quality,
      snapToGuides: json['snapToGuides'] as bool? ?? true,
      showSpacingGuides: json['showSpacingGuides'] as bool? ?? true,
      // Default false: existing users who never touched the setting
      // get the safer behaviour without surprise regressions.
      multiFingerUndoRedoEnabled:
          json['multiFingerUndoRedoEnabled'] as bool? ?? false,
      rightHandedToolbar:
          json['rightHandedToolbar'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.canvasPanEnabled == canvasPanEnabled &&
      other.canvasZoomEnabled == canvasZoomEnabled &&
      other.canvasRotationEnabled == canvasRotationEnabled &&
      other.defaultExportQuality == defaultExportQuality &&
      other.snapToGuides == snapToGuides &&
      other.showSpacingGuides == showSpacingGuides &&
      other.multiFingerUndoRedoEnabled == multiFingerUndoRedoEnabled &&
      other.rightHandedToolbar == rightHandedToolbar;

  @override
  int get hashCode => Object.hash(
        canvasPanEnabled,
        canvasZoomEnabled,
        canvasRotationEnabled,
        defaultExportQuality,
        snapToGuides,
        showSpacingGuides,
        multiFingerUndoRedoEnabled,
        rightHandedToolbar,
      );
}

/// Reactive settings store backed by [SharedPreferences].
///
/// Stored as one JSON blob so adding a new preference never requires a
/// migration step — fields default sensibly when missing from disk.
class SettingsController extends AsyncNotifier<AppSettings> {
  static const String _storageKey = 'app.settings.v1';

  late SharedPreferences _prefs;

  @override
  Future<AppSettings> build() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return AppSettings.defaults;
    try {
      return AppSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return AppSettings.defaults;
    }
  }

  Future<void> _persist(AppSettings next) async {
    state = AsyncData(next);
    await _prefs.setString(_storageKey, jsonEncode(next.toJson()));
  }

  Future<void> _mutate(
    AppSettings Function(AppSettings current) mutator,
  ) async {
    final current = state.value ?? AppSettings.defaults;
    final next = mutator(current);
    if (next == current) return;
    await _persist(next);
  }

  Future<void> setCanvasPanEnabled(bool value) =>
      _mutate((s) => s.copyWith(canvasPanEnabled: value));

  Future<void> setCanvasZoomEnabled(bool value) =>
      _mutate((s) => s.copyWith(canvasZoomEnabled: value));

  Future<void> setCanvasRotationEnabled(bool value) =>
      _mutate((s) => s.copyWith(canvasRotationEnabled: value));

  Future<void> setDefaultExportQuality(ExportQuality value) =>
      _mutate((s) => s.copyWith(defaultExportQuality: value));

  Future<void> setSnapToGuides(bool value) =>
      _mutate((s) => s.copyWith(snapToGuides: value));

  Future<void> setShowSpacingGuides(bool value) =>
      _mutate((s) => s.copyWith(showSpacingGuides: value));

  Future<void> setMultiFingerUndoRedoEnabled(bool value) =>
      _mutate((s) => s.copyWith(multiFingerUndoRedoEnabled: value));

  Future<void> setRightHandedToolbar(bool value) =>
      _mutate((s) => s.copyWith(rightHandedToolbar: value));
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Convenience: synchronous snapshot. Falls back to [AppSettings.defaults]
/// while the preferences file is loading so callers never need to handle
/// the loading state themselves — settings are global, always available.
final appSettingsProvider = Provider<AppSettings>((ref) {
  final async = ref.watch(settingsControllerProvider);
  return async.value ?? AppSettings.defaults;
});
