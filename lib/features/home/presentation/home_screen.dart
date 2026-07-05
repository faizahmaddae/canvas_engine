import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/navigation/nav_shell.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../editor/application/project_recovery_service.dart';
import '../application/project_store.dart';
import '../../settings/application/settings_controller.dart';
import '../../templates/application/template_repository_provider.dart';
import 'home_actions.dart';
import 'widgets/home_header.dart';
import 'widgets/quick_action_card.dart';
import 'widgets/recent_projects_section.dart';
import 'widgets/suggested_templates_rail.dart';

/// Home root content. Composed of small, independently-tested widgets
/// and routes every editor-launching action through [HomeActions] so
/// the screen itself stays pure presentation.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// One draft-recovery offer per Home mount — re-showing the banner
  /// on every rebuild would nag; a declined offer stays declined
  /// until the next cold start.
  bool _draftOfferShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerDraftResume());
  }

  Future<void> _offerDraftResume() async {
    if (_draftOfferShown || !mounted) return;
    _draftOfferShown = true;
    final draftJson = await ref
        .read(projectRecoveryServiceProvider)
        .pendingDraftJson();
    if (draftJson == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final recovery = ref.read(projectRecoveryServiceProvider);
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(context.l10n.resumeDraftBanner),
        leading: const Icon(Icons.restore_rounded),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              recovery.clearDraft();
            },
            child: Text(context.l10n.discardAction),
          ),
          FilledButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              // Journal survives until the resumed session either
              // saves (rebinds + clears) or is deliberately closed
              // (sessionEnding flush clears) — so a crash *during*
              // the resumed session is still covered.
              HomeActions(context, ref).resumeDraft(draftJson);
            },
            child: Text(context.l10n.resumeAction),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = HomeActions(context, ref);
    final templates = ref.watch(
      effectiveTemplatesProvider(Localizations.localeOf(context).languageCode),
    );
    final contentLanguages = ref.watch(contentLanguagesProvider);
    final enabledCategories = ref.watch(enabledCategoriesProvider);
    final recentProjects = ref.watch(projectStoreProvider);
    final hasRecentProjects = recentProjects.value?.isNotEmpty ?? false;

    return Scaffold(
      backgroundColor: AppTokens.of(context).pageBg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: HomeHeader()),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
            // Create row (redesign doc §3): two equal cards, the
            // filled ink card is THE primary action.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.pageGutter,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: QuickActionCard(
                        key: const ValueKey('home-create-new'),
                        label: context.l10n.blankCanvasCta,
                        icon: Icons.add_rounded,
                        filled: true,
                        onTap: actions.createNew,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: QuickActionCard(
                        key: const ValueKey('home-edit-photo'),
                        label: context.l10n.editPhotoCta,
                        icon: Icons.photo_outlined,
                        onTap: actions.importPhoto,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasRecentProjects) ...[
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              SliverToBoxAdapter(
                child: RecentProjectsSection(
                  onCreate: actions.createNew,
                  onOpen: actions.openProject,
                  // Launcher rails jump to their tab instead of
                  // pushing duplicate routes (navigation doc).
                  onSeeAll: () =>
                      ref.read(navShellIndexProvider.notifier).select(2),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
            SliverToBoxAdapter(
              child: SuggestedTemplatesRail(
                onOpen: actions.openTemplate,
                onSeeAll: () =>
                    ref.read(navShellIndexProvider.notifier).select(1),
                templates: templates,
                contentLanguages: contentLanguages,
                enabledCategories: enabledCategories,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }
}
