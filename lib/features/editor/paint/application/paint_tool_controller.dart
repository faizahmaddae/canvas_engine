import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/document_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/commands/editor_command.dart';
import '../../engine/commands/paint_commands.dart';
import '../../engine/core/canvas_sizing.dart';
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
    if (tool != PaintToolType.eraser) _lastDrawTool = tool;
    state = state.copyWith(
      panelOpen: true,
      activeTool: tool,
      clearOpenSlot: true,
    );
  }

  /// The last non-eraser tool, so [toggleEraser] has somewhere to
  /// return to. Erasing is a detour from drawing, not a destination.
  PaintToolType _lastDrawTool = PaintToolType.freestyle;

  /// The tool the strip's draw tile represents — never the eraser,
  /// which owns its own tile.
  PaintToolType get drawTool => _lastDrawTool;

  /// Flip between erasing and whatever was being drawn before.
  ///
  /// This is the paint mode's most frequent switch and it used to cost
  /// a round trip through the tool picker — tap the tool tile, wait for
  /// a panel covering most of the canvas, find the eraser in a grid,
  /// tap it, watch the panel close. Twice, to get back. One tap now,
  /// in both directions.
  void toggleEraser() {
    if (state.activeTool == PaintToolType.eraser) {
      selectTool(_lastDrawTool);
    } else {
      // NOT through selectTool's bookkeeping — the eraser must not
      // become the tool it returns to.
      ref.read(selectionControllerProvider.notifier).clear();
      state = state.copyWith(
        panelOpen: true,
        activeTool: PaintToolType.eraser,
        clearOpenSlot: true,
      );
    }
  }

  /// A paint control has exactly one target (§10.5 N): with a selected
  /// PaintLayer it restyles that bound layer; otherwise it changes the
  /// author's defaults for the next stroke. Every plain setter shares
  /// this branch — [onLayer] returns the command to execute, or `null`
  /// for a no-op (unchanged value, or a kind guard rejecting it);
  /// [onSessionDefault] runs only when nothing is bound.
  void _writeStyle({
    required EditorCommand? Function(PaintLayer layer) onLayer,
    required void Function() onSessionDefault,
  }) {
    final layer = selectedPaintLayer();
    if (layer != null) {
      final cmd = onLayer(layer);
      if (cmd != null) {
        ref.read(documentControllerProvider.notifier).execute(cmd);
      }
      return;
    }
    onSessionDefault();
  }

  void setStrokeColor(Color color) => _writeStyle(
    onLayer: (layer) => layer.strokeColor == color
        ? null
        : UpdatePaintStyleCommand(layerId: layer.id, strokeColor: color),
    onSessionDefault: () {
      if (state.strokeColor != color) {
        state = state.copyWith(strokeColor: color);
      }
    },
  );

  void setStrokeWidth(double width) => _writeStyle(
    onLayer: (layer) => layer.strokeWidth == width
        ? null
        : UpdatePaintStyleCommand(layerId: layer.id, strokeWidth: width),
    onSessionDefault: () {
      if (state.strokeWidth != width) {
        state = state.copyWith(strokeWidth: width);
      }
    },
  );

  /// Shared preview-channel mechanics (contract §2): stage a live-
  /// overlay preview for a bound layer, or write straight through to
  /// the session default when nothing is selected. [buildCommand]
  /// returns `null` to skip staging (e.g. blur's kind guard) — that
  /// branch must not touch the session default either. The colour
  /// picker's onCommitted also fires for a cancelled eyedrop at the
  /// original colour — the pending command then applies to an
  /// identical doc and execute() drops it (§3 no net-zero).
  void _previewStyle({
    required UpdatePaintStyleCommand? pending,
    required void Function(UpdatePaintStyleCommand?) setPending,
    required UpdatePaintStyleCommand? Function(PaintLayer layer) buildCommand,
    required void Function() onSessionDefault,
  }) {
    final hadPending = pending != null;
    setPending(null);
    final layer = selectedPaintLayer();
    if (layer == null) {
      if (hadPending) ref.read(liveOverlayProvider.notifier).clear();
      onSessionDefault();
      return;
    }
    final cmd = buildCommand(layer);
    if (cmd == null) {
      if (hadPending) ref.read(liveOverlayProvider.notifier).clear();
      return;
    }
    setPending(cmd);
    final doc = ref.read(documentControllerProvider);
    final preview = cmd.apply(doc).layerById(layer.id);
    if (preview != null) {
      ref.read(liveOverlayProvider.notifier).replaceLayer(preview);
    }
  }

  /// [pending]/[setPending] read/write the CALLER's own private field —
  /// each channel keeps its own, so an in-flight colour drag can never
  /// be clobbered by an unrelated width or blur drag.
  void _commitStyle(
    UpdatePaintStyleCommand? pending,
    void Function(UpdatePaintStyleCommand?) setPending,
  ) {
    setPending(null);
    if (pending == null) return;
    // Clear-then-execute in one synchronous run — no flash-back frame.
    // A drag that ends where it started no-ops inside execute() (apply
    // returns the identical doc), so no net-zero history entry is
    // pushed (§3).
    ref.read(liveOverlayProvider.notifier).clear();
    ref.read(documentControllerProvider.notifier).execute(pending);
  }

  // ─── Contract §2 preview channel: stroke colour (tb2 4/16) ─────
  UpdatePaintStyleCommand? _pendingStrokeColorCommit;

  void previewStrokeColor(Color color) => _previewStyle(
    pending: _pendingStrokeColorCommit,
    setPending: (cmd) => _pendingStrokeColorCommit = cmd,
    buildCommand: (layer) =>
        UpdatePaintStyleCommand(layerId: layer.id, strokeColor: color),
    onSessionDefault: () {
      if (state.strokeColor != color) {
        state = state.copyWith(strokeColor: color);
      }
    },
  );

  void commitStrokeColor() => _commitStyle(
    _pendingStrokeColorCommit,
    (cmd) => _pendingStrokeColorCommit = cmd,
  );

  /// Opacity is the alpha component of stroke colour, but owns its own
  /// slider surface. Route it through the colour preview channel so a
  /// drag changes the canvas immediately and still commits once.
  void previewStrokeOpacity(double percent) {
    final source = selectedPaintLayer()?.strokeColor ?? state.strokeColor;
    previewStrokeColor(
      source.withValues(alpha: (percent / 100).clamp(0.0, 1.0)),
    );
  }

  void commitStrokeOpacity(double percent) {
    // Preset taps have no preview ticks; staging here makes taps and
    // drags share the exact same commit path.
    previewStrokeOpacity(percent);
    commitStrokeColor();
  }

  // ─── Contract §2 preview channel: fill colour (tb2 4/16) ───────
  //
  // Same channel for the Fill panel's custom-picker drags. The
  // discrete fill cards (No fill / Same color) stay on the direct
  // [setFillColor] path — a tap is its own history entry (§3).
  UpdatePaintStyleCommand? _pendingFillColorCommit;

  void previewFillColor(Color? color) => _previewStyle(
    pending: _pendingFillColorCommit,
    setPending: (cmd) => _pendingFillColorCommit = cmd,
    buildCommand: (layer) => UpdatePaintStyleCommand(
      layerId: layer.id,
      setFillColor: true,
      fillColor: color,
    ),
    onSessionDefault: () {
      if (state.fillColor != color) state = state.copyWith(fillColor: color);
    },
  );

  void commitFillColor() => _commitStyle(
    _pendingFillColorCommit,
    (cmd) => _pendingFillColorCommit = cmd,
  );

  // ─── Contract §2 preview channel: stroke width (tb2 3/16) ──────
  //
  // Slider drags call [previewStrokeWidth] per tick and
  // [commitStrokeWidth] once on release / pointer-cancel. Author mode
  // updates only the session default; bound restyle mode stages only
  // the selected layer on the live overlay. The pending command is
  // the exact command commit executes; each tick APPLIES it to the
  // committed doc and stages the result, so preview == commit by
  // construction. [commitStrokeWidth] takes the value and previews it
  // first (mirrors [commitBlurRadius]/[commitStrokeOpacity]) because
  // PresetSliderControl's chip taps call onCommit directly with no
  // preceding preview tick.
  UpdatePaintStyleCommand? _pendingWidthCommit;

  void previewStrokeWidth(double width) => _previewStyle(
    pending: _pendingWidthCommit,
    setPending: (cmd) => _pendingWidthCommit = cmd,
    buildCommand: (layer) =>
        UpdatePaintStyleCommand(layerId: layer.id, strokeWidth: width),
    onSessionDefault: () {
      if (state.strokeWidth != width) {
        state = state.copyWith(strokeWidth: width);
      }
    },
  );

  void commitStrokeWidth(double width) {
    previewStrokeWidth(width);
    _commitStyle(_pendingWidthCommit, (cmd) => _pendingWidthCommit = cmd);
  }

  void setFillColor(Color? color) => _writeStyle(
    onLayer: (layer) => layer.fillColor == color
        ? null
        : UpdatePaintStyleCommand(
            layerId: layer.id,
            setFillColor: true,
            fillColor: color,
          ),
    onSessionDefault: () {
      if (state.fillColor != color) state = state.copyWith(fillColor: color);
    },
  );

  /// Toggle fill on/off without losing the previously chosen colour.
  /// When turning fill on for the first time we seed it with the
  /// current stroke colour so the user sees an immediate, sensible
  /// result. Stroke editing or fill-colour overrides remain free to
  /// change either independently afterwards.
  void setFillEnabled(bool enabled) => _writeStyle(
    onLayer: (layer) {
      final next = enabled ? (layer.fillColor ?? layer.strokeColor) : null;
      return layer.fillColor == next
          ? null
          : UpdatePaintStyleCommand(
              layerId: layer.id,
              setFillColor: true,
              fillColor: next,
            );
    },
    onSessionDefault: () {
      final next = enabled ? (state.fillColor ?? state.strokeColor) : null;
      if (state.fillColor != next) state = state.copyWith(fillColor: next);
    },
  );

  /// Blur controls speak reference-canvas pixels in both modes. Stored
  /// layers keep canvas pixels, so bound writes scale at the command
  /// boundary and [paintStyleViewProvider] performs the inverse read.
  void setBlurRadius(double radius) => _writeStyle(
    onLayer: (layer) {
      if (layer.kind != PaintKind.blur) return null;
      final canvasRadius = CanvasSizing.scaleDimension(
        radius,
        ref.read(documentControllerProvider),
      );
      return layer.blurSigma == canvasRadius
          ? null
          : UpdatePaintStyleCommand(layerId: layer.id, blurSigma: canvasRadius);
    },
    onSessionDefault: () {
      if (state.blurRadius != radius) {
        state = state.copyWith(blurRadius: radius);
      }
    },
  );

  UpdatePaintStyleCommand? _pendingBlurCommit;

  void previewBlurRadius(double radius) => _previewStyle(
    pending: _pendingBlurCommit,
    setPending: (cmd) => _pendingBlurCommit = cmd,
    buildCommand: (layer) {
      if (layer.kind != PaintKind.blur) return null;
      final canvasRadius = CanvasSizing.scaleDimension(
        radius,
        ref.read(documentControllerProvider),
      );
      return UpdatePaintStyleCommand(
        layerId: layer.id,
        blurSigma: canvasRadius,
      );
    },
    onSessionDefault: () {
      if (state.blurRadius != radius) {
        state = state.copyWith(blurRadius: radius);
      }
    },
  );

  void commitBlurRadius(double radius) {
    // Preset taps do not emit preview ticks.
    previewBlurRadius(radius);
    _commitStyle(_pendingBlurCommit, (cmd) => _pendingBlurCommit = cmd);
  }

  UpdatePaintStyleCommand? _pendingSidesCommit;

  /// Contract §2 preview channel for the Sides slider — same shape as
  /// blur/width: ticks stage on the live overlay for a bound polygon
  /// layer (or write the session default), commit seals ONE command.
  void previewPolygonSides(int sides) => _previewStyle(
    pending: _pendingSidesCommit,
    setPending: (cmd) => _pendingSidesCommit = cmd,
    buildCommand: (layer) => layer.kind != PaintKind.polygon
        ? null
        : UpdatePaintStyleCommand(layerId: layer.id, sides: sides),
    onSessionDefault: () {
      if (state.polygonSides != sides) {
        state = state.copyWith(polygonSides: sides);
      }
    },
  );

  void commitPolygonSides(int sides) {
    // Preset taps have no preview ticks.
    previewPolygonSides(sides);
    _commitStyle(_pendingSidesCommit, (cmd) => _pendingSidesCommit = cmd);
  }

  /// Polygon side count for the bound layer or the next stroke.
  void setPolygonSides(int sides) => _writeStyle(
    onLayer: (layer) =>
        (layer.kind != PaintKind.polygon || layer.sides == sides)
        ? null
        : UpdatePaintStyleCommand(layerId: layer.id, sides: sides),
    onSessionDefault: () {
      if (state.polygonSides != sides) {
        state = state.copyWith(polygonSides: sides);
      }
    },
  );

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

  /// Read the layer bound for restyling. A selected paint layer always
  /// wins over an armed tool — this is the single author/restyle
  /// predicate shared by every writer. Every path that ARMS a tool
  /// (selectTool, toggleEraser) clears the selection first, so the only
  /// way a tool stays armed with a layer selected is the one this rule
  /// exists to serve: [PaintStrokeController.commitDraft] selects the
  /// stroke it just added so the dock can restyle it immediately,
  /// without forcing the user to leave the tool armed for the next one.
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
/// body read that layer's style; with nothing selected they read the
/// session's next-stroke defaults. Before tb4 3/14 the dock only ever
/// showed session state, so selecting an old stroke and opening Color
/// showed the colour of the *next* stroke rather than the one on screen.
///
/// Writers use the same target rule ([isRestyling]): selected layer OR
/// session defaults, for any one write, so a restyle cannot leak into
/// the next authored stroke. That does not mean the two targets are
/// mutually exclusive over TIME — a tool can stay armed for continuous
/// drawing while the stroke just committed is selected for restyling,
/// and each new commit reselects to the newest stroke (see
/// [PaintStrokeController.commitDraft]). A fresh draft's own styling
/// always comes from the session defaults directly, never from this
/// view, so a stale selection mid-drag cannot leak into it either.
///
/// The layer it reads is the RENDERED one — committed document plus the
/// in-flight [LiveOverlay] — i.e. exactly what the canvas is drawing.
/// Reading the committed layer alone froze every paint consumer (strip
/// value labels and swatches, the Size hero + precision thumb, the
/// Polygon/Fill previews) at the pre-gesture value until release, while
/// the canvas underneath them already showed the preview. Writers keep
/// reading the committed document ([selectedPaintLayer]) so the staged
/// command is still built against it — preview == commit by
/// construction, and this provider stays display-only.
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

  /// Whether this view describes a bound layer (restyle) rather than
  /// the next-stroke session defaults. The one predicate every reader
  /// of "which target am I displaying" should use instead of
  /// re-deriving it — mirrors [PaintToolController.selectedPaintLayer]
  /// on the write side.
  bool get isRestyling => layerKind != null;
}

final paintStyleViewProvider = Provider<PaintStyleView>((ref) {
  final session = ref.watch(paintToolControllerProvider);
  final selection = ref.watch(selectionControllerProvider);
  // Selection wins over an armed tool — see selectedPaintLayer's doc.
  final id = selection.selectedId;
  // Contract §2: property edits stage on the live overlay and commit
  // one command on release. The dock is a consumer of that preview,
  // not of the commit, so it reads the merged view. `.select` keeps
  // the subscription pinned to the ONE layer this view describes —
  // an unrelated layer's preview must not rebuild the paint dock.
  final layer = id == null
      ? null
      : ref.watch(renderedDocumentProvider.select((doc) => doc.layerById(id)));
  if (layer is PaintLayer) {
    // Canvas dimensions are a document property no overlay can
    // express, so the reference-pixel factor stays on the committed
    // document.
    final factor = ref.watch(
      documentControllerProvider.select(CanvasSizing.scaleFactor),
    );
    return PaintStyleView(
      strokeColor: layer.strokeColor,
      strokeWidth: layer.strokeWidth,
      fillColor: layer.fillColor,
      sides: layer.sides,
      blurRadius: layer.blurSigma / factor,
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
