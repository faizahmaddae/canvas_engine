import 'package:flutter/material.dart';

import 'dock_sheet_chrome.dart';

/// Default body padding applied by [EditorToolPanelShell].
///
/// The chrome itself contributes ZERO padding around the body,
/// so this is the *only* gutter the child receives. The remaining
/// (un-consumed) bottom safe-area inset is added on top of
/// `bottom` automatically.
///
/// Top is `12` (not `4`) so the first content row never kisses
/// the fixed header — when the body scrolls, content starts with
/// visible breathing room instead of sliding flush against the
/// title bar.
///
/// Bottom is `24` (not `12`) so the last content row scrolls
/// fully clear of the chip-strip's top border underneath the
/// panel. Without this the final row reads as “tucked behind”
/// the dock when scrolled to the end.
const EdgeInsets kEditorPanelDefaultBodyPadding = EdgeInsets.fromLTRB(
  12,
  12,
  12,
  24,
);

/// Body padding used by [SubToolSheet] (Text / Paint sub-tools).
///
/// Wider horizontal gutters (20 vs 12) because Text/Paint sub-tools
/// are dominated by full-width sliders — the extra side margin
/// improves thumb reach on the slider track edges and gives the
/// label-row breathing room. Vertical values mirror the default
/// rhythm (`12` top / `24` bottom + a touch extra) so the floating
/// mode-exit pill above the panel and the chip strip below both
/// have visible clearance from the scrolling content.
const EdgeInsets kEditorSubToolBodyPadding = EdgeInsets.fromLTRB(
  20,
  14,
  20,
  28,
);

/// Unified shell for every sub-tool panel rendered inside the
/// editor's bottom dock (`EditorToolDock`'s `expanded` slot).
///
/// Single source of truth for panel chrome across **every** editor
/// mode — Text, Paint, Image, Shape, Canvas, Sticker. Wraps the
/// lower-level [DockSheetChrome] so the chrome stays one-step
/// removed and any future polish (animation curves, shadows,
/// header rhythm) lands in exactly one place.
///
/// **Full-screen exception**
/// - Tools that need to own the entire viewport (status bar +
///   canvas region + their own bottom bar) skip this shell
///   entirely. The canonical example is `CropModeOverlay` — it is
///   not a bottom panel, it is a full-screen mode. Do not fork
///   chrome for that case; render full-screen above the editor
///   and own its own dismiss controls.
///
/// **Padding contract**
/// - This shell owns all body padding. [DockSheetChrome] adds
///   none. [bodyPadding] **replaces** the default — it is not
///   additive — so callers always see the exact gutter they ask
///   for. The bottom safe-area inset is added on top so the last
///   control never sits under the home indicator.
///
/// **Header action contract**
/// - By default no chip is rendered: drag-handle tap and swipe-
///   down on the handle dismiss via [onClose] (canonical).
/// - Pass [showCloseAction] = true to render a neutral ✕ icon in
///   the header for users who prefer a tap target. It calls
///   [onClose] — same destination as the drag handle.
/// - Pass [confirmLabel] + [onConfirm] to render a filled primary
///   pill for true commit-and-exit semantics. Reserved for future
///   flows; today no panel commits.
class EditorToolPanelShell extends StatelessWidget {
  const EditorToolPanelShell({
    super.key,
    required this.title,
    required this.icon,
    required this.onClose,
    required this.child,
    this.onUndo,
    this.onPrev,
    this.onNext,
    this.onConfirm,
    this.confirmLabel,
    this.showCloseAction = true,
    this.maxHeightFraction = kEditorPanelMaxHeightFraction,
    this.maxHeightDp = kEditorPanelMaxHeightDp,
    this.bodyPadding,
    this.maxBodyWidth,
  }) : assert(
         (onConfirm == null) == (confirmLabel == null),
         'onConfirm and confirmLabel must be supplied together',
       );

  final String title;
  final IconData icon;

  /// Called when the user dismisses the panel (drag-handle tap,
  /// swipe-down on the handle, or the header ✕ when shown).
  /// Should resolve to the owning controller's `closePanel()` /
  /// `closeSlot()` so selection + canvas state stay untouched
  /// while the panel collapses.
  final VoidCallback onClose;

  final Widget child;

  /// Optional undo handler. When non-null an undo chip is shown in
  /// the header with long-press peek behaviour (handled by chrome).
  final VoidCallback? onUndo;

  /// Optional sibling-swipe handlers. Wiring these in enables
  /// horizontal-drag navigation between sibling tools.
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  /// True commit-and-exit handler. When supplied alongside
  /// [confirmLabel], a filled primary pill is rendered in the
  /// header. Use only when tapping really commits state (e.g.
  /// "Apply effect"). Otherwise leave null and rely on
  /// [showCloseAction].
  final VoidCallback? onConfirm;

  /// Label for the confirm pill (e.g. `'Apply'`). Required when
  /// [onConfirm] is supplied; otherwise ignored.
  final String? confirmLabel;

  /// Whether to render the neutral ✕ close icon in the header.
  /// Defaults to true because users on small phones expect a
  /// tap target near their thumb. Set false when the host owns
  /// a separate floating exit affordance (Text/Paint mode pill).
  final bool showCloseAction;

  /// Fraction of screen height the panel may consume. Defaults to
  /// [kEditorPanelMaxHeightFraction]. Effective height is clamped
  /// by [maxHeightDp] — see [DockSheetChrome] for details.
  final double maxHeightFraction;

  /// Hard dp ceiling for panel height. Defaults to
  /// [kEditorPanelMaxHeightDp]. Stops landscape phones / tablets
  /// from getting an oversized panel.
  final double maxHeightDp;

  /// Replacement (not additive) for the default body padding.
  /// Defaults to [kEditorPanelDefaultBodyPadding]. Bottom safe-
  /// area inset is added on top automatically.
  final EdgeInsets? bodyPadding;

  /// Optional max width for the body content. When set, the body
  /// is centred and constrained — use for grid-style panels
  /// (sticker picker) so they read on tablets without stretching.
  final double? maxBodyWidth;

  @override
  Widget build(BuildContext context) {
    // Use `paddingOf` (not `viewPaddingOf`): the dock wraps the
    // panel in `SafeArea(top: false)`, which already reserves the
    // home-indicator height as physical space below the panel. We
    // only need to top-up the body if an *outer* SafeArea is
    // missing — `paddingOf` reflects what's still un-consumed,
    // `viewPaddingOf` does not. Using `viewPaddingOf` here added
    // ~34 dp of phantom bottom padding on iPhones and pushed the
    // last scrollable row past the visible viewport edge.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final pad = bodyPadding ?? kEditorPanelDefaultBodyPadding;
    Widget body = Padding(
      padding: pad.copyWith(bottom: pad.bottom + bottomInset),
      child: child,
    );
    if (maxBodyWidth != null) {
      body = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxBodyWidth!),
          child: body,
        ),
      );
    }
    return DockSheetChrome(
      title: title,
      icon: icon,
      maxHeightFraction: maxHeightFraction,
      maxHeightDp: maxHeightDp,
      onClose: onClose,
      onUndo: onUndo,
      onPrev: onPrev,
      onNext: onNext,
      // Resolve the header action: confirm pill > close icon > none.
      headerAction: onConfirm ?? (showCloseAction ? onClose : null),
      confirmLabel: onConfirm != null ? confirmLabel : null,
      child: body,
    );
  }
}
