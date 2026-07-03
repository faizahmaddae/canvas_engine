import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../../../core/utils/haptics.dart';

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
  final Widget child;
  final VoidCallback onClose;

  /// Optional undo handler. When non-null an undo chip is shown in
  /// the header next to the close button — lets the user revert
  /// the last style tweak without leaving the sheet.
  final VoidCallback? onUndo;

  /// Optional horizontal-swipe handlers. When non-null, swiping
  /// LEFT on the sheet header / body routes to [onNext] and
  /// swiping RIGHT routes to [onPrev]. Lets the user move between
  /// sibling tools (e.g. Font → Color → Size) without collapsing
  /// the sheet first.
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
      if (_hDragAccum < 0 || v < 0) {
        // swiped left → next
        if (widget.onNext != null) {
          EditorHaptics.tap();
          widget.onNext!();
        }
      } else {
        // swiped right → prev
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
    final scheme = Theme.of(context).colorScheme;
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
          // Lift one tonal step above the canvas backdrop so the
          // sheet reads as a *floating* panel — not a flat strip.
          // Combined with the soft top shadow below this gives the
          // canonical "sheet just landed" event without animation.
          color: scheme.surfaceContainerHigh,
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Drag handle (swipe-down to dismiss) ─────────────
              // Slimmed 18→14dp. Pill is the *only* close affordance —
              // we removed the redundant ✕ in the header to reclaim
              // ~40dp of horizontal chrome and signal one canonical
              // dismiss gesture (swipe down OR tap the strip tile
              // again).
              Semantics(
                label: context.l10n.dismissPanelSemantics,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  onTap: () {
                    EditorHaptics.sheet();
                    widget.onClose();
                  },
                  child: SizedBox(
                    height: 14,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // ── Header ─────────────────────────────────────────
              // Compact: inline 20dp icon (no chip), tight title, undo
              // chip when applicable. The previous 32dp gradient chip
              // + ✕ stole ~25 % of the panel's vertical budget on
              // small phones; pros want density.
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 6),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
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
                        _CloseChip(onClose: widget.headerAction!),
                    ],
                  ],
                ),
              ),
              // ── Body ───────────────────────────────────────────
              // No padding here: the owning shell
              // (`EditorToolPanelShell`) is the single source of
              // truth for body padding. Adding any here would stack
              // additively with the shell's bodyPadding.
              Flexible(child: SingleChildScrollView(child: widget.child)),
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
    final scheme = Theme.of(context).colorScheme;
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
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.undo_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  context.l10n.undoTooltip,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
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

/// Neutral close affordance in the header. Renders as a tonal
/// ✕ icon button — honest semantics for panels that only
/// dismiss (no commit happens on tap). Mirrors the canonical
/// dismiss provided by drag-handle tap and swipe-down.
class _CloseChip extends StatelessWidget {
  const _CloseChip({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.closePanelSemantics,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          EditorHaptics.sheet();
          onClose();
        },
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
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
    final scheme = Theme.of(context).colorScheme;
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
            color: scheme.primary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.25),
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
              color: scheme.onPrimary,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
