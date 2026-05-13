import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/user_error.dart';
import '../../../../l10n/l10n.dart';
import '../../application/project_store.dart';
import '../../domain/project.dart';
import 'home_style.dart';
import 'project_card.dart';
import 'section_header.dart';

/// Recent projects rail on Home: section header + horizontal
/// scrollable row of ~140dp cards, with compact empty + loading +
/// error states. Home decides whether this appears near the top
/// (returning users) or near the bottom (new users with no recents).
class RecentProjectsSection extends ConsumerWidget {
  const RecentProjectsSection({
    super.key,
    required this.onCreate,
    required this.onChooseTemplate,
    required this.onOpen,
    required this.onSeeAll,
    this.previewLimit = 8,
  });

  final VoidCallback onCreate;
  final VoidCallback onChooseTemplate;
  final void Function(Project) onOpen;
  final VoidCallback onSeeAll;

  /// Maximum cards rendered in the rail. The rest are accessed via
  /// "See all" so Home stays scannable.
  final int previewLimit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectStoreProvider);
    final lastOpened = ref.watch(lastOpenedProjectIdProvider).value;
    final count = projects.value?.length ?? 0;
    final showSeeAll = count > previewLimit;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.pageGutter,
            end: AppSpacing.pageGutter,
          ),
          child: SectionHeader(
            title: l10n.recentTitle,
            actionLabel: showSeeAll ? l10n.seeAllAction : null,
            onAction: showSeeAll ? onSeeAll : null,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        projects.when(
          data: (list) {
            if (list.isEmpty) {
              return _Empty(
                onCreate: onCreate,
                onChooseTemplate: onChooseTemplate,
              );
            }
            final shown = list.length > previewLimit
                ? list.sublist(0, previewLimit)
                : list;
            return _Rail(
              projects: shown,
              lastOpenedId: lastOpened,
              onOpen: onOpen,
            );
          },
          loading: () => const _Skeleton(),
          error: (e, st) {
            debugLogError('recentProjectsSection/load', e, st);
            return Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.pageGutter,
                end: AppSpacing.pageGutter,
              ),
              child: Text(
                userMessageFor(e, fallback: l10n.couldntLoadProjects),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.projects,
    required this.lastOpenedId,
    required this.onOpen,
  });

  final List<Project> projects;
  final String? lastOpenedId;
  final void Function(Project) onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Card (140) + label rows (~44) + breathing room.
      height: 190,
      child: ShaderMask(
        // Soft trailing-edge fade so a partially-visible last card
        // reads as a scroll affordance, not a clipping bug. The
        // gradient is directional so it fades the *trailing* edge
        // under both LTR and RTL — but the shader callback runs
        // outside the widget tree, so we pass `textDirection`
        // explicitly to resolve the directional alignment.
        shaderCallback: (rect) => const LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          stops: [0.0, 0.93, 1.0],
          colors: [Colors.white, Colors.white, Colors.transparent],
        ).createShader(rect, textDirection: Directionality.of(context)),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.pageGutter,
            // Trailing pad short enough that the last card peeks
            // ~20% past the screen edge — explicit scroll hint.
            end: AppSpacing.xxl,
          ),
          itemCount: projects.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (context, i) {
            final p = projects[i];
            return ProjectCard(
              key: ValueKey(p.id),
              project: p,
              isLastOpened: p.id == lastOpenedId,
              onOpen: () => onOpen(p),
            );
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate, required this.onChooseTemplate});

  final VoidCallback onCreate;
  final VoidCallback onChooseTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.pageGutter,
        end: AppSpacing.pageGutter,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: HomePalette.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: HomePalette.hairline.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: HomePalette.shadow.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                      colors: [HomePalette.accentSoft, Color(0xFFFFF3E2)],
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.button),
                  ),
                  child: const Icon(
                    Icons.collections_bookmark_outlined,
                    color: HomePalette.accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.emptyProjectsTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: HomePalette.ink,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.start,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.emptyProjectsBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: HomePalette.muted,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                TextButton.icon(
                  onPressed: onChooseTemplate,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(l10n.homeChooseTemplateAction),
                  style: TextButton.styleFrom(
                    foregroundColor: HomePalette.accent,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                TextButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.blankCanvasCta),
                  style: TextButton.styleFrom(
                    foregroundColor: HomePalette.muted,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(
          start: AppSpacing.pageGutter,
          end: AppSpacing.xxl,
        ),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (_, _) => Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
        ),
      ),
    );
  }
}
