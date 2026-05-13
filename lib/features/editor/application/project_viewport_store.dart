import 'dart:async';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/core/viewport_state.dart';

/// Persists per-project [ViewportState] (zoom + pan) so reopening a
/// project restores the user's zoom level and scroll position.
///
/// ## Why a separate store, not the project file?
///
/// Viewport is **presentation state**, not document state. Saving it
/// inside the [EditorDocument] JSON would:
///
///   * Bump the schema (every old document grows a viewport block).
///   * Cause a "viewport changed" autosave write on every pinch.
///   * Make sharing a project file leak the original author's
///     last-zoom level to the recipient.
///
/// Keeping it in [SharedPreferences] keyed by `projectId` gives
/// per-device, per-user state with no schema impact.
///
/// ## Storage shape
///
/// One key per project: `viewport.<projectId>` → "scale|tx|ty".
/// Plain string is enough — three doubles, no nesting, never touched
/// by hand. If parsing ever fails the call returns `null` and the
/// editor falls back to its auto-fit (which is the same behaviour as
/// "no saved viewport", so a corrupted entry is self-healing).
class ProjectViewportStore {
  ProjectViewportStore({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _key(String projectId) => 'viewport.$projectId';

  /// Read the saved viewport for [projectId], or `null` if no entry
  /// exists or the entry is malformed. Never throws.
  Future<ViewportState?> load(String projectId) async {
    final prefs = await _instance();
    final raw = prefs.getString(_key(projectId));
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final scale = double.tryParse(parts[0]);
    final tx = double.tryParse(parts[1]);
    final ty = double.tryParse(parts[2]);
    if (scale == null || tx == null || ty == null) return null;
    if (!scale.isFinite || !tx.isFinite || !ty.isFinite) return null;
    return ViewportState(scale: scale, translation: Offset(tx, ty));
  }

  /// Save [viewport] for [projectId]. Best-effort; failures are
  /// swallowed because losing one zoom value is far better than
  /// surfacing a SharedPreferences error to the user mid-edit.
  Future<void> save(String projectId, ViewportState viewport) async {
    try {
      final prefs = await _instance();
      final encoded = '${viewport.scale}|'
          '${viewport.translation.dx}|'
          '${viewport.translation.dy}';
      await prefs.setString(_key(projectId), encoded);
    } catch (_) {
      // Intentional swallow — see doc comment.
    }
  }

  /// Drop any saved viewport for [projectId]. Called when a project
  /// is deleted so abandoned entries don't accumulate.
  Future<void> clear(String projectId) async {
    try {
      final prefs = await _instance();
      await prefs.remove(_key(projectId));
    } catch (_) {/* swallow */}
  }
}
