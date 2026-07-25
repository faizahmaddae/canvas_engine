import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/l10n.dart';

/// The "you have an unsaved design" offer, shown at the top of Home
/// when the recovery journal still holds a draft.
///
/// This used to be a raw Material `MaterialBanner`, which failed on
/// two counts: it painted default Material chrome into a screen whose
/// entire visual identity is the paper/ink/saffron token set, and its
/// `OverflowBar` pushed the primary action off the left edge under
/// RTL — a Persian user saw «ادام» and could not read, let alone
/// trust, the button they were being asked to press.
///
/// The replacement is a plain card on the page's own gutter: it can't
/// clip (both actions are laid out by a `Wrap` that falls to a second
/// line before it overflows), it reads as part of Home rather than as
/// system chrome, and it costs ~half the vertical space the banner did
/// so the launcher underneath stays where the user expects it.
class ResumeDraftCard extends StatelessWidget {
  const ResumeDraftCard({
    super.key,
    required this.onResume,
    required this.onDiscard,
  });

  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;

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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: tokens.brandSoft,
                    borderRadius: BorderRadius.circular(AppRadii.button),
                  ),
                  child: Icon(
                    Icons.restore_rounded,
                    size: 18,
                    color: tokens.accentDeep,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.resumeDraftBanner,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // `Wrap` rather than `Row`: Persian labels run longer than
            // their English counterparts and the narrowest supported
            // width is ~320dp, so the pair has to be able to stack
            // instead of clipping the way the banner did.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _DraftAction(
                  key: const ValueKey('resume-draft-discard'),
                  label: l10n.discardAction,
                  onPressed: onDiscard,
                  filled: false,
                ),
                _DraftAction(
                  key: const ValueKey('resume-draft-resume'),
                  label: l10n.resumeAction,
                  onPressed: onResume,
                  filled: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftAction extends StatelessWidget {
  const _DraftAction({
    super.key,
    required this.label,
    required this.onPressed,
    required this.filled,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      color: filled ? tokens.brand : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.button),
        // `Align` with both factors set (rather than a `Container` with
        // an `alignment`, which expands to fill whatever it is given)
        // so each action shrink-wraps its label and the pair shares one
        // line instead of each claiming a full run of the `Wrap`.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 88),
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
                  color: filled ? tokens.onBrand : tokens.accentDeep,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
