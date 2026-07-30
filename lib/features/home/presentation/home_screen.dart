import 'dart:async';

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
import 'widgets/resume_draft_card.dart';
import 'widgets/suggested_templates_rail.dart';
import '../../../app/theme/app_icons.dart';

/// Home root content. Composed of small, independently-tested widgets
/// and routes every editor-launching action through [HomeActions] so
/// the screen itself stays pure presentation.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// One draft-recovery offer per Home mount — re-offering on every
  /// rebuild would nag; a declined offer stays declined until the next
  /// cold start.
  bool _draftOfferShown = false;

  /// The pending draft, once the async read has resolved. Non-null is
  /// what puts [ResumeDraftCard] on screen.
  String? _pendingDraftJson;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerDraftResume());
  }

  /// True once the user has said "not now" this session. Keeps the
  /// offer down until the next cold start WITHOUT touching the
  /// journal — dismissing an offer is not the same act as deleting
  /// the work behind it.
  bool _draftOfferDismissed = false;

  Future<void> _offerDraftResume() async {
    if (_draftOfferShown || !mounted) return;
    _draftOfferShown = true;
    final draftJson = await ref
        .read(projectRecoveryServiceProvider)
        .pendingDraftJson();
    if (!mounted) return;
    // The empty case has to clear, not just return. `preserveOrphanDraft`
    // empties the slot whenever a new unsaved session starts, and the
    // card used to stay on screen holding the now-promoted JSON in
    // memory — so Resume re-opened, as a fresh unsaved session, work
    // that already existed as a project. Two copies of one drawing.
    if (draftJson == null) {
      if (_pendingDraftJson != null) {
        setState(() => _pendingDraftJson = null);
      }
      return;
    }
    if (_draftOfferDismissed) return;
    setState(() => _pendingDraftJson = draftJson);
  }

  /// "Not now" — hide the offer, keep the draft. It will be waiting
  /// at the next launch, and `preserveOrphanDraft` still promotes it
  /// to a real project if a new session claims the slot first.
  void _dismissDraftOffer() {
    _draftOfferDismissed = true;
    setState(() => _pendingDraftJson = null);
  }

  /// The only path that destroys the draft. Confirmed, because this
  /// is the single copy of work that was never saved anywhere.
  Future<void> _deleteDraft() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteDraftTitle),
        content: Text(l10n.deleteDraftBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(projectRecoveryServiceProvider).clearDraft();
    if (!mounted) return;
    setState(() => _pendingDraftJson = null);
  }

  void _resumeDraft(String draftJson) {
    setState(() => _pendingDraftJson = null);
    // Journal survives until the resumed session either saves
    // (rebinds + clears) or is deliberately closed (sessionEnding
    // flush clears) — so a crash *during* the resumed session is
    // still covered.
    HomeActions(context, ref).resumeDraft(draftJson);
  }

  @override
  Widget build(BuildContext context) {
    // Editor round-trips bump the tick (Home itself never remounts
    // inside the shell's IndexedStack) — re-arm the once-per-mount
    // guard and re-check the draft slot, so a back-out of an unsaved
    // session gets its resume offer immediately, not on next launch.
    ref.listen<int>(draftOfferTickProvider, (prev, next) {
      if (prev == next) return;
      _draftOfferShown = false;
      _offerDraftResume();
    });
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
            if (_pendingDraftJson case final String draftJson)
              SliverToBoxAdapter(
                child: ResumeDraftCard(
                  key: const ValueKey('home-resume-draft'),
                  onResume: () => _resumeDraft(draftJson),
                  onNotNow: _dismissDraftOffer,
                  onDeleteDraft: () => unawaited(_deleteDraft()),
                ),
              ),
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
                        icon: AppIcons.add,
                        filled: true,
                        onTap: actions.createNew,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: QuickActionCard(
                        key: const ValueKey('home-edit-photo'),
                        label: context.l10n.editPhotoCta,
                        icon: AppIcons.editPhoto,
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
