# Template Quality Audit - Phase 1

This report audits the visual quality of JSON templates registered in
`assets/templates/manifest.json`. Phase 1 began as a report-only pass; Polish
Batches 1, 2, and 3, followed by Template Minor Polish Cleanup and Redesign
Later Decision, then updated only selected template asset `document.json` files
and their `thumbnail.png` previews. Home/Browse UI, editor behavior, engine
code, template architecture, repository logic, categories, and template IDs were
not changed.

## Scope

| Metric | Count |
| --- | ---: |
| JSON templates audited | 116 |
| Combined templates | 116 |
| Legacy-only templates remaining | 0 |

## Summary

| Quality group | Count | Meaning |
| --- | ---: | --- |
| Ready | 116 | Usable in production with solid thumbnail, readable text, balanced composition, and accurate category fit. |
| Needs minor polish | 0 | Good design direction, but spacing, small text, or hierarchy should be tightened. |
| Needs major polish | 0 | The template may be structurally valid, but the thumbnail/design presentation is too block-like or unreadable for production browsing. |
| Should be redesigned later | 0 | Useful as asset-pipeline samples, but too generic to keep as production-facing templates without a concept refresh. |

## Completed Polish Batch 1

These 12 important Home/Browse templates were polished by tightening document
typography, spacing, hierarchy, and regenerating thumbnails with bundled fonts:

1. `fa_insta_story_v1`
2. `fa_promo_v1`
3. `fa_poetry_overlay_v1`
4. `en_yt_thumb_v1`
5. `en_announcement`
6. `fa_quote_minimal`
7. `en_quote_minimal`
8. `fa_poetry_v1`
9. `fa_promo_sale_v1`
10. `fa_insta_story_bold_word_v1`
11. `en_yt_question_v1`
12. `en_yt_list_v1`

Batch 1 outcome: 9 moved to Ready and 3 moved to Needs minor polish.

## Completed Polish Batch 2

These 10 major-polish templates were improved by making the text visible in
Home/Browse, tightening Persian and English typography, and regenerating
thumbnails with bundled fonts:

1. `en_quote_editorial_gradient`
2. `fa_story_warm_pastel`
3. `fa_poetry_minimal_v1`
4. `fa_insta_story_announcement_v1`
5. `fa_insta_story_frame_v1`
6. `fa_poetry_traditional_v1`
7. `fa_promo_event_v1`
8. `fa_promo_launch_v1`
9. `en_sale_modern_gradient`
10. `en_story_quote`

Batch 2 outcome: 7 moved to Ready and 3 moved to Needs minor polish.

## Completed Polish Batch 3

These 9 remaining major-polish templates were improved by replacing block-only
previews with readable document thumbnails, tightening sale/story/quote
hierarchy, and regenerating thumbnails with bundled fonts:

1. `fa_sale_bold`
2. `fa_insta_story_minimal_v1`
3. `en_sale_bold`
4. `en_birthday_confetti`
5. `fa_story_quote`
6. `fa_announcement`
7. `en_quote_editorial`
8. `fa_quote_editorial`
9. `en_story_motivation`

Batch 3 outcome: 8 moved to Ready and 1 moved to Needs minor polish. Needs
major polish is now empty.

## Completed Template Minor Polish Cleanup

These 15 remaining minor-polish templates were improved with small, safe
document and thumbnail updates: stronger detail-text sizing, tighter spacing,
cleaner alignment, clearer CTAs, and regenerated font-loaded previews.

1. `en_event_market`
2. `fa_event`
3. `fa_food_menu`
4. `en_food_coffee`
5. `en_sale_flash`
6. `en_event_concert`
7. `fa_food_coffee`
8. `fa_concert`
9. `fa_insta_story_v1`
10. `fa_promo_sale_v1`
11. `en_yt_question_v1`
12. `fa_insta_story_announcement_v1`
13. `fa_insta_story_frame_v1`
14. `fa_promo_launch_v1`
15. `fa_insta_story_minimal_v1`

Minor cleanup outcome: all 15 moved to Ready. Needs minor polish is now empty.

## Completed Redesign Later Decision

The 2 remaining sample templates were reviewed for category fit, language,
duplicate value, visual quality, and usefulness. Both were visible catalog
entries, not hidden fixtures, and each still filled a useful simple starter role
after a concept refresh. Decision: Redesign now for both, preserving template
IDs, categories, languages, routes, and metadata.

1. `fa_story_today` — redesigned now as a Persian daily story starter.
2. `en_youtube_watch_this` — redesigned now as an English YouTube thumbnail starter.

Redesign decision outcome: both moved to Ready. Should be redesigned later is
now empty.

## Completed Template Product Quality Batch 1

These 18 new templates were added as the first production-quality expansion
batch. The batch is Persian-first and improves visible Home/Browse depth across
story, social post, sale, promo, restaurant, education, poetry, quote, and
English YouTube/social use cases.

1. `fa_story_product_reveal`
2. `fa_story_daily_offer`
3. `fa_story_cafe_mood`
4. `fa_story_course_signup`
5. `fa_post_brand_intro`
6. `fa_post_minimal_tip`
7. `fa_post_event_countdown`
8. `fa_post_culture_seasonal`
9. `fa_sale_luxury_drop`
10. `fa_sale_market_weekend`
11. `fa_promo_restaurant_special`
12. `fa_promo_course_launch`
13. `fa_poetry_nastaliq_evening`
14. `fa_quote_modern_dark`
15. `fa_poetry_gallery_card`
16. `en_yt_ai_tools_2026`
17. `en_yt_before_after_design`
18. `en_social_launch_checklist`

Batch 1 outcome: 18 new Ready templates added. Total JSON templates is now 71.

## Completed Template Product Quality Batch 2

These 23 new templates were added as the second production-quality expansion
batch. The batch is Persian-heavy and improves business/hiring,
restaurant/cafe/menu, education/course, seasonal/cultural, English
business/event/social, and YouTube explainer coverage.

1. `fa_business_recruitment_story`
2. `fa_business_agency_intro`
3. `fa_business_service_offer`
4. `fa_business_job_fair`
5. `fa_business_team_hiring`
6. `fa_business_consulting_post`
7. `fa_food_modern_menu_board`
8. `fa_food_delivery_story`
9. `fa_cafe_breakfast_special`
10. `fa_restaurant_live_night`
11. `fa_food_dessert_launch`
12. `fa_edu_webinar_story`
13. `fa_edu_workshop_poster`
14. `fa_edu_exam_prep_post`
15. `fa_edu_course_tip_carousel`
16. `fa_season_nowruz_greeting`
17. `fa_season_iftar_invite`
18. `fa_cultural_book_night`
19. `en_business_product_update`
20. `en_webinar_growth_masterclass`
21. `en_event_startup_pitch`
22. `en_social_case_study`
23. `en_yt_explainer_framework`

Batch 2 outcome: 23 new Ready templates added. Total JSON templates is now 94.

## Completed Template Product Quality Batch 3

These 22 new templates were added as the third production-quality expansion
batch. The batch reaches the lower MVP catalog range and adds Persian-first
fashion, beauty, health, service, sale/promo, premium poetry/editorial,
business/event depth plus modern English YouTube and business starters.

1. `fa_story_fashion_drop`
2. `fa_story_beauty_booking`
3. `fa_story_health_clinic_tip`
4. `fa_post_product_carousel_cover`
5. `fa_post_service_announcement`
6. `fa_post_personal_brand_quote`
7. `fa_sale_retail_clearance`
8. `fa_promo_clinic_checkup`
9. `fa_promo_travel_tour`
10. `fa_sale_beauty_package`
11. `fa_promo_app_launch`
12. `fa_poetry_black_gold_nastaliq`
13. `fa_quote_editorial_magazine`
14. `fa_poetry_photo_frame_premium`
15. `fa_quote_literary_column`
16. `fa_event_gallery_opening`
17. `fa_business_service_launch_story`
18. `fa_event_workshop_announcement`
19. `en_yt_tutorial_blueprint`
20. `en_yt_reaction_hot_take`
21. `en_yt_podcast_interview`
22. `en_social_business_announcement`

Batch 3 outcome: 22 new Ready templates added. Total JSON templates is now 116.

## Completed Template Design Quality Rescue Pass

Manual emulator/contact-sheet review found several existing templates that were
technically valid and registered correctly, but still looked generic or unclear
in compact Home/Browse cards. This rescue pass improved only existing template
documents and thumbnails. No Home/Browse architecture, editor code, engine code,
DocumentCodec behavior, repository logic, routes, categories, template IDs, or
template count changed.

The first-pass rescue redesigned these 8 templates around clearer use cases and
regenerated thumbnails from the production `DocumentView` render path:

1. `fa_story_product_reveal` — stronger product reveal story with a product mockup, launch badge, availability chip, and clear CTA.
2. `fa_promo_app_launch` — clearer app launch post with phone frame, feature chips, and download CTA.
3. `fa_story_fashion_drop` — clearer fashion collection story with a lookbook/product-card visual and collection CTA.
4. `fa_post_product_carousel_cover` — clearer carousel cover with slide count, product mockups, and three editable feature bullets.
5. `fa_story_today` — more useful daily update story with date-card framing, short update copy, and details CTA.
6. `fa_story_beauty_booking` — clearer beauty booking story with salon/appointment visual cues and booking CTA.
7. `fa_post_service_announcement` — clearer service announcement post with service icon, feature cards, and details CTA.
8. `fa_business_service_launch_story` — clearer service launch story with checklist/dashboard visual, launch headline, and CTA.

Rescue pass outcome: all 8 remain Ready, with stronger purpose signals and
readable regenerated thumbnails. Remaining watch-list candidates for a future
quality pass are `fa_story_health_clinic_tip`, `fa_promo_clinic_checkup`,
`fa_promo_travel_tour`, `fa_sale_beauty_package`, `fa_event_gallery_opening`,
`fa_edu_webinar_story`, `fa_business_recruitment_story`, and
`fa_event_workshop_announcement`.

## Completed Template Design Quality Rescue Pass 2

Manual emulator QA after Rescue Pass 1 narrowed the remaining weak set to four
existing templates. The screenshots mapped to the current metadata as
`fa_story_beauty_booking`, `fa_story_product_reveal`,
`fa_post_service_announcement`, and `fa_story_today`. This pass changed only
those four `document.json` files and regenerated only their thumbnails. No new
templates, IDs, categories, manifest structure, Home/Browse code, editor code,
engine code, DocumentCodec behavior, repository logic, routes, or
TemplateCatalog cleanup changed.

The pass-2 fixes were:

1. `fa_story_beauty_booking` — replaced abstract salon shapes with a clean appointment card, calendar slot rows, beauty-tool elements, readable headline, stronger subtitle contrast, and `رزرو آنلاین` CTA.
2. `fa_story_product_reveal` — replaced the awkward rotated product mark with an upright product package/card, clear `محصول تازه` badge, calmer hierarchy, and `مشاهده محصول` CTA.
3. `fa_post_service_announcement` — replaced the placeholder-like icon composition with a professional service dashboard card, check-mark feature rows, `معرفی خدمت` label, and `بیشتر بدانید` CTA.
4. `fa_story_today` — converted the generic daily note into a useful daily offer/update story with `امروز` badge, offer card, `پیشنهاد امروز` headline, and details CTA.

Rescue Pass 2 outcome: all four thumbnails read more clearly in the focused
contact sheet. Follow-up manual emulator QA then narrowed the final visual
issues to three micro-polish targets: `fa_story_beauty_booking`,
`fa_post_service_announcement`, and `fa_story_today`.

## Completed Template Design Micro Polish Pass

Manual emulator QA after Rescue Pass 2 found three remaining quality issues in
existing templates. This micro pass changed only the three target
`document.json` files and regenerated only their thumbnails. No new templates,
template IDs, categories, manifest structure, Home/Browse code, editor code,
engine code, DocumentCodec behavior, repository logic, routes, or
TemplateCatalog cleanup changed.

The micro-polish fixes were:

1. `fa_story_beauty_booking` — simplified the busy appointment visual into an elegant booking card, switched the CTA and accents to a consistent plum/rose/cream salon palette, moved the headline higher, shortened the subtitle, and kept the editable `رزرو آنلاین` action.
2. `fa_post_service_announcement` — rebuilt the placeholder-like visual as a product/service feature card with editable product label, feature chips, stronger benefit copy, and an intentionally aligned `بیشتر بدانید` CTA.
3. `fa_story_today` — kept the daily offer structure while turning the lower empty area into a useful footer strip, preserving `پیشنهاد امروز`, adding the editable product/price/deadline subtitle, and changing the CTA to `فقط تا امشب`.

Micro Polish Pass outcome: all three thumbnails read clearly in the focused
contact sheet and no weak template remains in the manually confirmed final set.
Continue to watch the broader earlier candidates during future emulator QA,
especially `fa_story_health_clinic_tip`, `fa_promo_clinic_checkup`,
`fa_promo_travel_tour`, `fa_sale_beauty_package`,
`fa_event_gallery_opening`, `fa_edu_webinar_story`,
`fa_business_recruitment_story`, and `fa_event_workshop_announcement`.

## Obvious Thumbnail Issues

- No production-facing migrated template remains in Needs major polish.
- Polish Batches 1, 2, and 3 plus Minor Polish Cleanup and Redesign Later Decision thumbnails now render with bundled fonts and expose real text hierarchy in Home/Browse.
- The Template Design Quality Rescue Pass tightened 8 previously generic-but-valid templates and regenerated their thumbnails from the production document render path.
- Rescue Pass 2 tightened four manually confirmed weak thumbnails after emulator QA, and the Micro Polish Pass refined the final three visual issues found afterward.
- The former asset-pipeline samples were redesigned as production-ready starter templates; no template remains in Should Be Redesigned Later.
- Persian and English typography can now be judged from the production-facing migrated thumbnails because their previews expose real glyphs.
- Event, food, sale, story, and promotional thumbnails now have readable detail text and clearer compact-card hierarchy.
- No category mismatch was found in metadata during this audit.

## Ready

| Template | Category / language | Quality notes |
| --- | --- | --- |
| `en_motivation_sunrise` | motivational / english | Strong thumbnail, warm color harmony, readable English typography, balanced spacing, category accurate, production-ready. |
| `en_business_card_post` | business / english | Clear hierarchy, readable headline, good contrast, balanced spacing, category accurate, production-ready. |
| `fa_birthday` | greeting / persian | Readable Persian headline, cheerful color harmony, balanced decorative elements, category accurate, production-ready. |
| `fa_motivation_sunrise` | motivational / persian | Good Persian readability, balanced sunrise composition, warm palette, category accurate, production-ready. |
| `en_yt_reaction_v1` | youtubeThumbnail / english | Strong YouTube-style impact, readable text, high contrast, category accurate, production-ready. |
| `en_yt_tutorial_v1` | youtubeThumbnail / english | Strong landscape thumbnail, readable English type, clear focal point, category accurate, production-ready. |
| `fa_business_hiring` | business / persian | Strong Persian headline, good contrast, credible business tone, category accurate, production-ready. |
| `en_food_menu` | food / english | Readable menu layout, pleasant palette, balanced food motif, category accurate, production-ready. |
| `en_greeting_thanks` | greeting / english | Clean composition, readable mixed typography, soft color harmony, category accurate, production-ready. |
| `en_business_quote` | business / english | Good quote layout, calm palette, readable main copy, category accurate, production-ready. |
| `fa_sale_flash` | sale / persian | Strong Persian sale message, clear contrast, category accurate, production-ready. |
| `fa_thanks` | greeting / persian | Clean Persian greeting, readable hierarchy, soft palette, category accurate, production-ready. |
| `fa_promo_v1` | promotionalPoster / persian | Improved Persian sale hierarchy, clearer CTA, stronger contrast, and readable font-loaded thumbnail; production-ready. |
| `fa_poetry_overlay_v1` | poetryPost / persian | Improved poetry panel, stronger verse type, readable author line, and balanced dark overlay; production-ready. |
| `en_yt_thumb_v1` | youtubeThumbnail / english | Regenerated readable YouTube thumbnail with stronger headline/subtitle hierarchy and high contrast; production-ready. |
| `en_announcement` | social / english | Improved title scale, footer readability, and announcement hierarchy; production-ready. |
| `fa_quote_minimal` | quote / persian | Improved Persian quote font, rule placement, attribution spacing, and readable thumbnail; production-ready. |
| `en_quote_minimal` | quote / english | Improved quote spacing, rule placement, attribution scale, and readable editorial thumbnail; production-ready. |
| `fa_poetry_v1` | poetryPost / persian | Improved Persian poetry font, frame balance, and verse readability; production-ready. |
| `fa_insta_story_bold_word_v1` | instagramStory / persian | Improved bold Persian word treatment, caption contrast, and story thumbnail readability; production-ready. |
| `en_yt_list_v1` | youtubeThumbnail / english | Improved number badge, headline, subtitle contrast, and right-panel balance; production-ready. |
| `en_quote_editorial_gradient` | quote / english | Improved editorial quote typography, stronger spacing, visible attribution, and font-loaded thumbnail; production-ready. |
| `fa_story_warm_pastel` | story / persian | Improved Persian headline scale, warmer card hierarchy, readable caption, and balanced pastel story composition; production-ready. |
| `fa_poetry_minimal_v1` | poetryPost / persian | Improved Persian poetry card, stronger verse font, clearer author line, and refined rule spacing; production-ready. |
| `fa_poetry_traditional_v1` | poetryPost / persian | Improved traditional frame, readable Persian verse typography, visible kicker, and balanced ornament spacing; production-ready. |
| `fa_promo_event_v1` | promotionalPoster / persian | Improved event date card, Persian headline hierarchy, venue readability, and CTA treatment; production-ready. |
| `en_sale_modern_gradient` | sale / english | Improved sale headline scale, discount badge, CTA contrast, and readable English thumbnail; production-ready. |
| `en_story_quote` | story / english | Improved high-contrast story quote panel, readable headline, and clearer footer line; production-ready. |
| `fa_sale_bold` | sale / persian | Improved Persian sale hierarchy, discount badge, CTA contrast, and readable font-loaded thumbnail; production-ready. |
| `en_sale_bold` | sale / english | Improved sale type scale, discount badge, footer CTA hierarchy, and readable English thumbnail; production-ready. |
| `en_birthday_confetti` | greeting / english | Improved greeting card hierarchy, stronger confetti balance, readable script/display pairing, and soft color harmony; production-ready. |
| `fa_story_quote` | story / persian | Improved high-contrast Persian quote panel, readable footer line, and stronger story thumbnail; production-ready. |
| `fa_announcement` | social / persian | Improved Persian announcement hierarchy, stronger dark-blue contrast, readable support text, and clearer thumbnail; production-ready. |
| `en_quote_editorial` | quote / english | Improved editorial quote typography, attribution rule, readable serif headline, and font-loaded thumbnail; production-ready. |
| `fa_quote_editorial` | quote / persian | Improved Persian editorial quote typography, attribution spacing, warm palette, and readable thumbnail; production-ready. |
| `en_story_motivation` | story / english | Improved story-scale headline, top/bottom band contrast, footer readability, and thumbnail hierarchy; production-ready. |
| `en_event_market` | event / english | Improved event detail scale, CTA pill clarity, spacing, and font-loaded story thumbnail; production-ready. |
| `fa_event` | event / persian | Improved Persian event detail scale, CTA contrast, title spacing, and readable story thumbnail; production-ready. |
| `fa_food_menu` | food / persian | Improved menu card breathing room, Persian list readability, footer scale, and compact-card hierarchy; production-ready. |
| `en_food_coffee` | food / english | Improved coffee offer hierarchy, footer readability, cup balance, and thumbnail clarity; production-ready. |
| `en_sale_flash` | sale / english | Improved sale type spacing, promo-code strip contrast, simplified glyph use, and compact thumbnail readability; production-ready. |
| `en_event_concert` | event / english | Improved concert detail text, title spacing, venue contrast, and scan hierarchy; production-ready. |
| `fa_food_coffee` | food / persian | Improved Persian offer spacing, footer scale, cup balance, and thumbnail readability; production-ready. |
| `fa_concert` | event / persian | Improved Persian concert hierarchy, event details, venue contrast, and story thumbnail readability; production-ready. |
| `fa_insta_story_v1` | instagramStory / persian | Improved sparse story composition with a readable focal card, stronger hierarchy, and clear Persian text; production-ready. |
| `fa_promo_sale_v1` | promotionalPoster / persian | Improved Persian sale percentage, CTA scale, headline spacing, and readable poster thumbnail; production-ready. |
| `en_yt_question_v1` | youtubeThumbnail / english | Improved YouTube subtitle scale, question-disc balance, and landscape thumbnail readability; production-ready. |
| `fa_insta_story_announcement_v1` | instagramStory / persian | Improved Persian announcement detail text, card spacing, and compact story readability; production-ready. |
| `fa_insta_story_frame_v1` | instagramStory / persian | Improved frame focal element, Persian label scale, and placeholder-card hierarchy; production-ready. |
| `fa_promo_launch_v1` | promotionalPoster / persian | Improved product placeholder clarity, Persian headline scale, CTA size, and poster hierarchy; production-ready. |
| `fa_insta_story_minimal_v1` | instagramStory / persian | Improved minimal story focal balance, footer treatment, and Persian text hierarchy; production-ready. |
| `fa_story_today` | instagramStory / persian | Decision: redesigned now. Rebuilt as a Persian daily story starter with readable headline, photo-card focal point, warm palette, and font-loaded thumbnail; production-ready. |
| `en_youtube_watch_this` | youtubeThumbnail / english | Decision: redesigned now. Rebuilt as a high-contrast YouTube starter with stronger hook hierarchy, play focal point, CTA strip, and readable thumbnail; production-ready. |
| `fa_story_product_reveal` | instagramStory / persian | New Batch 1 Persian product reveal story with warm premium palette, editable product copy, strong hierarchy, and rendered thumbnail; production-ready. |
| `fa_story_daily_offer` | instagramStory / persian | New Batch 1 Persian daily offer story with high-contrast badge, offer card, editable CTA, and readable thumbnail; production-ready. |
| `fa_story_cafe_mood` | instagramStory / persian | New Batch 1 Persian cafe story with warm cafe palette, cup motif, editable headline, and attractive vertical thumbnail; production-ready. |
| `fa_story_course_signup` | story / persian | New Batch 1 Persian education story with course list structure, registration CTA, and clean mobile hierarchy; production-ready. |
| `fa_post_brand_intro` | social / persian | New Batch 1 Persian square brand intro post with logo mark, editorial spacing, and editable business copy; production-ready. |
| `fa_post_minimal_tip` | social / persian | New Batch 1 Persian educational/tip post with clean card layout, strong numbering, and save-oriented CTA; production-ready. |
| `fa_post_event_countdown` | event / persian | New Batch 1 Persian event countdown post with clear date/urgency hierarchy and high-contrast thumbnail; production-ready. |
| `fa_post_culture_seasonal` | greeting / persian | New Batch 1 Persian cultural/seasonal post with tasteful ornamental layout and editable greeting copy; production-ready. |
| `fa_sale_luxury_drop` | sale / persian | New Batch 1 Persian premium sale poster with luxury dark palette, discount card, CTA, and polished vertical thumbnail; production-ready. |
| `fa_sale_market_weekend` | sale / persian | New Batch 1 Persian market sale poster with weekend coupon treatment and strong retail readability; production-ready. |
| `fa_promo_restaurant_special` | promotionalPoster / persian | New Batch 1 Persian restaurant special poster with plate motif, chef offer hierarchy, and editable order copy; production-ready. |
| `fa_promo_course_launch` | promotionalPoster / persian | New Batch 1 Persian course launch poster with module list cards, registration CTA, and clean educational hierarchy; production-ready. |
| `fa_poetry_nastaliq_evening` | poetryPost / persian | New Batch 1 Persian Nastaliq evening poetry card with calm literary palette and editable verse/author layers; production-ready. |
| `fa_quote_modern_dark` | quote / persian | New Batch 1 Persian modern dark quote card with bold contrast, accent rail, and editable quote/author copy; production-ready. |
| `fa_poetry_gallery_card` | poetryPost / persian | New Batch 1 Persian gallery-style poetry card with image placeholder, soft palette, and rendered Persian typography; production-ready. |
| `en_yt_ai_tools_2026` | youtubeThumbnail / english | New Batch 1 English YouTube thumbnail with tech palette, bold title, chip focal point, and strong compact readability; production-ready. |
| `en_yt_before_after_design` | youtubeThumbnail / english | New Batch 1 English before/after YouTube thumbnail with clear comparison panels, arrow focal point, and readable title; production-ready. |
| `en_social_launch_checklist` | social / english | New Batch 1 English launch checklist post with clean card hierarchy, checklist rows, and professional social thumbnail; production-ready. |
| `fa_business_recruitment_story` | business / persian | New Batch 2 Persian recruitment story with clear hiring hierarchy, role list, editable CTA, and readable vertical thumbnail; production-ready. |
| `fa_business_agency_intro` | business / persian | New Batch 2 Persian agency intro post with premium dark card, service chips, and strong brand/service copy; production-ready. |
| `fa_business_service_offer` | business / persian | New Batch 2 Persian service offer poster with price band, consulting CTA, and polished business palette; production-ready. |
| `fa_business_job_fair` | event / persian | New Batch 2 Persian job fair event poster with date badge, interview details, and strong event hierarchy; production-ready. |
| `fa_business_team_hiring` | business / persian | New Batch 2 Persian team hiring story with bold headline, team motif, and readable resume CTA; production-ready. |
| `fa_business_consulting_post` | business / persian | New Batch 2 Persian consulting post with split layout, question framing, and booking CTA; production-ready. |
| `fa_food_modern_menu_board` | food / persian | New Batch 2 Persian menu board with readable menu rows, price column, and restaurant CTA; production-ready. |
| `fa_food_delivery_story` | food / persian | New Batch 2 Persian food delivery story with strong delivery offer, plate motif, and mobile-readable CTA; production-ready. |
| `fa_cafe_breakfast_special` | food / persian | New Batch 2 Persian cafe breakfast offer with warm palette, coffee motif, and editable combo pricing; production-ready. |
| `fa_restaurant_live_night` | event / persian | New Batch 2 Persian restaurant live-night event poster with stage motif, date pill, and readable event copy; production-ready. |
| `fa_food_dessert_launch` | food / persian | New Batch 2 Persian dessert launch post with soft product reveal composition and editable launch copy; production-ready. |
| `fa_edu_webinar_story` | story / persian | New Batch 2 Persian webinar story with screen focal point, course headline, date CTA, and strong education hierarchy; production-ready. |
| `fa_edu_workshop_poster` | promotionalPoster / persian | New Batch 2 Persian workshop poster with session details, registration CTA, and clean course layout; production-ready. |
| `fa_edu_exam_prep_post` | social / persian | New Batch 2 Persian exam-prep post with numbered tip structure and readable educational checklist; production-ready. |
| `fa_edu_course_tip_carousel` | social / persian | New Batch 2 Persian course/tip carousel cover with strong slide structure and editable teaching copy; production-ready. |
| `fa_season_nowruz_greeting` | greeting / persian | New Batch 2 Persian Nowruz greeting with tasteful cultural ornaments and editable brand signature; production-ready. |
| `fa_season_iftar_invite` | event / persian | New Batch 2 Persian Iftar invite with formal event card, date pill, and warm seasonal tone; production-ready. |
| `fa_cultural_book_night` | event / persian | New Batch 2 Persian book-night event poster with book motif, cultural event hierarchy, and readable copy; production-ready. |
| `en_business_product_update` | business / english | New Batch 2 English product update post with dashboard motif, clear announcement hierarchy, and professional thumbnail; production-ready. |
| `en_webinar_growth_masterclass` | event / english | New Batch 2 English webinar poster with screen focal point, strong title, and date CTA; production-ready. |
| `en_event_startup_pitch` | event / english | New Batch 2 English startup pitch poster with dark stage palette, application CTA, and clear event framing; production-ready. |
| `en_social_case_study` | social / english | New Batch 2 English case-study social post with metric badge, result-led headline, and business proof layout; production-ready. |
| `en_yt_explainer_framework` | youtubeThumbnail / english | New Batch 2 English YouTube explainer thumbnail with bold title, diagram focal point, and compact high-contrast readability; production-ready. |
| `fa_story_fashion_drop` | instagramStory / persian | New Batch 3 Persian fashion drop story with premium product focal area, strong Persian headline, CTA, and readable vertical thumbnail; production-ready. |
| `fa_story_beauty_booking` | instagramStory / persian | New Batch 3 Persian beauty booking story with salon-friendly palette, appointment CTA, and clear service hierarchy; production-ready. |
| `fa_story_health_clinic_tip` | instagramStory / persian | New Batch 3 Persian health/clinic tip story with medical icon focal point, clean educational copy, and readable CTA; production-ready. |
| `fa_post_product_carousel_cover` | social / persian | New Batch 3 Persian product carousel cover with editable product benefit headline, page indicator, and tightened thumbnail composition; production-ready. |
| `fa_post_service_announcement` | social / persian | New Batch 3 Persian service announcement post with premium icon block, launch copy, and strong business CTA; production-ready. |
| `fa_post_personal_brand_quote` | quote / persian | New Batch 3 Persian personal brand quote post with editorial card, accent rail, and editable attribution/handle; production-ready. |
| `fa_sale_retail_clearance` | sale / persian | New Batch 3 Persian retail clearance poster with discount badge, coupon strip, and high-contrast sale CTA; production-ready. |
| `fa_promo_clinic_checkup` | promotionalPoster / persian | New Batch 3 Persian clinic checkup promo with clean healthcare palette, service headline, and booking CTA; production-ready. |
| `fa_promo_travel_tour` | promotionalPoster / persian | New Batch 3 Persian travel tour poster with landscape motif, weekend headline, and readable reservation CTA; production-ready. |
| `fa_sale_beauty_package` | sale / persian | New Batch 3 Persian beauty package sale with soft salon palette, package offer band, and editable booking CTA; production-ready. |
| `fa_promo_app_launch` | promotionalPoster / persian | New Batch 3 Persian app launch poster with phone focal point, bold launch headline, and download CTA; production-ready. |
| `fa_poetry_black_gold_nastaliq` | poetryPost / persian | New Batch 3 Persian black/gold Nastaliq poem card with premium frame, readable verse, and literary tone; production-ready. |
| `fa_quote_editorial_magazine` | quote / persian | New Batch 3 Persian editorial magazine quote poster with image band, label treatment, and strong quote hierarchy; production-ready. |
| `fa_poetry_photo_frame_premium` | poetryPost / persian | New Batch 3 Persian premium photo poetry poster with warm image placeholder, poem card, and rendered Persian typography; production-ready. |
| `fa_quote_literary_column` | quote / persian | New Batch 3 Persian literary column quote post with article-like layout, CTA, and compact readability; production-ready. |
| `fa_event_gallery_opening` | event / persian | New Batch 3 Persian gallery opening poster with art focal area, event hierarchy, and premium dark palette; production-ready. |
| `fa_business_service_launch_story` | business / persian | New Batch 3 Persian service launch story with launch motif, bold headline, and early-access CTA; production-ready. |
| `fa_event_workshop_announcement` | event / persian | New Batch 3 Persian workshop announcement poster with clear date/location blocks and professional course hierarchy; production-ready. |
| `en_yt_tutorial_blueprint` | youtubeThumbnail / english | New Batch 3 English tutorial blueprint thumbnail with bold hook, step-card focal point, and high-contrast compact readability; production-ready. |
| `en_yt_reaction_hot_take` | youtubeThumbnail / english | New Batch 3 English reaction/hot-take thumbnail with strong headline, subject card, and clear commentary label; production-ready. |
| `en_yt_podcast_interview` | youtubeThumbnail / english | New Batch 3 English podcast interview thumbnail with host/guest focal shapes, episode badge, and readable headline; production-ready. |
| `en_social_business_announcement` | business / english | New Batch 3 English premium business announcement post with professional card layout, clear offer headline, and CTA; production-ready. |

## Needs Minor Polish

| Template | Category / language | Quality notes |
| --- | --- | --- |
| None | - | No production-facing migrated templates remain in this group after Template Minor Polish Cleanup. |

## Needs Major Polish

| Template | Category / language | Quality notes |
| --- | --- | --- |
| None | - | No production-facing migrated templates remain in this group after Polish Batch 3. |

## Should Be Redesigned Later

| Template | Category / language | Quality notes |
| --- | --- | --- |
| None | - | No templates remain in this group after Redesign Later Decision. |
