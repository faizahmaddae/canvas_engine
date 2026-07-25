import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/utils/haptics.dart';
import 'editor_breakpoints.dart';

/// Default fraction of screen height a panel may consume before
/// its body starts scrolling. Single source of truth — every
/// caller that does not pass [DockSheetChrome.maxHeightFraction]
/// explicitly inherits this.
///
/// Tuned to ~⅓ of the viewport so the canvas stays the protagonist
/// while a tool panel is open. Earlier 0.40 felt heavy on phones
/// (panel + dock could swallow ~50 % of the screen on shorter
/// devices, blocking the very edits the panel was meant to drive).
/// Beyond this fraction the body scrolls internally — see the
/// `Flexible` + `SingleChildScrollView` pair in `build`.
///
/// Full-screen surfaces (Crop, color picker, export sheet, font
/// browser, layers drawer) intentionally do **not** use this shell
/// — they own their own viewport.
const double kEditorPanelMaxHeightFraction = 0.34;

/// Hard dp ceiling applied on top of [kEditorPanelMaxHeightFraction].
/// Keeps the panel from eating the canvas on tablets and short
/// landscape viewports where the fraction alone would balloon.
const double kEditorPanelMaxHeightDp = 380;

/// Reusable chrome for any in-dock sheet rendered inside
/// [EditorToolDock]'s expanded slot.
///
/// **Padding contract:** this chrome adds ZERO horizontal/vertical
/// padding around [child]. The owning shell (`EditorToolPanelShell`)
/// is the single source of truth for body padding so layers do not
/// stack invisibly. Anything passed as [child] receives only the
/// internal `SingleChildScrollView`.
///
/// Premium-mobile affordances baked in:
///   * **Drag handle** at the top — visual cue + grabbable hit
///     target.
///   * **Swipe-down to dismiss** — vertical drag on the handle
///     area collapses the sheet via [onClose].
///   * Header row: inline icon + title + optional undo + close /
///     confirm chip.
///   * Body is its own scroll view, capped at
///     `min(screen * fraction, kEditorPanelMaxHeightDp)`.
class DockSheetChrome extends StatefulWidget {
  const DockSheetChrome({
    super.key,
    required this.title,
    required this.icon,
    this.headerValue,
    required this.child,
    required this.onClose,
    this.onUndo,
    this.onPrev,
    this.onNext,
    this.headerAction,
    this.confirmLabel,
    this.maxHeightFraction = kEditorPanelMaxHeightFraction,
    this.maxHeightDp = kEditorPanelMaxHeightDp,
  }) : assert(
         confirmLabel == null || headerAction != null,
         'confirmLabel requires headerAction to be set',
       );

  final String title;
  final IconData icon;

  /// Optional live value chip rendered after the title (e.g.
  /// "24px" / "80%"). Part of the unified panel-header grammar:
  /// title at the start, value + action chips at the end.
  final String? headerValue;
  final Widget child;
  final VoidCallback onClose;

  /// Optional undo handler. When non-null an undo chip is shown in
  /// the header next to the close button — lets the user revert
  /// the last style tweak without leaving the sheet.
  final VoidCallback? onUndo;

  /// Optional horizontal-swipe handlers. When non-null, swiping
  /// against the reading direction on the sheet header / body
  /// routes to [onNext] (physical LEFT under LTR, physical RIGHT
  /// under RTL) and the opposite swipe routes to [onPrev]. Lets
  /// the user move between sibling tools (e.g. Font → Color →
  /// Size) without collapsing the sheet first.
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  /// Optional thumb-reachable header action. By default this is
  /// rendered as a neutral ✕ close button — the canonical
  /// dismiss affordance for panels that do not commit on exit.
  /// Pass [confirmLabel] (e.g. `'Apply'`) to render a filled
  /// primary pill instead, for true confirm-and-commit flows.
  ///
  /// Renamed from `onDone` — the old name lied: this slot is the
  /// header action regardless of whether it closes or commits.
  final VoidCallback? headerAction;

  /// When non-null AND [headerAction] is set, the header action
  /// becomes a filled primary pill with this label (commit
  /// semantics). If null, [headerAction] renders as a neutral ✕
  /// icon (close semantics). Today no panel actually commits, so
  /// this stays null and the chrome shows an honest ✕ — but the
  /// door is open.
  final String? confirmLabel;

  /// Fraction of screen height the sheet may consume. Effective
  /// height is `min(screen.height * fraction, maxHeightDp)`. Body
  /// scrolls internally beyond that.
  final double maxHeightFraction;

  /// Hard dp ceiling. Stops the panel from eating the canvas on
  /// tablets and short landscape viewports.
  final double maxHeightDp;

  @override
  State<DockSheetChrome> createState() => _DockSheetChromeState();
}

class _DockSheetChromeState extends State<DockSheetChrome> {
  double _dragAccum = 0;
  double _hDragAccum = 0;

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.primaryDelta == null) return;
    if (d.primaryDelta! > 0) _dragAccum += d.primaryDelta!;
  }

  void _onDragEnd(DragEndDetails d) {
    final flung = d.primaryVelocity != null && d.primaryVelocity! > 380;
    if (_dragAccum > 36 || flung) {
      EditorHaptics.sheet();
      widget.onClose();
    }
    _dragAccum = 0;
  }

  void _onHDragUpdate(DragUpdateDetails d) {
    if (d.primaryDelta == null) return;
    _hDragAccum += d.primaryDelta!;
  }

  void _onHDragEnd(DragEndDetails d) {
    // Threshold: 56dp of travel OR a fling > 520px/s. Matches the
    // feel of Instagram / Canva story-style lateral swipes.
    final v = d.primaryVelocity ?? 0;
    final fling = v.abs() > 520;
    final travelled = _hDragAccum.abs() > 56;
    if (fling || travelled) {
      // "Next" follows the reading direction: under LTR the user
      // swipes the sheet LEFT (negative delta) to advance, under
      // RTL they swipe RIGHT — the physical mirror (tb1 17/17;
      // LTR pinned by dock_sheet_gestures_test, RTL by
      // rtl_strip_pins_test).
      final isRtl = Directionality.of(context) == TextDirection.rtl;
      final towardNext = isRtl
          ? (_hDragAccum > 0 || v > 0)
          : (_hDragAccum < 0 || v < 0);
      if (towardNext) {
        if (widget.onNext != null) {
          EditorHaptics.tap();
          widget.onNext!();
        }
      } else {
        if (widget.onPrev != null) {
          EditorHaptics.tap();
          widget.onPrev!();
        }
      }
    }
    _hDragAccum = 0;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final media = MediaQuery.of(context);
    // Effective max height: fraction of screen, clamped by the dp
    // ceiling so landscape phones / tablets stay sane.
    final maxHeight = (media.size.height * widget.maxHeightFraction).clamp(
      0.0,
      widget.maxHeightDp,
    );
    final hasLateral = widget.onPrev != null || widget.onNext != null;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // The panel sits on the same elevated chrome surface as
          // the dock bar (a step lighter than the workspace) so bar
          // + panel read as ONE floating chrome layer. Combined with
          // the soft top shadow below this gives the canonical
          // "sheet just landed" event without animation.
          color: tokens.surface,
          // Bottom hairline only — the panel's top edge IS the
          // dock's top edge, which already draws the sheet's 1px
          // outline; a second line here doubled it.
          border: Border(
            bottom: BorderSide(
              color: tokens.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          boxShadow: [
            // Inverted shadow that bleeds *up* over the canvas —
            // 4dp lift signals the sheet sits above the surface.
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: GestureDetector(
          // Lateral swipe anywhere on the sheet navigates to the
          // sibling tool. `behavior: deferToChild` so buttons and
          // sliders inside keep winning the gesture arena for
          // taps / vertical drags.
          behavior: HitTestBehavior.deferToChild,
          onHorizontalDragUpdate: hasLateral ? _onHDragUpdate : null,
          onHorizontalDragEnd: hasLateral ? _onHDragEnd : null,
          // Layout column + overlay hit zones (tb2 a11y pass). The
          // painted chrome is unchanged; the DISMISS gestures now
          // live on transparent overlay boxes sized to
          // [kMinHitTarget] so they meet the 44dp floor without
          // moving a single visible pixel (the flex column has no
          // vertical slack: 14dp handle + 34dp header = 48dp above
          // the body, so in-flow 44dp boxes would push the body
          // down — the byte-gated captures forbid that).
          child: Stack(
            children: [
              // ── 44dp dismiss zone (swipe-down / tap) ────────────
              // FIRST child = beneath the column, so header
              // interactives (confirm pill, undo, value chips) win
              // the hit test outright; the handle band and header
              // gaps decline hits and fall through here, giving the
              // dismiss gesture its 44dp floor without occluding a
              // single control. A tap on the empty title band
              // dismisses — deliberate, it reads as sheet chrome.
              // Horizontal drags still fall through to the outer
              // lateral detector (this zone claims vertical + tap).
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: kMinHitTarget,
                child: Semantics(
                  label: context.l10n.dismissPanelSemantics,
                  button: true,
                  child: GestureDetector(
                    key: const ValueKey('dock-sheet-handle-hit'),
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    onTap: () {
                      EditorHaptics.sheet();
                      widget.onClose();
                    },
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Drag handle (visual only — the tap/swipe zone
                  // is the 44dp under-layer). Slimmed 18→14dp; the
                  // pill signals the canonical dismiss gesture
                  // (swipe down OR tap the strip tile again).
                  // IgnorePointer: the painted pill's decoration
                  // would otherwise absorb hits aimed dead-centre at
                  // the handle and starve the dismiss zone beneath.
                  IgnorePointer(
                    child: SizedBox(
                      height: 14,
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: tokens.border.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ── Header ─────────────────────────────────────
                  // Compact: inline 20dp icon (no chip), tight title,
                  // undo chip when applicable. The previous 32dp
                  // gradient chip + ✕ stole ~25 % of the panel's
                  // vertical budget on small phones; pros want
                  // density.
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 6),
                    child: Row(
                      children: [
                        Icon(widget.icon, size: 20, color: tokens.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                          ),
                        ),
                        if (widget.headerValue != null) ...[
                          _HeaderValueChip(value: widget.headerValue!),
                          const SizedBox(width: 8),
                        ],
                        // Sibling navigation, made VISIBLE (tb7 2/7).
                        // onPrev/onNext were swipe-only: the feature
                        // existed and nothing on screen said so, which
                        // is the definition of undiscoverable. The
                        // approved prototype put ‹ › next to the ✕ in
                        // every panel that has siblings. Directional
                        // icons — Material's *_rounded chevrons carry
                        // matchTextDirection, so they mirror under RTL
                        // on their own.
                        if (widget.onPrev != null || widget.onNext != null) ...[
                          _NavChip(
                            icon: Icons.chevron_left_rounded,
                            semanticLabel: MaterialLocalizations.of(
                              context,
                            ).previousPageTooltip,
                            onTap: widget.onPrev,
                          ),
                          _NavChip(
                            icon: Icons.chevron_right_rounded,
                            semanticLabel: MaterialLocalizations.of(
                              context,
                            ).nextPageTooltip,
                            onTap: widget.onNext,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (widget.onUndo != null)
                          _UndoChip(onUndo: widget.onUndo!),
                        if (widget.headerAction != null) ...[
                          if (widget.onUndo != null) const SizedBox(width: 8),
                          if (widget.confirmLabel != null)
                            _ConfirmChip(
                              label: widget.confirmLabel!,
                              onConfirm: widget.headerAction!,
                            )
                          else
                            // Visual only — its 44dp tap overlay is
                            // stacked above (bottom of this Stack's
                            // child list = top of the hit order).
                            const _CloseChipVisual(),
                        ],
                      ],
                    ),
                  ),
                  // ── Body ───────────────────────────────────────
                  // No padding here: the owning shell
                  // (`EditorToolPanelShell`) is the single source of
                  // truth for body padding. Adding any here would
                  // stack additively with the shell's bodyPadding.
                  Flexible(child: SingleChildScrollView(child: widget.child)),
                ],
              ),
              // ── 44dp close hit box over the painted ✕ chip ──────
              // Geometry derives from the header constants: the
              // painted 28dp chip sits 12dp from the end and centred
              // at y=28 (14dp handle + 28dp row / 2), so the 44dp
              // box is inset (28−22)=6 from the top and
              // (12+14−22)=4 from the end. Undo/confirm chips keep
              // their inline 28dp hit — they have no production
              // consumer today (both call sites pass null) and their
              // width is content-dependent, which a fixed overlay
              // cannot cover; revive them through this overlay
              // pattern when a consumer lands.
              if (widget.headerAction != null && widget.confirmLabel == null)
                PositionedDirectional(
                  top: 6,
                  end: 4,
                  width: kMinHitTarget,
                  height: kMinHitTarget,
                  child: Semantics(
                    label: context.l10n.closePanelSemantics,
                    button: true,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const ValueKey('dock-sheet-close-hit'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          EditorHaptics.sheet();
                          widget.headerAction!();
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header undo affordance. Tap = single undo; long-press peeks at
/// the prior state and snaps back on release.
class _UndoChip extends StatelessWidget {
  const _UndoChip({required this.onUndo});

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      label: context.l10n.undoLastChangeSemantics,
      button: true,
      child: GestureDetector(
        // Long-press collapses to a single undo (same as tap).
        // The previous design fired undo on both start and end to
        // simulate a peek/snap-back, but no redo path is wired so it
        // silently consumed two history entries — high data-loss
        // risk on the most prominent destructive control.
        onLongPressStart: (_) {
          EditorHaptics.toggle();
          onUndo();
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            EditorHaptics.tap();
            onUndo();
          },
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surfaceMuted.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.undo_rounded, size: 14, color: tokens.textSecondary),
                const SizedBox(width: 4),
                Text(
                  context.l10n.undoTooltip,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Neutral close affordance in the header — the PAINTED 28dp tonal
/// ✕ chip only. Honest semantics for panels that only dismiss (no
/// commit happens on tap). Interaction (tap + semantics) lives on
/// the 44dp overlay hit box in [DockSheetChrome]'s Stack so the hit
/// area meets [kMinHitTarget] without growing the header row.
class _CloseChipVisual extends StatelessWidget {
  const _CloseChipVisual();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.close_rounded, size: 16, color: tokens.textSecondary),
    );
  }
}

/// True confirm-and-commit affordance. Filled primary so it reads
/// as the primary action of the sheet. Only rendered when the
/// caller passes `confirmLabel` to [DockSheetChrome] — today no
/// editor panel commits on close, but the path is reserved for
/// future flows (apply effect, finish crop, etc.).
class _ConfirmChip extends StatelessWidget {
  const _ConfirmChip({required this.label, required this.onConfirm});

  final String label;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          EditorHaptics.confirm();
          onConfirm();
        },
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.brand,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: tokens.brand.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tokens.onBrand,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small live-value chip in the sheet header — the unified panel
/// grammar's end-of-header readout ("24px", "80%", "Off"). Same
/// visual vocabulary as the LayoutSliderCard value pill so header
/// and body readouts read as one family. Non-interactive.
class _HeaderValueChip extends StatelessWidget {
  const _HeaderValueChip({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A small ‹ / › sibling-navigation button in the panel header.
///
/// Deliberately sized NOT to grow the header: the dense header is the
/// point of the prototype's layout, and the 44dp chrome floor is
/// specified for primary dismiss/commit affordances (see
/// `chrome_hit_targets_test`) — these are secondary accelerators for a
/// gesture that still works. `InkResponse.radius` gives the finger a
/// circular target wider than the painted glyph.
class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkResponse(
        onTap: onTap == null
            ? null
            : () {
                EditorHaptics.tap();
                onTap!();
              },
        radius: 22,
        child: SizedBox(
          width: 30,
          height: 28,
          child: Icon(
            icon,
            size: 24,
            color: onTap == null
                ? tokens.textMuted.withValues(alpha: 0.4)
                : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
