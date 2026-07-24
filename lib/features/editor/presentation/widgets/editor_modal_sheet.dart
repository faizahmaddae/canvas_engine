import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// Barrier policy for [showEditorSheet] (interaction contract §9).
///
/// | value    | scrim | use                                            |
/// |----------|-------|------------------------------------------------|
/// | none     | 0%    | surface live-previews the canvas (paint size,  |
/// |          |       | colour picker) — dimming would contradict the  |
/// |          |       | preview                                        |
/// | whisper  | 6%    | keep context visible (font browser, composer)  |
/// | full     | default scrim | list/overflow sheets, pickers, export  |
enum EditorSheetBarrier { none, whisper, full }

/// Whisper scrim opacity — light enough that live canvas previews
/// stay legible behind the sheet, present enough to signal a modal.
const double kEditorSheetWhisperAlpha = 0.06;

/// Height of the drag-handle dismiss zone at the top of every
/// editor sheet. ≥44dp per the chrome hit floor (tb2 14/16,
/// 0563102): the painted 36×4 pill is purely visual; this whole
/// band is tappable (dismiss) and draggable (the modal route's own
/// swipe-down).
const double kEditorSheetHandleZoneHeight = 44.0;

/// THE single modal-sheet host for the editor (tb2 8/16, contract
/// §1-M): one chrome grammar — floating card (radius 24, 12dp
/// gutter), a 36×4 handle inside a ≥44dp dismiss zone, an optional
/// title row — plus the §9 three-value [EditorSheetBarrier] policy
/// and keyboard awareness for text-entry content.
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
Future<T?> showEditorSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  EditorSheetBarrier barrier = EditorSheetBarrier.full,
  String? title,
  IconData? titleIcon,
  double? maxHeightFraction,
  // Material 3's modal-sheet width ceiling. Surfaces wanting a
  // tighter column (the font browser's 520) pass it explicitly.
  double maxWidth = 640,
  bool keyboardAware = false,
}) {
  final Color? barrierColor = switch (barrier) {
    EditorSheetBarrier.none => Colors.transparent,
    EditorSheetBarrier.whisper => Theme.of(
      context,
    ).colorScheme.scrim.withValues(alpha: kEditorSheetWhisperAlpha),
    // null → the framework's default scrim.
    EditorSheetBarrier.full => null,
  };
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    builder: (sheetCtx) => _EditorSheetCard(
      title: title,
      titleIcon: titleIcon,
      maxHeightFraction: maxHeightFraction,
      maxWidth: maxWidth,
      keyboardAware: keyboardAware,
      child: Builder(builder: builder),
    ),
  );
}

class _EditorSheetCard extends StatelessWidget {
  const _EditorSheetCard({
    required this.title,
    required this.titleIcon,
    required this.maxHeightFraction,
    required this.maxWidth,
    required this.keyboardAware,
    required this.child,
  });

  final String? title;
  final IconData? titleIcon;
  final double? maxHeightFraction;
  final double maxWidth;
  final bool keyboardAware;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final media = MediaQuery.of(context);

    Widget card = Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
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
            height: kEditorSheetHandleZoneHeight,
            child: Semantics(
              key: const ValueKey('editor-sheet-handle-zone'),
              button: true,
              label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
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
              IgnorePointer(
                child: SizedBox(
                  height: 14,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: tokens.border.withValues(alpha: 0.8),
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
              Flexible(child: child),
            ],
          ),
        ],
      ),
    );

    card = Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeightFraction == null
              ? double.infinity
              : media.size.height * maxHeightFraction!,
        ),
        child: card,
      ),
    );

    if (keyboardAware) {
      // Keep text-entry content above the keyboard. viewInsets, not
      // viewPadding: the route's useSafeArea already handles the
      // static system chrome.
      card = Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: card,
      );
    }
    return card;
  }
}
