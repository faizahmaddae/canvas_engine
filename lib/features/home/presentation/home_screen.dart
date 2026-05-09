import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import 'home_actions.dart';
import 'widgets/home_header.dart';
import 'widgets/primary_actions.dart';
import 'widgets/recent_projects_section.dart';
import 'widgets/templates_section.dart';

/// Home tab content. Composed of small, independently-tested
/// widgets and routes every editor-launching action through
/// [HomeActions] so the screen itself stays pure presentation.
///
/// The shell ([RootShell]) owns the bottom navigation; this screen
/// is just one of its tabs and does not render its own scaffold
/// chrome beyond the scrolling content.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = HomeActions(context, ref);

    return CustomScrollView(
      // Bouncing for that tactile feel on scroll-back from the
      // bottom of long template lists.
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: HomeHeader()),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        SliverToBoxAdapter(
          child: PrimaryActions(
            onEditPhoto: actions.importPhoto,
            onBlankCanvas: actions.createNew,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
          child: RecentProjectsSection(
            onCreate: actions.createNew,
            onOpen: actions.openProject,
            onSeeAll: actions.openRecentAll,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
          child: TemplatesSection(onOpen: actions.openTemplate),
        ),
        // Bottom inset so the last category row clears the
        // navigation bar comfortably.
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }
}
