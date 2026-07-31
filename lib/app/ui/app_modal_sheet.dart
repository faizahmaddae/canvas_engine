import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';

/// Barrier policy for [showAppSheet] (interaction contract §9).
///
/// | value    | scrim | use                                            |
/// |----------|-------|------------------------------------------------|
/// | none     | 0%    | surface live-previews the canvas (paint size,  |
/// |          |       | colour picker) — dimming would contradict the  |
/// |          |       | preview                                        |
/// | whisper  | 6%    | keep context visible (font browser, composer)  |
/// | full     | default scrim | list/overflow sheets, pickers, export  |
enum AppSheetBarrier { none, whisper, full }

/// Whisper scrim opacity — light enough that live canvas previews
/// stay legible behind the sheet, present enough to signal a modal.
const double kAppSheetWhisperAlpha = 0.06;

/// Height of the drag-handle dismiss zone at the top of every
/// app sheet. ≥44dp per the chrome hit floor (tb2 14/16,
/// 0563102): the painted 36×4 pill is purely visual; this whole
/// band is tappable (dismiss) and draggable (the modal route's own
/// swipe-down).
const double kAppSheetHandleZoneHeight = 44.0;

/// THE single modal-sheet host for the whole app (tb2 8/16, contract
/// §1-M): one chrome grammar — a sheet ANCHORED to the bottom edge
/// (full width, rounded top corners only), a 36×4 handle inside a
/// ≥44dp dismiss zone, an optional title row — plus the §9
/// three-value [AppSheetBarrier] policy and keyboard awareness for
/// text-entry content.
///
/// Anchored, not floating. The host used to render a card inset by a
/// 12dp gutter on both sides and 12dp from the bottom, ON TOP of the
/// route's `useSafeArea`, so on a device with a home indicator the
/// sheet sat ~46dp clear of the bottom edge with workspace visible
/// down both flanks. At sheet sizes that reads as a dialogue; at the
/// sizes this app actually uses it did not — the sticker and shape
/// pickers are 85% of the screen, and a near-full-height slab
/// floating in a gutter is neither a sheet nor a page. It also made
/// the open animation read badly: a detached card flying up past its
/// own shadow, rather than a surface rising from the edge it is
/// attached to.
///
/// So: no side gutters, no bottom gap, square bottom corners, and the
/// surface paints THROUGH the bottom safe area while content stays
/// padded clear of the home indicator. `maxWidth` still applies, so
/// on a tablet the sheet is a centred column — the one case where
/// side gutters are correct, because there the sheet really is a
/// dialogue.
///
/// Content contract: [builder]'s widget owns its OWN scrolling
/// (the scroll-guard pattern from 8a612ec) — the host never wraps
/// content in a scroll view, because several bodies are all-drag
/// surfaces (colour wheel) that must not live inside one. The
/// route always bounds the card to the available height;
/// [maxHeightFraction] caps it lower.
///
/// Dismiss semantics are the modal route's own: swipe-down, barrier
/// tap and system back all pop with `null`; content pops with a
/// value. The host adds tap-on-handle as an explicit dismiss.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  AppSheetBarrier barrier = AppSheetBarrier.full,
  String? title,
  IconData? titleIcon,
  double? maxHeightFraction,
  // Material 3's modal-sheet width ceiling. Surfaces wanting a
  // tighter column (the font browser's 520) pass it explicitly.
  double maxWidth = 640,
  bool keyboardAware = false,
}) {
  final Color? barrierColor = switch (barrier) {
    AppSheetBarrier.none => Colors.transparent,
    AppSheetBarrier.whisper => Theme.of(
      context,
    ).colorScheme.scrim.withValues(alpha: kAppSheetWhisperAlpha),
    // null → the framework's default scrim.
    AppSheetBarrier.full => null,
  };
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // FALSE deliberately: `useSafeArea` insets the whole route, which
    // is what lifted the sheet off the bottom edge. The card caps its
    // own height against the top inset instead, and pads its content
    // clear of the home indicator from the inside — so the surface
    // reaches the edge and the content still never sits under system
    // chrome.
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    builder: (sheetCtx) => _AppSheetCard(
      title: title,
      titleIcon: titleIcon,
      maxHeightFraction: maxHeightFraction,
      maxWidth: maxWidth,
      keyboardAware: keyboardAware,
      // Captured OUT here, where it still exists. `ModalBottomSheetRoute`
      // applies `MediaQuery.removePadding(removeTop: true)` to its child
      // unconditionally — not as part of `useSafeArea` — so inside the
      // builder both `padding.top` and `viewPadding.top` read 0 and a
      // cap computed in there silently lets a full-height sheet run up
      // under the notch.
      topInset: MediaQuery.of(context).padding.top,
      child: Builder(builder: builder),
    ),
  );
}

class _AppSheetCard extends StatelessWidget {
  const _AppSheetCard({
    required this.title,
    required this.titleIcon,
    required this.maxHeightFraction,
    required this.maxWidth,
    required this.keyboardAware,
    required this.topInset,
    required this.child,
  });

  final String? title;
  final IconData? titleIcon;
  final double? maxHeightFraction;
  final double maxWidth;
  final bool keyboardAware;

  /// Top system inset, read outside the route (see the call site).
  final double topInset;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final media = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // When the keyboard is up it covers the home indicator, so the
    // sheet rides the keyboard instead and owes the inset nothing.
    final keyboard = media.viewInsets.bottom;
    final safeBottom = keyboard > 0 ? 0.0 : media.padding.bottom;

    Widget card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheetTop),
        ),
        boxShadow: [
          // Cast UPWARD only. The old (0, 8) shadow fell downward into
          // the gutter this sheet no longer has, which is nowhere —
          // the sheet's bottom edge is the screen's. What has to read
          // as lifted is its top edge against the canvas.
          //
          // Theme-driven and mode-tuned, matching the dock. A
          // hardcoded `Colors.black @ 0.10` is both a tokens-rule
          // violation and useless in dark mode: black over the dark
          // workspace measured 1.07:1, against a sheet surface that is
          // itself only 1.05:1 against that workspace — so with
          // `barrier: none` the sheet had no discernible top edge at
          // all.
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.shadow.withValues(alpha: isDark ? 0.44 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      // A transparent Material under the content, the same way the
      // tool dock does it. The card is a bare DecoratedBox, so any
      // Material widget placed in a sheet body — a ListTile, an
      // InkWell — had no Material ancestor to paint its ink on and
      // rendered its splashes invisibly (Flutter asserts on exactly
      // this in debug). Bodies that bring their own Material are
      // unaffected; this only supplies one where there was none.
      child: Material(
        color: Colors.transparent,
        // The 44dp dismiss zone UNDERLAYS the chrome (0563102's dock
        // pattern): interactive content wins its own hits; the pill is
        // IgnorePointer'd and empty strip space falls through to the
        // zone, so a tap aimed anywhere at the handle band dismisses.
        child: Stack(
          children: [
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              height: kAppSheetHandleZoneHeight,
              child: Semantics(
                key: const ValueKey('app-sheet-handle-zone'),
                button: true,
                label: MaterialLocalizations.of(
                  context,
                ).modalBarrierDismissLabel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A hairline the shadow cannot substitute for. In dark
                // mode `surface` sits 1.05:1 against the workspace, so
                // on a `barrier: none` sheet the top edge needs a line,
                // not just a glow — the dock reaches for the same token
                // one pixel below.
                Container(height: 1, color: tokens.border),
                IgnorePointer(
                  child: SizedBox(
                    height: 13,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          // Was `border @ 0.8`: measured 1.25:1 light
                          // and 1.14:1 dark against `surface` — the one
                          // affordance saying "drag me down", and the
                          // faintest thing on the sheet. `textSecondary`
                          // is the mid-tone that survives both ends of
                          // the ramp (the colour swatches make the same
                          // call), and 0.70 is the lowest alpha that
                          // clears the 3:1 non-text floor in BOTH
                          // themes: 3.03:1 light, 3.96:1 dark.
                          color: tokens.textSecondary.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 6),
                    child: Row(
                      children: [
                        if (titleIcon != null) ...[
                          Icon(titleIcon, size: 18, color: tokens.accent),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            title!,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                // The safe-area inset lives HERE, not around the card:
                // the surface has to paint through to the screen edge
                // while the content it holds clears the home indicator.
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: safeBottom),
                    child: child,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // Cap against the TOP inset, which is the job `useSafeArea` used
    // to do for us: a sheet may fill the screen but must never slide
    // under the status bar or the notch. [topInset], not
    // `media.padding.top` — the latter is zero in here.
    final ceiling = media.size.height - topInset;
    card = Align(
      alignment: Alignment.bottomCenter,
      // Size to the CHILD's height, do not expand to fill. Flutter's
      // `BottomSheet` divides drag distance by its child's height to
      // decide a dismiss, so an Align that stretched to the full
      // screen made a 234dp sheet demand ~478dp of downward drag —
      // i.e. drag-to-dismiss was unreachable on every short sheet.
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeightFraction == null
              ? ceiling
              : (media.size.height * maxHeightFraction!).clamp(0.0, ceiling),
        ),
        child: card,
      ),
    );

    if (keyboardAware) {
      // Keep text-entry content above the keyboard: the sheet's bottom
      // edge sits ON the keyboard rather than under it.
      card = Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: card,
      );
    }
    return card;
  }
}
