import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';

/// Two equally-weighted primary CTAs at the top of Home.
///
/// "Edit a photo" is the bold, saturated brand-gradient hero —
/// it's the most attention-grabbing element on the page and sets
/// the visual hierarchy. "Blank canvas" is a clear secondary
/// action: an outlined surface tile with a thick primary-coloured
/// border and primary-tinted icon + label so it reads as
/// *outlined and inviting*, not as a disabled state.
class PrimaryActions extends StatelessWidget {
  const PrimaryActions({
    super.key,
    required this.onEditPhoto,
    required this.onBlankCanvas,
  });

  static const String editTitle = 'Edit a photo';
  static const String editSubtitle = 'From your gallery';
  static const String blankTitle = 'Blank canvas';
  static const String blankSubtitle = 'Custom size';

  final VoidCallback onEditPhoto;
  final VoidCallback onBlankCanvas;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.pageGutter,
        end: AppSpacing.pageGutter,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _GradientHeroCta(
                title: editTitle,
                subtitle: editSubtitle,
                icon: Icons.photo_library_rounded,
                onTap: onEditPhoto,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _OutlinedHeroCta(
                title: blankTitle,
                subtitle: blankSubtitle,
                icon: Icons.add_rounded,
                onTap: onBlankCanvas,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bold brand-gradient hero. Vivid violet → magenta with a
/// 1dp lighter top edge for a subtle "lit from above" depth cue
/// and a primary-tinted shadow so it lifts off the dark surface.
class _GradientHeroCta extends StatelessWidget {
  const _GradientHeroCta({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  // Vivid, saturated brand gradient — explicit hex so the hero
  // looks consistent regardless of the seeded ColorScheme drift.
  // The end stop is a slightly muted magenta so the hero stays
  // commanding without out-shouting the colourful Recent rail.
  static const Color _violet = Color(0xFF7C5CFF);
  static const Color _magenta = Color(0xFFC44BC0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const fg = Colors.white;

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.hero),
            gradient: const LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [_violet, _magenta],
            ),
            // 1dp lighter top edge for a touch of dimensional depth.
            border: const Border(
              top: BorderSide(color: Color(0x33FFFFFF), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: _violet.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.hero),
            onTap: onTap,
            // Make the ripple distinctly visible against the bright
            // gradient — pure-white at low alpha reads cleanly.
            splashColor: fg.withValues(alpha: 0.20),
            highlightColor: fg.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(AppRadii.button),
                    ),
                    child: const Icon(
                      Icons.photo_library_rounded,
                      color: fg,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fg.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The outlined secondary CTA. Surface-container fill, 2dp primary
/// border, primary-tinted icon and label — clearly "secondary" but
/// unmistakably actionable, never ghosted.
class _OutlinedHeroCta extends StatelessWidget {
  const _OutlinedHeroCta({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.primary;

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.hero),
            border: Border.all(color: accent, width: 2),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.hero),
            onTap: onTap,
            splashColor: accent.withValues(alpha: 0.18),
            highlightColor: accent.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadii.button),
                    ),
                    child: Icon(icon, color: accent, size: 32),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
