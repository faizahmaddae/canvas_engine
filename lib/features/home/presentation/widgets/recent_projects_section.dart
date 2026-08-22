import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/thumb_ratio.dart';
import '../../../../core/utils/user_error.dart';
import '../../../../l10n/l10n.dart';
import '../../application/project_store.dart';
import '../../domain/project.dart';
import 'project_thumb.dart';

/// Recent work on Home: «کارهای اخیر» + a horizontal rail of
/// [ProjectThumb]s.
///
/// The rail is the desk's second row — the continue hero above it
/// already shows the newest project at recognisable size, so with
/// [skipNewest] the rail starts from the second-newest and the same
/// design never appears twice on one screen. The dashed «جدید» tile
/// died with the hero's arrival: it duplicated the create row sitting
/// 150dp above it, and its prime start-edge slot belongs to actual
/// work.
///
/// When there is nothing to show — fresh user, store still loading,
/// hero already holding the only project, or a load error — the
/// section renders NOTHING. No empty rail, no skeleton: Home stays
/// calm and the templates below carry the screen (errors are logged,
/// never displayed here).
class RecentProjectsSection extends ConsumerWidget {
  const RecentProjectsSection({
    super.key,
    required this.onOpen,
    required this.onSeeAll,
    this.skipNewest = false,
    this.previewLimit = 8,
  });

  final void Function(Project) onOpen;
  final VoidCallback onSeeAll;

  /// True when the continue hero above the rail is already showing the
  /// newest project, which the rail must then not repeat.
  final bool skipNewest;

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
    final rest = skipNewest && list.isNotEmpty ? list.sublist(1) : list;
    if (rest.isEmpty) return const SizedBox.shrink();

    final shown = rest.length > previewLimit
        ? rest.sublist(0, previewLimit)
        : rest;
    final showSeeAll = rest.length > previewLimit;

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
                    foregroundColor: tokens.accentText,
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
          // Thumb (140) + gap (4) + caption line + slack. The caption
          // line scales with the user's text-size setting, so the
          // strip height has to as well — pinned at 168 it sheared the
          // descenders off «پروژه» at Large and overflowed at Largest.
          // Capped at 1.6 so an extreme setting stretches the rail
          // instead of eating the whole screen.
          height:
              144 +
              21 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.pageGutter,
            ),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final project = shown[index];
              // Honest ratio: the tile is the canvas's own shape, so a
              // square project reads square instead of floating in the
              // letterbox bands of a one-size portrait card.
              return ProjectThumb(
                key: ValueKey('home-recent-${project.id}'),
                project: project,
                width: thumbWidthFor(
                  height: 140,
                  ratio: project.width / project.height,
                ),
                onTap: () => onOpen(project),
              );
            },
          ),
        ),
      ],
    );
  }
}
