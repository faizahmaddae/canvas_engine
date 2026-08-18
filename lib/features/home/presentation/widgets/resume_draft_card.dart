import 'package:flutter/material.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/ui/app_modal_sheet.dart';
import '../../../../l10n/l10n.dart';

/// What the overflow sheet resolved to. `null` (swipe-down, barrier
/// tap, back) means the offer stands untouched — neither dismissing
/// the card nor destroying the draft is something a stray tap should
/// be able to do.
enum _DraftMenuAction { notNow, delete }

/// The "you have an unsaved design" offer, shown at the top of Home
/// when the recovery journal still holds a draft.
///
/// Two earlier shapes failed here. A raw `MaterialBanner` painted
/// framework chrome into a paper/ink/saffron screen and let its
/// `OverflowBar` push the primary action off the leading edge under
/// RTL — a Persian user saw «ادام» and could not read, let alone
/// trust, the button they were being asked to press. The card that
/// replaced it fixed the clipping and demoted the destructive action,
/// but it spent three stacked rows (message, safe pair, delete) doing
/// it: ~185dp of a launcher whose whole invariant is that its height
/// does not grow with content, for an offer most launches dismiss.
///
/// This is one row, ~68dp. The gain comes from saying less and
/// showing more: the draft's own name replaces the sentence that
/// described it, so the offer answers "resume WHAT?" instead of
/// announcing that something exists.
///
/// The three paths survive the compression, with their weights
/// further apart than before rather than closer:
///
///   * [onResume] is the filled button — the only action with weight.
///   * [onNotNow] hides the offer and keeps the draft. It is not a
///     peer of Resume; it lives behind «⋯».
///   * [onDeleteDraft] is the only path that destroys anything, now
///     one level deeper than it used to be and still confirmed by its
///     caller. It used to sit beside Resume as a peer and clear the
///     journal on a single tap — the only copy of that work, with no
///     dialog, while deleting an already-SAVED project required one.
class ResumeDraftCard extends StatelessWidget {
  const ResumeDraftCard({
    super.key,
    required this.onResume,
    required this.onNotNow,
    required this.onDeleteDraft,
    this.draftName,
  });

  final VoidCallback onResume;
  final VoidCallback onNotNow;
  final VoidCallback onDeleteDraft;

  /// The draft's recorded display name. Null when the journal predates
  /// the name sidecar or the write lost its race with the crash, in
  /// which case the generic recovered-draft name stands in — the row
  /// must never render a blank title.
  final String? draftName;

  Future<void> _showMenu(BuildContext context) async {
    final l10n = context.l10n;
    // Same host and same grammar as the project card's menu two
    // sliders down this screen: a list sheet has nothing to preview
    // behind it, so the barrier is `full` per interaction contract §9.
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
        onNotNow();
      case _DraftMenuAction.delete:
        onDeleteDraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.pageGutter,
        0,
        AppSpacing.pageGutter,
        AppSpacing.md,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: tokens.border),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tokens.brandSoft,
                borderRadius: BorderRadius.circular(AppRadii.button),
              ),
              child: Icon(
                AppIcons.resumeDraft,
                size: 18,
                color: tokens.accentText,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // The title has to be free to shrink: Persian project names
            // run long, and the two trailing controls are fixed-width.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    draftName ?? l10n.recoveredDraftName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    l10n.unsavedBadge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ResumeButton(
              key: const ValueKey('resume-draft-resume'),
              label: l10n.resumeAction,
              onPressed: onResume,
            ),
            IconButton(
              key: const ValueKey('resume-draft-overflow'),
              iconSize: 18,
              // Explicit box, not `VisualDensity.compact`: compact
              // trims 8dp off both axes and lands the menu trigger at
              // 40dp, under the touch floor the rest of the app holds.
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: l10n.moreTooltip,
              color: tokens.textSecondary,
              icon: const Icon(AppIcons.moreActions),
              onPressed: () => _showMenu(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one action carrying weight. Kept local rather than reaching for
/// `AppPrimaryButton`, which is a full-width page CTA — this one has to
/// shrink-wrap its label so the title beside it keeps the remaining
/// width.
class _ResumeButton extends StatelessWidget {
  const _ResumeButton({
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
