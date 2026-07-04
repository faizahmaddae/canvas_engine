import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/warm_palette.dart';
import '../../../../l10n/l10n.dart';

/// Compact quick actions for starting from the most common paths.
/// The heavy brand moment lives in [HeroStartCard]; these tiles stay
/// quieter so Home reads like a creative workspace instead of a wall
/// of competing CTAs.
class PrimaryActions extends StatelessWidget {
  const PrimaryActions({
    super.key,
    required this.onEditPhoto,
    required this.onBlankCanvas,
    required this.onNewProject,
    required this.onTextOnPhoto,
  });

  final VoidCallback onEditPhoto;
  final VoidCallback onBlankCanvas;
  final VoidCallback onNewProject;
  final VoidCallback onTextOnPhoto;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = WarmPalette.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.pageGutter,
        end: AppSpacing.pageGutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.homeQuickActionsTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
              final actions = [
                _QuickActionData(
                  title: l10n.blankCanvasCta,
                  subtitle: l10n.blankCanvasSubtitle,
                  icon: Icons.add_rounded,
                  accent: palette.accent,
                  onTap: onBlankCanvas,
                ),
                _QuickActionData(
                  title: l10n.editPhotoCta,
                  subtitle: l10n.editPhotoSubtitle,
                  icon: Icons.photo_library_rounded,
                  accent: palette.rose,
                  onTap: onEditPhoto,
                ),
                _QuickActionData(
                  title: l10n.homeTextOnPhotoCta,
                  subtitle: l10n.homeTextOnPhotoSubtitle,
                  icon: Icons.text_fields_rounded,
                  accent: palette.saffron,
                  onTap: onTextOnPhoto,
                ),
                _QuickActionData(
                  title: l10n.emptyProjectsCta,
                  subtitle: l10n.pickCanvasSizeBody,
                  icon: Icons.dashboard_customize_rounded,
                  accent: palette.accentPressed,
                  onTap: onNewProject,
                ),
              ];
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: tileWidth,
                      child: _QuickActionCard(action: action),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
}

class _QuickActionCard extends StatefulWidget {
  const _QuickActionCard({required this.action});

  final _QuickActionData action;

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = WarmPalette.of(context);
    final action = widget.action;
    return Semantics(
      button: true,
      label: '${action.title}. ${action.subtitle}',
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Ink(
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(
                color: palette.hairline.withValues(alpha: 0.72),
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.card),
              onTap: action.onTap,
              onHighlightChanged: (pressed) =>
                  setState(() => _pressed = pressed),
              splashColor: action.accent.withValues(alpha: 0.08),
              highlightColor: action.accent.withValues(alpha: 0.05),
              child: SizedBox(
                height: 74,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: action.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadii.button),
                        ),
                        child: Icon(
                          action.icon,
                          color: action.accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          action.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: palette.ink,
                            fontWeight: FontWeight.w900,
                            height: 1.18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
