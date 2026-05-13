# Template Product Quality Plan

This plan pauses TemplateCatalog cleanup and focuses only on the visible template product: design quality, quantity, category coverage, Persian differentiation, English variety, and thumbnail strength.

## Current Product Audit

Before Batch 1 the app had 53 JSON templates: 29 Persian and 24 English. Technically, those templates were valid and the previous quality audit marked them Ready, but the catalog still felt too small for a real design app.

Current weaknesses from a user/product perspective:

- The catalog does not yet feel abundant. A user can scan the whole library too quickly.
- Persian quality is better than the original migration state, but still not strong enough to be the app's unique product advantage.
- Many templates are single-purpose starters rather than a broad set of visually distinct, ready-to-customize designs.
- Home/Browse thumbnails are readable, but the overall shelf still lacks enough color, layout, and use-case variety.
- Instagram post coverage is thin because the current category enum uses broad buckets like `social`, `story`, and `instagramStory` rather than a dedicated Instagram Post category.
- Educational templates are not first-class yet; they need to be represented through `story`, `social`, and `promotionalPoster` until the taxonomy changes deliberately.
- Persian sale/promo, cafe/restaurant, hiring/business, seasonal/cultural, and education need more depth.
- English templates need more professional social/business/education variety beyond the YouTube and quote/sale basics.

## Category Gaps

Current gaps after the 53-template baseline:

| Area | Current issue | Near-term treatment |
| --- | --- | --- |
| Persian Instagram Story | Useful but still shallow for a Persian-first app | Add more product reveal, offer, cafe, course, announcement, and event story designs |
| Persian Instagram Post | No dedicated enum category | Use `social`, `event`, `greeting`, `quote`, and `food` for square post designs |
| Persian Poetry / Quote | Quality exists, but needs more premium Nastaliq/editorial treatments | Add more literary, dark editorial, gallery, and minimal quote templates |
| Persian Sale / Promo | Existing sale/promo count is low for business users | Add more retail, market, launch, restaurant, and luxury sale posters |
| Restaurant / Cafe | Present, but not enough Persian-first ready designs | Add cafe story, restaurant promo, menu, seasonal offer, and coffee variants |
| Business / Hiring | Too thin, especially Persian | Add hiring, brand intro, agency/service offer, resume/job fair, and office announcement designs |
| Education | Not explicit in taxonomy | Add course signup, checklist, class announcement, webinar, and exam-prep designs using existing categories |
| Religious / Cultural / Seasonal | Minimal coverage | Add tasteful seasonal/cultural/greeting templates without hard-coding narrow content |
| English Social / Business / Education | English set leans toward YouTube, quote, sale | Add more launch, carousel-style post starters, business promos, education, and event designs |

## Recommended MVP Target Counts

Recommended MVP library size:

| Language | MVP target | Rationale |
| --- | ---: | --- |
| Persian | 60-80 | This should be the app's visible differentiator; Persian templates need depth across story, post, sale, poetry, culture, food, education, and business. |
| English | 40-60 | Enough variety to feel professional without diluting the Persian-first value. |
| Total | 100-140 | This range is large enough for Home/Browse to feel like a real design app while still allowing quality control. |

Recommended balance for MVP: about 60 percent Persian and 40 percent English. After Batch 2 the catalog is 62 Persian and 32 English, so the next batch should keep Persian quality high while adding a measured set of English professional templates.

## Priority Categories

Persian priority categories:

- Instagram Story
- Instagram Post, represented through `social`, `story`, `quote`, `food`, `event`, and `greeting` until taxonomy changes
- Poetry / quote
- Sale / promo
- Restaurant / cafe menu and offers
- Event announcement
- Business / hiring
- Educational templates
- Religious, cultural, and seasonal templates where the content is broadly useful and tasteful

English priority categories:

- YouTube thumbnails
- Instagram/social posts
- Stories
- Sale / promo
- Quotes
- Event
- Business
- Education

## Existing Templates To Redesign Or Expand Around

No existing templates should be removed. The current 53 can remain as the foundation, but these areas should receive redesign variants or companion templates:

- `fa_business_hiring`: keep it, but add more Persian business and hiring styles.
- `fa_food_menu`, `fa_food_coffee`: keep them, but add richer restaurant/cafe campaign variants.
- `fa_sale_bold`, `fa_sale_flash`, `fa_promo_sale_v1`: keep them, but add more premium sale styles and market/retail offers.
- `fa_poetry_v1`, `fa_poetry_minimal_v1`, `fa_poetry_traditional_v1`, `fa_poetry_overlay_v1`: keep them, but add stronger Nastaliq/editorial and gallery-style variants.
- `fa_insta_story_*`: keep them, but add more commercial, education, cafe, product reveal, and seasonal story variants.
- `en_yt_*`: keep them, but add more modern YouTube thumbnail concepts with clearer subject/focal layouts.
- English `business`, `event`, `social`, and education-like use cases need more companion templates.

## Template Expansion Batch 1

Batch 1 adds 18 new JSON templates: 15 Persian and 3 English. The batch is Persian-first and concentrates on visible shelf richness in Home/Browse.

Persian Instagram/story/post templates:

1. `fa_story_product_reveal` — Persian product reveal story.
2. `fa_story_daily_offer` — Persian daily offer story.
3. `fa_story_cafe_mood` — Persian cafe mood story.
4. `fa_story_course_signup` — Persian course signup story.
5. `fa_post_brand_intro` — Persian brand intro square post.
6. `fa_post_minimal_tip` — Persian educational/tip square post.
7. `fa_post_event_countdown` — Persian event countdown square post.
8. `fa_post_culture_seasonal` — Persian cultural/seasonal square post.

Persian sale/promo templates:

1. `fa_sale_luxury_drop` — premium Persian sale poster.
2. `fa_sale_market_weekend` — Persian weekend market sale poster.
3. `fa_promo_restaurant_special` — Persian restaurant special poster.
4. `fa_promo_course_launch` — Persian course launch poster.

Persian poetry/quote templates:

1. `fa_poetry_nastaliq_evening` — Persian Nastaliq evening poem card.
2. `fa_quote_modern_dark` — Persian modern dark quote card.
3. `fa_poetry_gallery_card` — Persian gallery poetry card.

English YouTube/social templates:

1. `en_yt_ai_tools_2026` — AI tools YouTube thumbnail.
2. `en_yt_before_after_design` — before/after design YouTube thumbnail.
3. `en_social_launch_checklist` — launch checklist square social post.

Batch 1 implementation notes:

- Every template has `template.json`, `document.json`, and `thumbnail.png`.
- Every document uses editable text layers.
- Thumbnails were rendered from the production `DocumentView` with app fonts, then scaled to match the document aspect ratio.
- New templates are registered in `assets/templates/manifest.json` and `pubspec.yaml`.
- Batch-specific tests verify manifest registration, unique IDs, category/language validity, document decoding, unique layer IDs, thumbnail decoding, and thumbnail aspect ratio.

## Post-Batch 1 Counts

| Metric | Count |
| --- | ---: |
| Total JSON templates | 71 |
| Persian templates | 44 |
| English templates | 27 |

Post-Batch 1 category counts:

| Category | Count |
| --- | ---: |
| business | 3 |
| event | 5 |
| food | 4 |
| greeting | 5 |
| instagramStory | 9 |
| motivational | 2 |
| poetryPost | 6 |
| promotionalPoster | 6 |
| quote | 6 |
| sale | 7 |
| social | 5 |
| story | 5 |
| youtubeThumbnail | 8 |

## Recommended Batch 2

Recommended Batch 2 size: 18-24 templates.

Suggested Batch 2 priorities:

1. Add 4 Persian business/hiring templates: recruitment story, agency intro, service offer, and professional announcement.
2. Add 4 Persian restaurant/cafe/menu templates: menu board, breakfast offer, delivery promo, cafe event.
3. Add 4 Persian education templates: webinar, exam prep, workshop poster, carousel-like tip post.
4. Add 3 Persian seasonal/cultural templates: Nowruz-style greeting, Ramadan/Iftar offer if appropriate, general celebration card.
5. Add 3-5 English professional templates: business launch, webinar, event poster, Instagram post, and YouTube explainer thumbnail.

Batch 2 completed this goal and moved the catalog to 94 templates.

## Template Expansion Batch 2

Batch 2 adds 23 new JSON templates: 18 Persian and 5 English. The batch deepens the categories users are most likely to need in a production design app: business/hiring, restaurant/cafe/menu, education/course, seasonal/cultural, professional English event/business, and YouTube explainer thumbnails.

Persian business/hiring templates:

1. `fa_business_recruitment_story` — Persian recruitment story.
2. `fa_business_agency_intro` — Persian agency intro post.
3. `fa_business_service_offer` — Persian service offer poster.
4. `fa_business_job_fair` — Persian job fair/event poster.
5. `fa_business_team_hiring` — Persian team hiring story.
6. `fa_business_consulting_post` — Persian consulting/social post.

Persian restaurant/cafe/menu templates:

1. `fa_food_modern_menu_board` — Persian modern menu board.
2. `fa_food_delivery_story` — Persian food delivery story.
3. `fa_cafe_breakfast_special` — Persian cafe breakfast offer.
4. `fa_restaurant_live_night` — Persian restaurant live-night event poster.
5. `fa_food_dessert_launch` — Persian dessert launch post.

Persian education/course templates:

1. `fa_edu_webinar_story` — Persian webinar story.
2. `fa_edu_workshop_poster` — Persian workshop poster.
3. `fa_edu_exam_prep_post` — Persian exam-prep educational post.
4. `fa_edu_course_tip_carousel` — Persian course/tip carousel cover.

Persian seasonal/cultural templates:

1. `fa_season_nowruz_greeting` — Persian Nowruz greeting post.
2. `fa_season_iftar_invite` — Persian Iftar invite poster.
3. `fa_cultural_book_night` — Persian book-night cultural event poster.

English business/webinar/event/social/YouTube templates:

1. `en_business_product_update` — English product update business post.
2. `en_webinar_growth_masterclass` — English webinar/course event poster.
3. `en_event_startup_pitch` — English startup pitch event poster.
4. `en_social_case_study` — English case-study social post.
5. `en_yt_explainer_framework` — English YouTube explainer thumbnail.

Batch 2 implementation notes:

- Every template has `template.json`, `document.json`, and `thumbnail.png`.
- Every document uses editable text layers.
- Thumbnails were rendered from the production `DocumentView` with app fonts, then scaled to match document aspect ratio.
- New templates are registered in `assets/templates/manifest.json` and `pubspec.yaml`.
- Batch-specific tests verify manifest registration, unique IDs, category/language validity, document decoding, unique layer IDs, thumbnail decoding, thumbnail aspect ratio, file existence, and pubspec asset declaration coverage.

## Post-Batch 2 Counts

| Metric | Count |
| --- | ---: |
| Total JSON templates | 94 |
| Persian templates | 62 |
| English templates | 32 |

Post-Batch 2 category counts:

| Category | Count |
| --- | ---: |
| business | 9 |
| event | 11 |
| food | 8 |
| greeting | 6 |
| instagramStory | 9 |
| motivational | 2 |
| poetryPost | 6 |
| promotionalPoster | 7 |
| quote | 6 |
| sale | 7 |
| social | 8 |
| story | 6 |
| youtubeThumbnail | 9 |

## Recommended Batch 3

Recommended Batch 3 size: 18-24 templates.

Suggested Batch 3 priorities:

1. Add 5-6 Persian Instagram post/story templates for fashion, beauty, health, product drops, and service announcements.
2. Add 4-5 Persian sale/promo templates for retail, real estate, medical/clinic, travel, and app/service launch use cases.
3. Add 3-4 Persian poetry/quote/editorial templates with more premium literary and magazine-style layouts.
4. Add 3-4 English YouTube/social templates for tutorial, reaction, podcast, and educational explainer use cases.
5. Add 3-4 English business/event templates for hiring, product launch, conference, and course/webinar promotion.

Batch 3 completed this goal and moved the catalog to 116 templates.

## Template Expansion Batch 3

Batch 3 adds 22 new JSON templates: 18 Persian and 4 English. The batch pushes the catalog into the lower MVP range while keeping the Persian-first advantage visible across fashion/beauty/health stories, product/service posts, sale/promo, premium poetry/editorial, business/event, and modern English YouTube/business starters.

Persian Instagram story/post templates:

1. `fa_story_fashion_drop` — Persian fashion drop story.
2. `fa_story_beauty_booking` — Persian beauty booking story.
3. `fa_story_health_clinic_tip` — Persian health/clinic tip story.
4. `fa_post_product_carousel_cover` — Persian product carousel cover.
5. `fa_post_service_announcement` — Persian service announcement post.
6. `fa_post_personal_brand_quote` — Persian personal brand quote post.

Persian sale/promo templates:

1. `fa_sale_retail_clearance` — Persian retail clearance sale poster.
2. `fa_promo_clinic_checkup` — Persian clinic checkup promo poster.
3. `fa_promo_travel_tour` — Persian travel tour promo poster.
4. `fa_sale_beauty_package` — Persian beauty package sale poster.
5. `fa_promo_app_launch` — Persian app launch promo poster.

Persian poetry/quote/editorial templates:

1. `fa_poetry_black_gold_nastaliq` — Persian black/gold Nastaliq poem card.
2. `fa_quote_editorial_magazine` — Persian editorial magazine quote poster.
3. `fa_poetry_photo_frame_premium` — Persian premium photo poetry poster.
4. `fa_quote_literary_column` — Persian literary column quote post.

Persian event/business templates:

1. `fa_event_gallery_opening` — Persian gallery opening event poster.
2. `fa_business_service_launch_story` — Persian service launch story.
3. `fa_event_workshop_announcement` — Persian workshop announcement poster.

English YouTube/social/business templates:

1. `en_yt_tutorial_blueprint` — English tutorial blueprint YouTube thumbnail.
2. `en_yt_reaction_hot_take` — English reaction/hot-take YouTube thumbnail.
3. `en_yt_podcast_interview` — English podcast interview YouTube thumbnail.
4. `en_social_business_announcement` — English premium business announcement post.

Batch 3 implementation notes:

- Every template has `template.json`, `document.json`, and `thumbnail.png`.
- Every document uses editable text layers.
- Thumbnails were rendered from the production `DocumentView` with app fonts, then scaled to match document aspect ratio.
- A contact sheet was reviewed after generation and the product carousel cover was tightened before final thumbnail regeneration.
- New templates are registered in `assets/templates/manifest.json` and `pubspec.yaml`.
- Batch-specific tests verify manifest registration, unique IDs, category/language validity, document decoding, unique layer IDs, thumbnail decoding, thumbnail aspect ratio, file existence, pubspec asset declaration coverage, and removal of the temporary thumbnail generator.

## Post-Batch 3 Counts

| Metric | Count |
| --- | ---: |
| Total JSON templates | 116 |
| Persian templates | 80 |
| English templates | 36 |

Post-Batch 3 category counts:

| Category | Count |
| --- | ---: |
| business | 11 |
| event | 13 |
| food | 8 |
| greeting | 6 |
| instagramStory | 12 |
| motivational | 2 |
| poetryPost | 8 |
| promotionalPoster | 10 |
| quote | 9 |
| sale | 9 |
| social | 10 |
| story | 6 |
| youtubeThumbnail | 12 |

## Recommended Batch 4

Recommended Batch 4 size: 14-20 templates.

Suggested Batch 4 priorities:

1. Bring English closer to MVP balance with more social/business/event/course templates.
2. Add Persian food, greeting, and story variants because those categories did not grow in Batch 3.
3. Add more professional carousel-style square posts using `social` until the taxonomy gains a dedicated carousel/post category.
4. Keep thumbnail generation through `DocumentView` and continue contact-sheet review before final validation.

## Home/Browse Presentation Polish

This phase keeps the 116-template catalog and JSON format unchanged. The polish is presentation-only: Home and Browse now apply curated ordering on top of the repository-backed `Template` list instead of showing raw manifest order.

What changed:

- Home's recommended strip now starts with stronger Batch 1-3 designs such as `fa_story_fashion_drop`, `fa_promo_app_launch`, `fa_poetry_black_gold_nastaliq`, and `en_yt_tutorial_blueprint` before older migrated fallbacks.
- Home's category strips keep their existing labels and proportions, but their internal order now prefers fresher, more polished templates within stories, ads/sale, YouTube, typography, and poetry.
- Browse now sorts visible results after language, category, and search filters are applied, so filtering never drops templates and the final shelf still feels curated.
- Browse category chips use a product-oriented order: story/social, sale/promo, business, food/menu, events, quote/poetry, and YouTube instead of raw enum order.
- Browse search now includes presentation-only use-case keywords so education/course templates are discoverable even though education is not a first-class category enum yet.

Ordering rules:

- Respect the active language/category/search filters first.
- Prefer the active UI language when Browse is showing all or mixed languages; Persian locale shows Persian templates first.
- Within the filtered set, place explicitly curated IDs first, then Batch 3, Batch 2, Batch 1, and finally older fallbacks in their original relative order.
- Preserve stable ordering and keep every filtered template in the result.

Category display rules:

- Do not add taxonomy values until the category model is deliberately expanded.
- Represent education through search keywords and existing `story`, `social`, and `promotionalPoster` categories.
- Keep `sale` and `promotionalPoster` distinct in Browse chips, while Home can present them together as advertising templates.
- Keep Home labels localized through existing strings; no template ID, category enum, or asset path changed.

Remaining UX recommendations:

- Consider expanding the Home category preference picker beyond the original four onboarding goals so business, food, event, sale, and social rows can be user-controlled directly.
- Consider adding metadata-backed presentation fields to `Template` only in a deliberate data-model phase; the current polish mirrors featured/sort intent by ID to avoid repository churn.
- Add visual badges or compact section headers later if user testing shows Browse still feels too dense with 100+ templates.

## Template Design Quality Rescue Pass

This phase does not add templates or change Home/Browse, editor, engine, codec, repository, route, category, or ID architecture. It rescues existing weak template documents and regenerates their thumbnails through the production document-rendering path.

Rescue checklist:

- Purpose is clear within 2 seconds.
- Headline is dominant and readable at small card size.
- Subtitle supports the template purpose instead of repeating the headline.
- CTA is visible, meaningful, and placed near the natural action area.
- Main visual supports the template purpose.
- No meaningless placeholder shape dominates the design.
- Text does not collide with visual elements.
- Thumbnail reads in Home/Browse compact cards.
- Persian typography is strong, readable, and natural.

Weak-template audit candidates from manual emulator/contact-sheet review:

1. `fa_story_product_reveal` — product meaning was abstract and the object read as generic shapes.
2. `fa_promo_app_launch` — phone/object existed, but the campaign structure and benefit hierarchy were too generic.
3. `fa_story_fashion_drop` — used as the closest rescue target for the missing `fa_story_motivation`; the fashion/product visual was too abstract.
4. `fa_post_product_carousel_cover` — crowded cover, headline and product visual competed.
5. `fa_story_today` — too vague as a daily note and not useful enough as a real starter.
6. `fa_story_beauty_booking` — weak salon/booking metaphor.
7. `fa_post_service_announcement` — clearer than some, but still generic and not service-driven enough.
8. `fa_business_service_launch_story` — launch metaphor was abstract and weak for a service story.
9. `fa_story_health_clinic_tip` — readable but still template-like and icon-heavy.
10. `fa_promo_clinic_checkup` — purpose is clear, but the visual is still mostly a medical icon block.
11. `fa_promo_travel_tour` — travel purpose depends on a generic landscape card.
12. `fa_sale_beauty_package` — stronger than booking, but still should be watched for text density.
13. `fa_event_gallery_opening` — useful, but the gallery visual is minimal.
14. `fa_edu_webinar_story` — clear enough, though the visual metaphor remains simple.
15. `fa_business_recruitment_story` — serviceable, but dense in small cards.

Rescued first-pass templates:

1. `fa_story_product_reveal`
2. `fa_promo_app_launch`
3. `fa_story_fashion_drop`
4. `fa_post_product_carousel_cover`
5. `fa_story_today`
6. `fa_story_beauty_booking`
7. `fa_post_service_announcement`
8. `fa_business_service_launch_story`

Rescue implementation notes:

- No new templates were added and no template IDs, routes, repository logic, codec behavior, editor behavior, or Home/Browse presentation code changed.
- The eight rescued templates now use clearer purpose-driven document layouts: product mockups, app phone frame, fashion lookbook card, product carousel cover, daily update card, beauty booking motif, service feature cards, and service-launch checklist/dashboard visuals.
- Thumbnails were regenerated from the production `DocumentView` render path with app fonts after the document edits.
- The final rescue contact sheet was reviewed at compact card size and two small issues were tightened before final generation: app-launch chip contrast and service-announcement headline/icon spacing.
- `test/editor/templates/template_design_quality_rescue_test.dart` verifies manifest registration, document decoding, unique layer IDs, key editable text, thumbnail decoding/aspect ratio, and removal of the temporary thumbnail generator.
- Remaining watch-list candidates for a later pass: `fa_story_health_clinic_tip`, `fa_promo_clinic_checkup`, `fa_promo_travel_tour`, `fa_sale_beauty_package`, `fa_event_gallery_opening`, `fa_edu_webinar_story`, `fa_business_recruitment_story`, and `fa_event_workshop_announcement`.

## Template Design Quality Rescue Pass 2

Manual emulator QA after Rescue Pass 1 narrowed the still-weak set to four
existing templates: `fa_story_beauty_booking`, `fa_story_product_reveal`,
`fa_post_service_announcement`, and `fa_story_today`. Pass 2 keeps the same
constraints as Pass 1: no new templates, IDs, categories, manifest structure,
Home/Browse code, editor code, engine code, codec behavior, repository logic,
routes, or TemplateCatalog cleanup.

Pass 2 treatment:

- `fa_story_beauty_booking`: make the salon booking purpose literal with an appointment card, calendar slots, beauty-tool visual, readable headline, strong subtitle, and high-contrast booking CTA.
- `fa_story_product_reveal`: make the product reveal purpose literal with an upright product package/card, clear product badge, cleaner text hierarchy, no rotated label, and high-contrast product CTA.
- `fa_post_service_announcement`: make the service announcement look like a real product/service card with feature checklist rows, a clear service label, direct headline/subtitle relationship, and `بیشتر بدانید` CTA.
- `fa_story_today`: convert the generic story into a useful daily offer/update template with `امروز` badge, offer-card visual, `پیشنهاد امروز` headline, supporting subtitle, and details CTA.

## Template Design Micro Polish Pass

Manual emulator QA after Rescue Pass 2 narrowed the final issues to three
existing templates: `fa_story_beauty_booking`,
`fa_post_service_announcement`, and `fa_story_today`. The micro pass keeps the
same constraints as the rescue passes: no new templates, IDs, categories,
manifest structure, Home/Browse code, editor code, engine code, codec behavior,
repository logic, routes, or TemplateCatalog cleanup.

Micro polish treatment:

- `fa_story_beauty_booking`: simplify the appointment visual, make the palette consistently pink/plum/cream, use a plum CTA, raise the headline, and make the salon booking purpose feel premium.
- `fa_post_service_announcement`: replace remaining empty/generic space with a clear product/service feature card, 2-3 feature chips, benefit subtitle, and aligned CTA.
- `fa_story_today`: keep the offer card, connect the supporting copy to the daily offer with a useful footer strip, and preserve a strong deadline-style CTA.
