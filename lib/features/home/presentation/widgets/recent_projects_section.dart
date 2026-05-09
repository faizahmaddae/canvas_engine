import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../application/project_store.dart';
import '../../domain/project.dart';
import 'project_card.dart';
import 'section_header.dart';

/// Recent projects rail on Home: section header + horizontal
/// scrollable row of ~140dp cards, with empty + loading + error
/// states. Capped at [previewLimit]; full list lives behind the
/// header's "See all" affordance.
class RecentProjectsSection extends ConsumerWidget {
  const RecentProjectsSection({
    super.key,
    required this.onCreate,
    required this.onOpen,
    required this.onSeeAll,
    this.previewLimit = 8,
  });

  /// Strings extracted as constants so future Persian translation
  /// is a one-line swap, not a hunt across widgets.
  static const String titleLabel = 'Recent';
  static const String seeAllLabel = 'See all';
  static const String emptyTitle = 'Your projects appear here';
  static const String emptyBody = 'Start something new — pick a photo or a blank canvas.';
  static const String emptyCta = 'New project';
  static const String errorPrefix = 'Could not load projects: ';

  final VoidCallback onCreate;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.pageGutter,
            end: AppSpacing.pageGutter,
          ),
          child: SectionHeader(
            title: titleLabel,
            actionLabel: showSeeAll ? seeAllLabel : null,
            onAction: showSeeAll ? onSeeAll : null,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        projects.when(
          data: (list) {
            if (list.isEmpty) return _Empty(onCreate: onCreate);
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
          error: (e, _) => Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.pageGutter,
              end: AppSpacing.pageGutter,
            ),
            child: Text(
              '$errorPrefix$e',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
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
      height: 200,
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
          colors: [
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
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
  const _Empty({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.pageGutter,
        end: AppSpacing.pageGutter,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [
                    scheme.primary.withValues(alpha: 0.22),
                    scheme.tertiary.withValues(alpha: 0.18),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Icon(
                Icons.collections_bookmark_outlined,
                color: scheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    RecentProjectsSection.emptyTitle,
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.start,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    RecentProjectsSection.emptyBody,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            FilledButton.tonal(
              onPressed: onCreate,
              child: const Text(RecentProjectsSection.emptyCta),
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
          end: AppSpacing.lg,
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
