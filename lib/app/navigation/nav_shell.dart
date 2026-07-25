import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/presentation/home_actions.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/widgets/recent_projects_grid.dart';
import '../../features/templates/presentation/templates_browse_screen.dart';
import '../../l10n/l10n.dart';
import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';
import '../ui/bottom_tab_bar.dart';
import '../theme/app_icons.dart';

/// Active tab of the root [NavShell]. A provider (not local state)
/// so launcher rails can jump to a tab — Home's «مشاهده همه» links
/// set this instead of pushing duplicate routes on the stack.
final navShellIndexProvider = NotifierProvider<NavShellIndexController, int>(
  NavShellIndexController.new,
);

class NavShellIndexController extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

/// Root navigation (app-navigation doc): a bottom tab bar with
/// خانه · قالب‌ها · پروژه‌ها. Home stays a short launcher; content
/// growth lives in the dedicated browser tabs. Settings remains the
/// Home header icon — it's a utility, not a destination.
///
/// Tabs live in an [IndexedStack] so each keeps its scroll position
/// and filter state across switches — but they build LAZILY: a tab
/// mounts on its first visit, not at app launch. Home shouldn't pay
/// the browser tabs' load cost (template repository, project-store
/// file IO) before the user ever opens them.
class NavShell extends ConsumerStatefulWidget {
  const NavShell({super.key});

  @override
  ConsumerState<NavShell> createState() => _NavShellState();
}

class _NavShellState extends ConsumerState<NavShell> {
  final Set<int> _visited = {0};

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navShellIndexProvider);
    _visited.add(index);
    final l10n = context.l10n;
    Widget tab(int i, Widget Function() builder) =>
        _visited.contains(i) ? builder() : const SizedBox.shrink();
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          tab(0, () => const HomeScreen()),
          tab(1, () => const _TemplatesTab()),
          tab(2, () => const _ProjectsTab()),
        ],
      ),
      bottomNavigationBar: BottomTabBar(
        currentIndex: index,
        onSelect: (value) =>
            ref.read(navShellIndexProvider.notifier).select(value),
        items: [
          BottomTabItem(
            icon: AppIcons.homeTab,
            activeIcon: AppIcons.homeTab,
            label: l10n.navHomeTab,
          ),
          BottomTabItem(
            icon: AppIcons.templatesTab,
            activeIcon: AppIcons.gridView,
            label: l10n.templatesTitle,
          ),
          BottomTabItem(
            icon: AppIcons.projectsTab,
            activeIcon: AppIcons.projectsTab,
            label: l10n.navProjectsTab,
          ),
        ],
      ),
    );
  }
}

/// Templates tab — the existing browse screen mounted as a tab
/// (restyled to v2 in its own commit). Editor-opening flows through
/// [HomeActions] so navigation logic stays in one place.
class _TemplatesTab extends ConsumerWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = HomeActions(context, ref);
    return TemplatesBrowseScreen(onOpen: actions.openTemplate);
  }
}

/// Projects tab — the existing full grid mounted as a tab (restyled
/// to v2 in its own commit).
class _ProjectsTab extends ConsumerWidget {
  const _ProjectsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = HomeActions(context, ref);
    final tokens = AppTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.pageBg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.pageGutter,
            AppSpacing.lg,
            AppSpacing.pageGutter,
            AppSpacing.xl,
          ),
          child: RecentProjectsGrid(
            onCreate: actions.createNew,
            onOpen: actions.openProject,
          ),
        ),
      ),
    );
  }
}
