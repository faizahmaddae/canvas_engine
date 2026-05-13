import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import '../application/project_store.dart';
import '../../settings/application/settings_controller.dart';
import '../../templates/application/template_repository_provider.dart';
import '../../templates/domain/template.dart';
import 'home_actions.dart';
import 'widgets/hero_start_card.dart';
import 'widgets/home_header.dart';
import 'widgets/home_style.dart';
import 'widgets/primary_actions.dart';
import 'widgets/recent_projects_section.dart';
import 'widgets/template_language_filter.dart';
import 'widgets/templates_section.dart';

/// Home root content. Composed of small, independently-tested widgets
/// and routes every editor-launching action through [HomeActions] so
/// the screen itself stays pure presentation.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  HomeTemplateLanguageFilter _templateLanguageFilter =
      HomeTemplateLanguageFilter.all;

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
    final showBottomRecent =
        !hasRecentProjects &&
        (recentProjects.hasValue || recentProjects.hasError);
    final effectiveLanguages = _effectiveLanguages(
      _templateLanguageFilter,
      contentLanguages,
    );

    return Scaffold(
      backgroundColor: HomePalette.backgroundBottom,
      body: SafeArea(
        bottom: false,
        child: HomeBackground(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: HomeHeader()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              SliverToBoxAdapter(
                child: HeroStartCard(
                  templates: templates,
                  onChooseTemplate: () => actions.openTemplates(
                    initialLanguage: _initialBrowseLanguage(effectiveLanguages),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              SliverToBoxAdapter(
                child: PrimaryActions(
                  onEditPhoto: actions.importPhoto,
                  onBlankCanvas: actions.createNew,
                  onNewProject: actions.createNew,
                  onTextOnPhoto: () => _openTemplateById(
                    actions,
                    templates,
                    'fa_poetry_overlay_v1',
                  ),
                ),
              ),
              if (hasRecentProjects) ...[
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.lg),
                ),
                SliverToBoxAdapter(
                  child: RecentProjectsSection(
                    onCreate: actions.createNew,
                    onChooseTemplate: () => actions.openTemplates(
                      initialLanguage: _initialBrowseLanguage(
                        effectiveLanguages,
                      ),
                    ),
                    onOpen: actions.openProject,
                    onSeeAll: actions.openRecentAll,
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              SliverToBoxAdapter(
                child: TemplatesSection(
                  onOpen: actions.openTemplate,
                  templates: templates,
                  contentLanguages: contentLanguages,
                  enabledCategories: enabledCategories,
                  languageFilter: _templateLanguageFilter,
                  filter: TemplateLanguageFilter(
                    selected: _templateLanguageFilter,
                    onChanged: (value) =>
                        setState(() => _templateLanguageFilter = value),
                  ),
                ),
              ),
              if (showBottomRecent) ...[
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.lg),
                ),
                SliverToBoxAdapter(
                  child: RecentProjectsSection(
                    onCreate: actions.createNew,
                    onChooseTemplate: () => actions.openTemplates(
                      initialLanguage: _initialBrowseLanguage(
                        effectiveLanguages,
                      ),
                    ),
                    onOpen: actions.openProject,
                    onSeeAll: actions.openRecentAll,
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
            ],
          ),
        ),
      ),
    );
  }
}

void _openTemplateById(
  HomeActions actions,
  List<Template> templates,
  String id,
) {
  for (final template in templates) {
    if (template.id == id) {
      actions.openTemplate(template);
      return;
    }
  }
  actions.openTemplates(initialCategory: TemplateCategory.poetryPost);
}

Set<TemplateLanguage> _effectiveLanguages(
  HomeTemplateLanguageFilter filter,
  Set<TemplateLanguage> contentLanguages,
) => switch (filter) {
  HomeTemplateLanguageFilter.all => contentLanguages,
  HomeTemplateLanguageFilter.persian => {TemplateLanguage.persian},
  HomeTemplateLanguageFilter.english => {TemplateLanguage.english},
  HomeTemplateLanguageFilter.mixed => {
    TemplateLanguage.english,
    TemplateLanguage.persian,
  },
};

TemplateLanguage _initialBrowseLanguage(Set<TemplateLanguage> languages) {
  if (languages.contains(TemplateLanguage.persian)) {
    return TemplateLanguage.persian;
  }
  return TemplateLanguage.english;
}
