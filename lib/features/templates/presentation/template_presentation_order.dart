import '../domain/template.dart';

const List<TemplateCategory> kTemplateBrowseCategoryOrder = [
  TemplateCategory.instagramStory,
  TemplateCategory.social,
  TemplateCategory.story,
  TemplateCategory.sale,
  TemplateCategory.promotionalPoster,
  TemplateCategory.business,
  TemplateCategory.food,
  TemplateCategory.event,
  TemplateCategory.poetryPost,
  TemplateCategory.quote,
  TemplateCategory.youtubeThumbnail,
  TemplateCategory.greeting,
  TemplateCategory.motivational,
];

const List<String> kHomeRecommendedTemplateIds = [
  'fa_story_fashion_drop',
  'fa_promo_app_launch',
  'fa_poetry_black_gold_nastaliq',
  'en_yt_tutorial_blueprint',
  'fa_story_product_reveal',
  'fa_sale_luxury_drop',
  'fa_edu_webinar_story',
  'fa_food_modern_menu_board',
  'fa_post_product_carousel_cover',
  'fa_business_service_launch_story',
  'en_social_business_announcement',
  'en_yt_podcast_interview',
  'fa_insta_story_v1',
  'fa_promo_v1',
  'fa_poetry_overlay_v1',
  'en_yt_thumb_v1',
];

const List<String> kHomeStoryTemplateIds = [
  'fa_story_fashion_drop',
  'fa_story_beauty_booking',
  'fa_story_health_clinic_tip',
  'fa_story_product_reveal',
  'fa_story_daily_offer',
  'fa_story_cafe_mood',
  'fa_story_course_signup',
  'fa_insta_story_v1',
];

const List<String> kHomeTextTemplateIds = [
  'fa_post_personal_brand_quote',
  'fa_quote_editorial_magazine',
  'fa_quote_literary_column',
  'fa_quote_modern_dark',
  'en_quote_editorial_gradient',
  'fa_quote_minimal',
  'en_quote_editorial',
  'en_quote_minimal',
];

const List<String> kHomeAdvertisingTemplateIds = [
  'fa_promo_app_launch',
  'fa_sale_retail_clearance',
  'fa_promo_travel_tour',
  'fa_sale_luxury_drop',
  'fa_sale_beauty_package',
  'fa_promo_clinic_checkup',
  'fa_promo_restaurant_special',
  'fa_promo_course_launch',
  'fa_promo_v1',
];

const List<String> kHomeYoutubeTemplateIds = [
  'en_yt_tutorial_blueprint',
  'en_yt_podcast_interview',
  'en_yt_reaction_hot_take',
  'en_yt_explainer_framework',
  'en_yt_before_after_design',
  'en_yt_ai_tools_2026',
  'en_yt_thumb_v1',
];

const List<String> kHomePoetryTemplateIds = [
  'fa_poetry_black_gold_nastaliq',
  'fa_poetry_photo_frame_premium',
  'fa_poetry_nastaliq_evening',
  'fa_poetry_gallery_card',
  'fa_poetry_overlay_v1',
  'fa_poetry_minimal_v1',
  'fa_poetry_v1',
];

const List<String> _browseFeaturedTemplateIds = [
  ...kHomeRecommendedTemplateIds,
  ...kHomeStoryTemplateIds,
  ...kHomeTextTemplateIds,
  ...kHomeAdvertisingTemplateIds,
  ...kHomeYoutubeTemplateIds,
  ...kHomePoetryTemplateIds,
  'fa_business_recruitment_story',
  'fa_business_agency_intro',
  'fa_business_service_offer',
  'fa_food_delivery_story',
  'fa_cafe_breakfast_special',
  'fa_post_service_announcement',
  'fa_event_workshop_announcement',
  'en_social_launch_checklist',
  'en_social_case_study',
  'en_business_product_update',
  'en_event_startup_pitch',
  'en_webinar_growth_masterclass',
];

const Set<String> _productQualityBatch3Ids = {
  'fa_story_fashion_drop',
  'fa_story_beauty_booking',
  'fa_story_health_clinic_tip',
  'fa_post_product_carousel_cover',
  'fa_post_service_announcement',
  'fa_post_personal_brand_quote',
  'fa_sale_retail_clearance',
  'fa_promo_clinic_checkup',
  'fa_promo_travel_tour',
  'fa_sale_beauty_package',
  'fa_promo_app_launch',
  'fa_poetry_black_gold_nastaliq',
  'fa_quote_editorial_magazine',
  'fa_poetry_photo_frame_premium',
  'fa_quote_literary_column',
  'fa_event_gallery_opening',
  'fa_business_service_launch_story',
  'fa_event_workshop_announcement',
  'en_yt_tutorial_blueprint',
  'en_yt_reaction_hot_take',
  'en_yt_podcast_interview',
  'en_social_business_announcement',
};

const Set<String> _productQualityBatch2Ids = {
  'fa_business_recruitment_story',
  'fa_business_agency_intro',
  'fa_business_service_offer',
  'fa_business_job_fair',
  'fa_business_team_hiring',
  'fa_business_consulting_post',
  'fa_food_modern_menu_board',
  'fa_food_delivery_story',
  'fa_cafe_breakfast_special',
  'fa_restaurant_live_night',
  'fa_food_dessert_launch',
  'fa_edu_webinar_story',
  'fa_edu_workshop_poster',
  'fa_edu_exam_prep_post',
  'fa_edu_course_tip_carousel',
  'fa_season_nowruz_greeting',
  'fa_season_iftar_invite',
  'fa_cultural_book_night',
  'en_business_product_update',
  'en_webinar_growth_masterclass',
  'en_event_startup_pitch',
  'en_social_case_study',
  'en_yt_explainer_framework',
};

const Set<String> _productQualityBatch1Ids = {
  'fa_story_product_reveal',
  'fa_story_daily_offer',
  'fa_story_cafe_mood',
  'fa_story_course_signup',
  'fa_post_brand_intro',
  'fa_post_minimal_tip',
  'fa_post_event_countdown',
  'fa_post_culture_seasonal',
  'fa_sale_luxury_drop',
  'fa_sale_market_weekend',
  'fa_promo_restaurant_special',
  'fa_promo_course_launch',
  'fa_poetry_nastaliq_evening',
  'fa_quote_modern_dark',
  'fa_poetry_gallery_card',
  'en_yt_ai_tools_2026',
  'en_yt_before_after_design',
  'en_social_launch_checklist',
};

List<Template> orderTemplatesForHome({
  required List<Template> templates,
  Iterable<String> preferredIds = const [],
  Iterable<TemplateCategory> categoryPriority = const [],
}) {
  return _orderedTemplates(
    templates: templates,
    preferredIds: preferredIds,
    categoryPriority: categoryPriority,
  );
}

List<Template> orderTemplatesForBrowse({
  required List<Template> templates,
  TemplateLanguage? preferredLanguage,
  TemplateCategory? selectedCategory,
}) {
  return _orderedTemplates(
    templates: templates,
    preferredLanguage: preferredLanguage,
    preferredIds: _preferredIdsForCategory(selectedCategory),
    categoryPriority: selectedCategory == null
        ? kTemplateBrowseCategoryOrder
        : const [],
  );
}

List<TemplateCategory> orderedTemplateCategories(
  Iterable<Template> templates, {
  TemplateCategory? selected,
}) {
  final present = <TemplateCategory>{
    for (final template in templates) template.category,
    ?selected,
  };
  return [
    for (final category in kTemplateBrowseCategoryOrder)
      if (present.contains(category)) category,
    for (final category in TemplateCategory.values)
      if (present.contains(category) &&
          !kTemplateBrowseCategoryOrder.contains(category))
        category,
  ];
}

List<Template> _orderedTemplates({
  required List<Template> templates,
  TemplateLanguage? preferredLanguage,
  Iterable<String> preferredIds = const [],
  Iterable<TemplateCategory> categoryPriority = const [],
}) {
  final sourceIndexById = <String, int>{
    for (var index = 0; index < templates.length; index++)
      templates[index].id: index,
  };
  final preferredRank = <String, int>{};
  for (final entry in preferredIds.indexed) {
    preferredRank.putIfAbsent(entry.$2, () => entry.$1);
  }
  final categoryRank = <TemplateCategory, int>{
    for (final entry in categoryPriority.indexed) entry.$2: entry.$1,
  };

  final ordered = [...templates]
    ..sort((a, b) {
      final languageCompare = _languageRank(
        a,
        preferredLanguage,
      ).compareTo(_languageRank(b, preferredLanguage));
      if (languageCompare != 0) return languageCompare;

      final preferredCompare = _preferredRank(
        a,
        preferredRank,
      ).compareTo(_preferredRank(b, preferredRank));
      if (preferredCompare != 0) return preferredCompare;

      final qualityCompare = _qualityRank(a).compareTo(_qualityRank(b));
      if (qualityCompare != 0) return qualityCompare;

      final categoryCompare = _categoryRank(
        a,
        categoryRank,
      ).compareTo(_categoryRank(b, categoryRank));
      if (categoryCompare != 0) return categoryCompare;

      return (sourceIndexById[a.id] ?? 0).compareTo(sourceIndexById[b.id] ?? 0);
    });
  return List.unmodifiable(ordered);
}

Iterable<String> _preferredIdsForCategory(TemplateCategory? category) {
  return switch (category) {
    TemplateCategory.instagramStory => kHomeStoryTemplateIds,
    TemplateCategory.quote => kHomeTextTemplateIds,
    TemplateCategory.promotionalPoster ||
    TemplateCategory.sale => kHomeAdvertisingTemplateIds,
    TemplateCategory.youtubeThumbnail => kHomeYoutubeTemplateIds,
    TemplateCategory.poetryPost => kHomePoetryTemplateIds,
    _ => _browseFeaturedTemplateIds,
  };
}

int _languageRank(Template template, TemplateLanguage? preferredLanguage) {
  if (preferredLanguage == null) return 0;
  return template.language == preferredLanguage ? 0 : 1;
}

int _preferredRank(Template template, Map<String, int> preferredRank) {
  return preferredRank[template.id] ?? preferredRank.length + 1;
}

int _qualityRank(Template template) {
  if (_productQualityBatch3Ids.contains(template.id)) return 0;
  if (_productQualityBatch2Ids.contains(template.id)) return 1;
  if (_productQualityBatch1Ids.contains(template.id)) return 2;
  return 3;
}

int _categoryRank(Template template, Map<TemplateCategory, int> categoryRank) {
  return categoryRank[template.category] ?? categoryRank.length + 1;
}
