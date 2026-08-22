import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/app_modal_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/project.dart';
import 'project_thumb.dart';
import 'relative_time.dart';

/// What the draft overflow sheet resolved to. `null` (swipe-down,
/// barrier tap, back) means the offer stands untouched — neither
/// dismissing the card nor destroying the draft is something a stray
/// tap should be able to do.
enum _DraftMenuAction { notNow, delete }

/// The top of the desk: whatever the user touched last, rendered big
/// enough to recognise and one tap from reopening.
///
/// Two things can occupy the slot, and they never appear together —
/// the slot always holds the *most recent* act:
///
///   * [ContinueCard.draft] — a crashed/abandoned unsaved session from
///     the recovery journal. Successor to `ResumeDraftCard`, keeping
///     its exact action weights: Resume is the filled button, «نه حالا»
///     hides behind «⋯», and delete — the only path that destroys the
///     single copy of unsaved work — sits one level deeper still and
///     is confirmed by the caller.
///   * [ContinueCard.project] — the newest saved project, with its
///     name and relative last-modified time. The rail below skips it
///     so the same design never appears twice on one screen.
///
/// The old offer was a 68dp one-liner that *told* the user a draft
/// existed; this shows the work itself — a live document preview at
/// the canvas's true aspect ratio. Recognition beats description on a
/// screen visited every day.
class ContinueCard extends StatelessWidget {
  const ContinueCard.draft({
    super.key,
    required String this.draftJson,
    this.draftName,
    required VoidCallback this.onResume,
    required VoidCallback this.onNotNow,
    required VoidCallback this.onDeleteDraft,
  }) : project = null,
       onOpen = null;

  const ContinueCard.project({
    super.key,
    required Project this.project,
    required VoidCallback this.onOpen,
  }) : draftJson = null,
       draftName = null,
       onResume = null,
       onNotNow = null,
       onDeleteDraft = null;

  /// Serialized document from the draft journal (draft mode only).
  final String? draftJson;

  /// The draft's recorded display name. Null when the journal predates
  /// the name sidecar or the write lost its race with the crash, in
  /// which case the generic recovered-draft name stands in — the card
  /// must never render a blank title.
  final String? draftName;

  final VoidCallback? onResume;
  final VoidCallback? onNotNow;
  final VoidCallback? onDeleteDraft;

  /// The newest saved project (project mode only).
  final Project? project;
  final VoidCallback? onOpen;

  bool get _isDraft => draftJson != null;

  /// Preview pane height. The card's overall height follows this —
  /// tall enough that a design is recognisable at arm's length, short
  /// enough that the create row stays above the fold.
  static const double _previewHeight = 132;

  /// Honest-ratio bounds for the preview pane: a 9:16 story still
  /// reads tall and a 16:9 thumbnail still reads wide, but neither
  /// extreme may starve the title column of its minimum width.
  static const double _minRatio = 0.62;
  static const double _maxRatio = 1.5;

  /// Widest the pane may go as a share of the card's inner width. On a
  /// 320dp screen a square canvas at full [_previewHeight] would eat
  /// half the card and push the resume button out the far edge; past
  /// this cap the pane letterboxes a little instead. At today's normal
  /// widths (≥390dp) the cap never engages for portrait/square work.
  static const double _maxWidthFraction = 0.42;

  /// Canvas aspect ratio (w/h) for the preview pane, from the mode's
  /// own source of truth. Draft JSON that cannot be read falls back to
  /// square — the preview widget itself will render the corrupt-JSON
  /// icon, and a square pane is the neutral frame for it.
  double get _ratio {
    if (!_isDraft) return project!.width / project!.height;
    try {
      final doc = jsonDecode(draftJson!);
      if (doc is Map<String, dynamic>) {
        final w = (doc['width'] as num?)?.toDouble();
        final h = (doc['height'] as num?)?.toDouble();
        if (w != null && h != null && w > 0 && h > 0) return w / h;
      }
    } on FormatException {
      // Fall through to square.
    }
    return 1;
  }

  Future<void> _showDraftMenu(BuildContext context) async {
    final l10n = context.l10n;
    // Same host and same grammar as the project card's menu on the
    // Projects tab: a list sheet has nothing to preview behind it, so
    // the barrier is `full` per interaction contract §9.
    final action = await showAppSheet<_DraftMenuAction>(
      context,
      title: draftName ?? l10n.recoveredDraftName,
      titleIcon: AppIcons.resumeDraft,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('resume-draft-not-now'),
            leading: const Icon(AppIcons.close),
            title: Text(l10n.notNowAction),
            onTap: () => Navigator.pop(ctx, _DraftMenuAction.notNow),
          ),
          ListTile(
            key: const ValueKey('resume-draft-delete'),
            leading: Icon(
              AppIcons.delete,
              color: Theme.of(ctx).colorScheme.error,
            ),
            title: Text(
              l10n.deleteDraftAction,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
            onTap: () => Navigator.pop(ctx, _DraftMenuAction.delete),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
    switch (action) {
      case null:
        return;
      case _DraftMenuAction.notNow:
        onNotNow!();
      case _DraftMenuAction.delete:
        onDeleteDraft!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final title = _isDraft
        ? (draftName ?? l10n.recoveredDraftName)
        : project!.name;
    final subtitle = _isDraft
        ? l10n.unsavedBadge
        : relativeTime(l10n, project!.lastModified);
    final open = _isDraft ? onResume! : onOpen!;
    final ratioWidth =
        _previewHeight * _ratio.clamp(_minRatio, _maxRatio).toDouble();

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.pageGutter,
        0,
        AppSpacing.pageGutter,
        AppSpacing.md,
      ),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: tokens.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final previewWidth = ratioWidth
                      .clamp(0.0, constraints.maxWidth * _maxWidthFraction)
                      .toDouble();
                  return Row(
                    children: [
                      Container(
                        key: const ValueKey('continue-preview'),
                        width: previewWidth,
                        height: _previewHeight,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: tokens.surfaceMuted,
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          border: Border.all(color: tokens.border),
                        ),
                        child: _isDraft
                            ? DocumentJsonPreview(
                                documentJson: draftJson!,
                                name: title,
                              )
                            : ProjectPreview(project: project!),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.homeContinueTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypeScale.caption.copyWith(
                                fontSize: 11,
                                color: tokens.accentText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypeScale.body.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypeScale.caption.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                // Flexible so a tight column (narrow
                                // screen × wide type) squeezes the
                                // button's label before anything can
                                // overflow the card edge.
                                Flexible(
                                  child: _ContinueButton(
                                    key: _isDraft
                                        ? const ValueKey('resume-draft-resume')
                                        : const ValueKey('home-continue-open'),
                                    label: l10n.resumeAction,
                                    onPressed: open,
                                  ),
                                ),
                                if (_isDraft) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  IconButton(
                                    key: const ValueKey(
                                      'resume-draft-overflow',
                                    ),
                                    iconSize: 18,
                                    // Explicit box, not `VisualDensity.compact`:
                                    // compact trims 8dp off both axes and lands
                                    // the trigger under the 44dp touch floor
                                    // the rest of the app holds.
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    tooltip: l10n.moreTooltip,
                                    color: tokens.textSecondary,
                                    icon: const Icon(AppIcons.moreActions),
                                    onPressed: () => _showDraftMenu(context),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one action carrying weight. Kept local rather than reaching for
/// `AppPrimaryButton`, which is a full-width page CTA — this one has to
/// shrink-wrap its label so the title above it keeps the column width.
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      color: tokens.brand,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.button),
        // `Align` with both factors set (rather than a `Container` with
        // an `alignment`, which expands to fill whatever it is given)
        // so the button shrink-wraps its label.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 76),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.onBrand,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
