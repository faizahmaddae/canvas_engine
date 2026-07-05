import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/user_error.dart';
import '../../../../l10n/l10n.dart';
import '../../application/project_store.dart';
import '../../domain/project.dart';
import 'project_thumb.dart';

/// Recent work on Home, v2 (home redesign doc §4): «کارهای اخیر» +
/// a horizontal rail of [ProjectThumb]s ending in the dashed «جدید»
/// tile.
///
/// When there is nothing to show — fresh user, store still loading,
/// or a load error — the section renders NOTHING. No empty rail, no
/// skeleton: Home stays calm and the templates below carry the
/// screen (errors are logged, never displayed here).
class RecentProjectsSection extends ConsumerWidget {
  const RecentProjectsSection({
    super.key,
    required this.onCreate,
    required this.onOpen,
    required this.onSeeAll,
    this.previewLimit = 8,
  });

  final VoidCallback onCreate;
  final void Function(Project) onOpen;
  final VoidCallback onSeeAll;

  /// Maximum thumbs rendered in the rail. The rest are accessed via
  /// «مشاهده همه» so Home stays scannable.
  final int previewLimit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectStoreProvider);
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);

    if (projects.hasError) {
      debugLogError(
        'recentProjectsSection/load',
        projects.error ?? 'unknown error',
        projects.stackTrace,
      );
    }
    final list = projects.value ?? const <Project>[];
    if (list.isEmpty) return const SizedBox.shrink();

    final shown = list.length > previewLimit
        ? list.sublist(0, previewLimit)
        : list;
    final showSeeAll = list.length > previewLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.pageGutter,
            end: AppSpacing.pageGutter,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.recentTitle,
                  style: AppTypeScale.title.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showSeeAll)
                TextButton(
                  key: const ValueKey('home-recent-see-all'),
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.accent,
                    textStyle: AppTypeScale.caption.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(l10n.seeAllAction),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          // Thumb (140) + gap (4) + caption line (~21) + slack.
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.pageGutter,
            ),
            itemCount: shown.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              if (index == shown.length) {
                return NewProjectTile(
                  key: const ValueKey('home-recent-new-tile'),
                  label: l10n.homeRecentNewTile,
                  onTap: onCreate,
                );
              }
              final project = shown[index];
              return ProjectThumb(
                key: ValueKey('home-recent-${project.id}'),
                project: project,
                onTap: () => onOpen(project),
              );
            },
          ),
        ),
      ],
    );
  }
}
