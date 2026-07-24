import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/paint_commands.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../domain/paint_tool_type.dart';

/// The engine kind a tool draws. `null` for the eraser, which never
/// reaches the draft pipeline.
///
/// Lives here (application) rather than in the draw surface so both
/// the gesture pipeline and the dock's restyle path agree on the
/// mapping — they used to hold separate copies.
PaintKind? paintKindForTool(PaintToolType tool) => switch (tool) {
  PaintToolType.freestyle => PaintKind.freestyle,
  PaintToolType.line => PaintKind.line,
  PaintToolType.arrow => PaintKind.arrow,
  PaintToolType.rectangle => PaintKind.rectangle,
  PaintToolType.circle => PaintKind.circle,
  PaintToolType.dashLine => PaintKind.dashLine,
  PaintToolType.dashDotLine => PaintKind.dashDotLine,
  PaintToolType.hexagon => PaintKind.hexagon,
  PaintToolType.polygon => PaintKind.polygon,
  PaintToolType.blur => PaintKind.blur,
  PaintToolType.eraser => null,
};

/// Snapshot of the user's current paint configuration.
///
/// One immutable value object holds **everything** the paint pipeline
/// needs to start a stroke: which tool is active, plus the visual
/// parameters that future stroke-creation logic will consume. Adding a
/// new dimension (fill, dash gap, blur radius, polygon sides, …) is a
/// single field + a single line in [copyWith] — the rest of the system
/// stays untouched.
///
/// `panelOpen` is intentionally part of the same value so the panel's
/// open/closed state is reactively co-located with tool selection. The
/// editor treats `activeTool == null` as "nothing selected"; it can
/// still keep the panel open in that interim moment without ambiguity.
@immutable
class PaintSession {
  const PaintSession({
    this.panelOpen = false,
    this.activeTool,
    this.openSlot,
    this.strokeColor = const Color(0xFFFF3B30),
    this.strokeWidth = 6.0,
    this.fillColor,
    this.blurRadius = 16.0,
    this.polygonSides = 6,
  });

  static const PaintSession initial = PaintSession();

  /// Whether the paint sub-tool panel is currently visible above the
  /// bottom toolbar.
  final bool panelOpen;

  /// Currently-selected paint tool. `null` when the user has opened the
  /// panel but not yet picked a tool, or when paint mode is dormant.
  final PaintToolType? activeTool;

  /// Identifier of the quick-action slot whose inline expansion row
  /// is currently shown above the capsule (`'tool'`, `'color'`,
  /// `'size'`). `null` when no inline row is open.
  final String? openSlot;

  // Future-ready stroke configuration.
  final Color strokeColor;
  final double strokeWidth;
  final Color? fillColor;
  final double blurRadius;
  final int polygonSides;

  PaintSession copyWith({
    bool? panelOpen,
    Object? activeTool = _sentinel,
    String? openSlot,
    bool clearOpenSlot = false,
    Color? strokeColor,
    double? strokeWidth,
    Object? fillColor = _sentinel,
    double? blurRadius,
    int? polygonSides,
  }) {
    return PaintSession(
      panelOpen: panelOpen ?? this.panelOpen,
      activeTool: identical(activeTool, _sentinel)
          ? this.activeTool
          : activeTool as PaintToolType?,
      openSlot: clearOpenSlot ? null : (openSlot ?? this.openSlot),
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fillColor: identical(fillColor, _sentinel)
          ? this.fillColor
          : fillColor as Color?,
      blurRadius: blurRadius ?? this.blurRadius,
      polygonSides: polygonSides ?? this.polygonSides,
    );
  }

  static const Object _sentinel = Object();
}

/// Reactive paint session state.
///
/// The controller is intentionally thin — it owns transitions, not
/// rendering. The drawing engine (built in a later phase) will subscribe
/// to this controller to pick up the active tool + stroke config when
/// the user puts a finger down on the canvas.
class PaintToolController extends Notifier<PaintSession> {
  @override
  PaintSession build() => PaintSession.initial;

  /// Toggle the panel open/closed. Used by the bottom toolbar's Paint
  /// item. Closing the panel also clears the active tool so paint mode
  /// doesn't silently linger after the user dismisses the panel.
  void togglePanel() {
    if (state.panelOpen) {
      state = state.copyWith(panelOpen: false, activeTool: null);
    } else {
      state = state.copyWith(panelOpen: true);
    }
  }

  /// Force the panel open without changing tool selection. Useful for
  /// programmatic entry points (e.g. context menus) that want to reveal
  /// paint UI without committing to a tool yet.
  void openPanel() {
    if (state.panelOpen) return;
    state = state.copyWith(panelOpen: true);
  }

  /// Hide the panel and exit paint mode.
  void closePanel() {
    if (!state.panelOpen && state.activeTool == null) return;
    state = state.copyWith(
      panelOpen: false,
      activeTool: null,
      clearOpenSlot: true,
    );
  }

  /// Wipe all ephemeral paint-tool UI state back to
  /// [PaintSession.initial]. Intended for project-switch boundaries
  /// so brand-new / freshly-opened projects don't inherit the
  /// previous project's tool selection, stroke colour/width, dash
  /// pattern, blur, or polygon sides.
  void resetSession() {
    state = PaintSession.initial;
  }

  // ─── inline slot expansions (Adaptive Dock) ──────────────────────

  /// Toggle the inline expansion for the given slot id.
  void toggleSlot(String slotId) {
    if (state.openSlot == slotId) {
      state = state.copyWith(clearOpenSlot: true);
    } else {
      state = state.copyWith(openSlot: slotId);
    }
  }

  /// Non-toggling variant: opens the slot if not already active.
  /// Re-tapping the active tile is a no-op so users can't
  /// accidentally dismiss the sheet by double-tapping. Dismissal is
  /// via the drag handle, swipe-down, or the Done pill.
  void openSlot(String slotId) {
    if (state.openSlot == slotId) return;
    state = state.copyWith(openSlot: slotId);
  }

  /// Force the inline slot row closed.
  void closeSlot() {
    if (state.openSlot == null) return;
    state = state.copyWith(clearOpenSlot: true);
  }

  /// Select a paint sub-tool. No-op for tools that aren't yet
  /// available — the panel renders them as disabled, but we guard here
  /// too so any future programmatic caller can't put the controller
  /// into an unsupported state.
  ///
  /// Also clears any layer selection so the screen-space selection
  /// chrome (body drag, handles) can't intercept paint gestures.
  void selectTool(PaintToolType tool) {
    if (!tool.available) return;
    ref.read(selectionControllerProvider.notifier).clear();
    state = state.copyWith(
      panelOpen: true,
      activeTool: tool,
      clearOpenSlot: true,
    );
  }

  /// Deselect the current tool while keeping the panel open. Lets the
  /// user "un-arm" without closing the panel.
  void clearTool() {
    if (state.activeTool == null) return;
    state = state.copyWith(activeTool: null);
  }

  // Future-facing setters. Kept here so all paint-state mutation flows
  // through this single controller, regardless of which UI surface
  // (panel, color picker, slider) initiated the change.
  //
  // Each setter also mirrors to the currently-selected paint layer
  // (if any) as a single undoable command, so the floating quick
  // toolbar can edit a committed layer's style without duplicating
  // any logic. Mirrors the pattern used by [TextToolController].
  void setStrokeColor(Color color) {
    if (state.strokeColor != color) {
      state = state.copyWith(strokeColor: color);
    }
    final layer = selectedPaintLayer();
    if (layer != null && layer.strokeColor != color) {
      ref
          .read(documentControllerProvider.notifier)
          .execute(
            UpdatePaintStyleCommand(layerId: layer.id, strokeColor: color),
          );
    }
  }

  void setStrokeWidth(double width) {
    if (state.strokeWidth != width) {
      state = state.copyWith(strokeWidth: width);
    }
    final layer = selectedPaintLayer();
    if (layer != null && layer.strokeWidth != width) {
      ref
          .read(documentControllerProvider.notifier)
          .execute(
            UpdatePaintStyleCommand(layerId: layer.id, strokeWidth: width),
          );
    }
  }

  // ─── Contract §2 preview channel: stroke colour (tb2 4/16) ─────
  //
  // Mirrors the width channel below: the session default tracks
  // every preview tick (readouts + next stroke), and when a paint
  // layer is selected the mirrored edit stages on the live overlay
  // and commits as ONE UpdatePaintStyleCommand on settle. The
  // colour picker's onCommitted also fires for a cancelled eyedrop
  // at the original colour — the pending command then applies to
  // an identical doc and execute() drops it (§3 no net-zero).
  UpdatePaintStyleCommand? _pendingStrokeColorCommit;

  void previewStrokeColor(Color color) {
    if (state.strokeColor != color) {
      state = state.copyWith(strokeColor: color);
    }
    final layer = selectedPaintLayer();
    if (layer == null) return;
    final cmd = UpdatePaintStyleCommand(layerId: layer.id, strokeColor: color);
    _pendingStrokeColorCommit = cmd;
    final doc = ref.read(documentControllerProvider);
    final preview = cmd.apply(doc).layerById(layer.id);
    if (preview != null) {
      ref.read(liveOverlayProvider.notifier).replaceLayer(preview);
    }
  }

  void commitStrokeColor() {
    final cmd = _pendingStrokeColorCommit;
    _pendingStrokeColorCommit = null;
    if (cmd == null) return;
    ref.read(liveOverlayProvider.notifier).clear();
    ref.read(documentControllerProvider.notifier).execute(cmd);
  }

  // ─── Contract §2 preview channel: fill colour (tb2 4/16) ───────
  //
  // Same channel for the Fill panel's custom-picker drags. The
  // discrete fill cards (No fill / Same color) stay on the direct
  // [setFillColor] path — a tap is its own history entry (§3).
  UpdatePaintStyleCommand? _pendingFillColorCommit;

  void previewFillColor(Color? color) {
    if (state.fillColor != color) {
      state = state.copyWith(fillColor: color);
    }
    final layer = selectedPaintLayer();
    if (layer == null) return;
    final cmd = UpdatePaintStyleCommand(
      layerId: layer.id,
      setFillColor: true,
      fillColor: color,
    );
    _pendingFillColorCommit = cmd;
    final doc = ref.read(documentControllerProvider);
    final preview = cmd.apply(doc).layerById(layer.id);
    if (preview != null) {
      ref.read(liveOverlayProvider.notifier).replaceLayer(preview);
    }
  }

  void commitFillColor() {
    final cmd = _pendingFillColorCommit;
    _pendingFillColorCommit = null;
    if (cmd == null) return;
    ref.read(liveOverlayProvider.notifier).clear();
    ref.read(documentControllerProvider.notifier).execute(cmd);
  }

  // ─── Contract §2 preview channel: stroke width (tb2 3/16) ──────
  //
  // Slider drags call [previewStrokeWidth] per tick and
  // [commitStrokeWidth] once on release / pointer-cancel / preset
  // tap. The session default updates per tick (it drives readouts
  // and the next stroke and is NOT a document write); when a paint
  // layer is selected, the layer edit stages on the live overlay
  // and commits as ONE undoable command. When nothing is selected
  // the drag is session-only — exactly the historical split.
  UpdatePaintStyleCommand? _pendingWidthCommit;

  void previewStrokeWidth(double width) {
    if (state.strokeWidth != width) {
      state = state.copyWith(strokeWidth: width);
    }
    final layer = selectedPaintLayer();
    if (layer == null) return;
    final cmd = UpdatePaintStyleCommand(layerId: layer.id, strokeWidth: width);
    // The pending command is the exact command commit executes;
    // each tick APPLIES it to the committed doc and stages the
    // result, so preview == commit by construction.
    _pendingWidthCommit = cmd;
    final doc = ref.read(documentControllerProvider);
    final preview = cmd.apply(doc).layerById(layer.id);
    if (preview != null) {
      ref.read(liveOverlayProvider.notifier).replaceLayer(preview);
    }
  }

  void commitStrokeWidth() {
    final cmd = _pendingWidthCommit;
    _pendingWidthCommit = null;
    if (cmd == null) return;
    // Clear-then-execute in one synchronous run — no flash-back
    // frame. A drag that ends where it started no-ops inside
    // execute() (apply returns the identical doc), so no net-zero
    // history entry is pushed (§3).
    ref.read(liveOverlayProvider.notifier).clear();
    ref.read(documentControllerProvider.notifier).execute(cmd);
  }

  void setFillColor(Color? color) {
    if (state.fillColor != color) {
      state = state.copyWith(fillColor: color);
    }
    final layer = selectedPaintLayer();
    if (layer != null && layer.fillColor != color) {
      ref
          .read(documentControllerProvider.notifier)
          .execute(
            UpdatePaintStyleCommand(
              layerId: layer.id,
              setFillColor: true,
              fillColor: color,
            ),
          );
    }
  }

  /// Toggle fill on/off without losing the previously chosen colour.
  /// When turning fill on for the first time we seed it with the
  /// current stroke colour so the user sees an immediate, sensible
  /// result. Stroke editing or fill-colour overrides remain free to
  /// change either independently afterwards.
  ///
  /// Mirrors the same enable/disable to a selected paint layer (if
  /// any) as one undoable command.
  void setFillEnabled(bool enabled) {
    Color? next;
    if (enabled) {
      next = state.fillColor ?? state.strokeColor;
    } else {
      next = null;
    }
    if (state.fillColor != next) {
      state = state.copyWith(fillColor: next);
    }
    final layer = selectedPaintLayer();
    if (layer == null) return;
    final layerNext = enabled ? (layer.fillColor ?? layer.strokeColor) : null;
    if (layer.fillColor == layerNext) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(
          UpdatePaintStyleCommand(
            layerId: layer.id,
            setFillColor: true,
            fillColor: layerNext,
          ),
        );
  }

  /// Blur sigma. Mirrors onto a selected blur layer so the control
  /// edits what the user is looking at (tb4 3/14) — before this, the
  /// slot was hidden whenever a paint layer was selected because it
  /// only moved a session default.
  void setBlurRadius(double radius) {
    if (state.blurRadius != radius) {
      state = state.copyWith(blurRadius: radius);
    }
    final layer = selectedPaintLayer();
    if (layer == null || layer.kind != PaintKind.blur) return;
    if (layer.blurSigma == radius) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(UpdatePaintStyleCommand(layerId: layer.id, blurSigma: radius));
  }

  /// Polygon side count. Mirrors onto a selected polygon layer.
  void setPolygonSides(int sides) {
    if (state.polygonSides != sides) {
      state = state.copyWith(polygonSides: sides);
    }
    final layer = selectedPaintLayer();
    if (layer == null || layer.kind != PaintKind.polygon) return;
    if (layer.sides == sides) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(UpdatePaintStyleCommand(layerId: layer.id, sides: sides));
  }

  /// Pick a line style (solid / dashed / dotted).
  ///
  /// With a line-kind layer selected this restyles THAT layer — the
  /// three styles are peers, so the switch is geometry-safe. With
  /// nothing selected it arms the matching tool for the next stroke,
  /// which is what the body did unconditionally before tb4 3/14 (and
  /// why the slot had to be hidden for a selected layer).
  void selectLineStyle(PaintToolType tool) {
    final layer = selectedPaintLayer();
    final kind = paintKindForTool(tool);
    if (layer != null &&
        kind != null &&
        paintKindPeers(layer.kind).contains(kind)) {
      if (layer.kind == kind) return;
      ref
          .read(documentControllerProvider.notifier)
          .execute(UpdatePaintStyleCommand(layerId: layer.id, kind: kind));
      return;
    }
    selectTool(tool);
  }

  /// Switch the resize behavior of the currently-selected paint layer.
  /// No-op when nothing paint-y is selected, or when the mode is
  /// already what we'd set. Single undoable history entry.
  void setResizeMode(PaintResizeMode mode) {
    final layer = selectedPaintLayer();
    if (layer == null) return;
    if (layer.resizeMode == mode) return;
    ref
        .read(documentControllerProvider.notifier)
        .execute(SetPaintResizeModeCommand(layerId: layer.id, mode: mode));
  }

  /// Read the currently-selected paint layer (if any). Used by the
  /// dock to render against the selected layer's style instead of
  /// the session default.
  PaintLayer? selectedPaintLayer() {
    final selection = ref.read(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer = ref
        .read(documentControllerProvider)
        .layerById(selection.selectedId!);
    return layer is PaintLayer ? layer : null;
  }
}

final paintToolControllerProvider =
    NotifierProvider<PaintToolController, PaintSession>(
      PaintToolController.new,
    );

/// What the paint dock DISPLAYS.
///
/// With a paint layer selected the strip, its value labels and every
/// body read that layer's committed style; with nothing selected they
/// read the session's next-stroke defaults. Before tb4 3/14 the dock
/// only ever showed session state, so selecting an old stroke and
/// opening Color showed the colour of the *next* stroke rather than
/// the one on screen.
///
/// Writers are unchanged: every setter already mirrors to the
/// selected layer, so what you see is what you edit.
@immutable
class PaintStyleView {
  const PaintStyleView({
    required this.strokeColor,
    required this.strokeWidth,
    required this.fillColor,
    required this.sides,
    required this.blurRadius,
    this.layerKind,
  });

  final Color strokeColor;
  final double strokeWidth;
  final Color? fillColor;
  final int sides;
  final double blurRadius;

  /// The selected layer's kind, or `null` when the view is showing
  /// session defaults.
  final PaintKind? layerKind;
}

final paintStyleViewProvider = Provider<PaintStyleView>((ref) {
  final session = ref.watch(paintToolControllerProvider);
  final selection = ref.watch(selectionControllerProvider);
  final id = selection.selectedId;
  final layer = id == null
      ? null
      : ref.watch(documentControllerProvider).layerById(id);
  if (layer is PaintLayer) {
    return PaintStyleView(
      strokeColor: layer.strokeColor,
      strokeWidth: layer.strokeWidth,
      fillColor: layer.fillColor,
      sides: layer.sides,
      blurRadius: layer.blurSigma,
      layerKind: layer.kind,
    );
  }
  return PaintStyleView(
    strokeColor: session.strokeColor,
    strokeWidth: session.strokeWidth,
    fillColor: session.fillColor,
    sides: session.polygonSides,
    blurRadius: session.blurRadius,
  );
});
