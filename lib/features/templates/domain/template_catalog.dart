import 'package:flutter/painting.dart';

import '../../editor/engine/core/editor_document.dart';
import '../../editor/engine/core/editor_layer.dart';
import '../../editor/engine/core/layer_transform.dart';
import '../../editor/engine/modules/shape/shape_layer.dart';
import '../../editor/engine/modules/text/text_layer.dart';
import 'template.dart';
import 'template_tokens.dart';

/// Deprecated legacy Dart template catalog.
///
/// JSON asset templates listed in `assets/templates/manifest.json` are now the
/// production source of truth. This catalog is retained temporarily for
/// explicit migration/test audit coverage and legacy fallback fixtures. Normal
/// runtime providers and UI should not read it.
///
/// Do not add new templates here. Add or update JSON asset templates instead,
/// then remove this catalog in a later cleanup phase once tests no longer
/// depend on it.
class TemplateCatalog {
  TemplateCatalog._();

  /// Legacy master list. Order is preserved for fallback and migration-audit
  /// comparisons only; production ordering comes from the JSON asset manifest.
  static final List<Template> all = <Template>[
    // ───────── English ─────────
    Template(
      id: 'en_quote_minimal',
      name: 'Minimal quote',
      category: TemplateCategory.quote,
      language: TemplateLanguage.english,
      build: _enQuoteMinimal,
    ),
    Template(
      id: 'en_sale_bold',
      name: 'Bold sale',
      category: TemplateCategory.sale,
      language: TemplateLanguage.english,
      build: _enSaleBold,
    ),
    Template(
      id: 'en_story_quote',
      name: 'Story quote',
      category: TemplateCategory.story,
      language: TemplateLanguage.english,
      build: _enStoryQuote,
    ),
    Template(
      id: 'en_birthday_confetti',
      name: 'Birthday confetti',
      category: TemplateCategory.greeting,
      language: TemplateLanguage.english,
      build: _enBirthday,
    ),
    Template(
      id: 'en_announcement',
      name: 'Announcement',
      category: TemplateCategory.social,
      language: TemplateLanguage.english,
      build: _enAnnouncement,
    ),
    Template(
      id: 'en_event_market',
      name: 'Event market',
      category: TemplateCategory.event,
      language: TemplateLanguage.english,
      build: _enStoryEvent,
    ),
    Template(
      id: 'en_quote_editorial',
      name: 'Editorial quote',
      category: TemplateCategory.quote,
      language: TemplateLanguage.english,
      build: _enQuoteEditorial,
    ),
    Template(
      id: 'en_motivation_sunrise',
      name: 'Sunrise motivation',
      category: TemplateCategory.motivational,
      language: TemplateLanguage.english,
      build: _enMotivationSunrise,
    ),
    Template(
      id: 'en_business_card_post',
      name: 'Now hiring',
      category: TemplateCategory.business,
      language: TemplateLanguage.english,
      build: _enNowHiring,
    ),
    Template(
      id: 'en_food_menu',
      name: 'Daily menu',
      category: TemplateCategory.food,
      language: TemplateLanguage.english,
      build: _enDailyMenu,
    ),
    Template(
      id: 'en_food_coffee',
      name: 'Coffee promo',
      category: TemplateCategory.food,
      language: TemplateLanguage.english,
      build: _enCoffeePromo,
    ),
    Template(
      id: 'en_sale_flash',
      name: 'Flash sale',
      category: TemplateCategory.sale,
      language: TemplateLanguage.english,
      build: _enFlashSale,
    ),
    Template(
      id: 'en_story_motivation',
      name: 'Story motivation',
      category: TemplateCategory.story,
      language: TemplateLanguage.english,
      build: _enStoryMotivation,
    ),
    Template(
      id: 'en_greeting_thanks',
      name: 'Thank you',
      category: TemplateCategory.greeting,
      language: TemplateLanguage.english,
      build: _enThankYou,
    ),
    Template(
      id: 'en_business_quote',
      name: 'Founder quote',
      category: TemplateCategory.business,
      language: TemplateLanguage.english,
      build: _enFounderQuote,
    ),
    Template(
      id: 'en_event_concert',
      name: 'Concert poster',
      category: TemplateCategory.event,
      language: TemplateLanguage.english,
      build: _enConcert,
    ),

    // ───────── Persian / فارسی ─────────
    Template(
      id: 'fa_quote_minimal',
      name: 'نقل قول مینیمال',
      category: TemplateCategory.quote,
      language: TemplateLanguage.persian,
      build: _faQuoteMinimal,
    ),
    Template(
      id: 'fa_sale_bold',
      name: 'حراج ویژه',
      category: TemplateCategory.sale,
      language: TemplateLanguage.persian,
      build: _faSaleBold,
    ),
    Template(
      id: 'fa_story_quote',
      name: 'استوری انگیزشی',
      category: TemplateCategory.story,
      language: TemplateLanguage.persian,
      build: _faStoryQuote,
    ),
    Template(
      id: 'fa_birthday',
      name: 'تولدت مبارک',
      category: TemplateCategory.greeting,
      language: TemplateLanguage.persian,
      build: _faBirthday,
    ),
    Template(
      id: 'fa_announcement',
      name: 'اطلاعیه',
      category: TemplateCategory.social,
      language: TemplateLanguage.persian,
      build: _faAnnouncement,
    ),
    Template(
      id: 'fa_event',
      name: 'رویداد جمعه',
      category: TemplateCategory.event,
      language: TemplateLanguage.persian,
      build: _faEvent,
    ),
    Template(
      id: 'fa_quote_editorial',
      name: 'نقل قول مجله‌ای',
      category: TemplateCategory.quote,
      language: TemplateLanguage.persian,
      build: _faQuoteEditorial,
    ),
    Template(
      id: 'fa_motivation_sunrise',
      name: 'صبحت بخیر',
      category: TemplateCategory.motivational,
      language: TemplateLanguage.persian,
      build: _faMotivation,
    ),
    Template(
      id: 'fa_business_hiring',
      name: 'استخدام',
      category: TemplateCategory.business,
      language: TemplateLanguage.persian,
      build: _faHiring,
    ),
    Template(
      id: 'fa_food_menu',
      name: 'منوی روز',
      category: TemplateCategory.food,
      language: TemplateLanguage.persian,
      build: _faMenu,
    ),
    Template(
      id: 'fa_food_coffee',
      name: 'کافه گرم',
      category: TemplateCategory.food,
      language: TemplateLanguage.persian,
      build: _faCoffee,
    ),
    Template(
      id: 'fa_sale_flash',
      name: 'فروش لحظه‌ای',
      category: TemplateCategory.sale,
      language: TemplateLanguage.persian,
      build: _faFlashSale,
    ),
    Template(
      id: 'fa_thanks',
      name: 'سپاسگزارم',
      category: TemplateCategory.greeting,
      language: TemplateLanguage.persian,
      build: _faThanks,
    ),
    Template(
      id: 'fa_concert',
      name: 'پوستر کنسرت',
      category: TemplateCategory.event,
      language: TemplateLanguage.persian,
      build: _faConcert,
    ),

    // ───────── Sprint 2 — Gradient Engine POC ─────────
    // Three hand-tuned templates that exercise every variant of the
    // sealed [BackgroundFill] (linear canvas, radial canvas, gradient
    // shape fill) so the gradient pipeline gets real-world stress
    // before being exposed in the Style panel.
    Template(
      id: 'en_sale_modern_gradient',
      name: 'Modern sale',
      category: TemplateCategory.sale,
      language: TemplateLanguage.english,
      build: _enSaleModernGradient,
    ),
    Template(
      id: 'en_quote_editorial_gradient',
      name: 'Editorial gradient',
      category: TemplateCategory.quote,
      language: TemplateLanguage.english,
      build: _enQuoteEditorialGradient,
    ),
    Template(
      id: 'fa_story_warm_pastel',
      name: 'استوری پاستلی',
      category: TemplateCategory.story,
      language: TemplateLanguage.persian,
      build: _faStoryWarmPastel,
    ),

    // ───────── Phase A — Focused Use-Case Templates ─────────
    Template(
      id: 'fa_insta_story_v1',
      name: 'داستان امروز',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      build: _faInstaStoryV1,
    ),
    Template(
      id: 'en_yt_thumb_v1',
      name: 'Watch this',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      build: _enYoutubeThumbnailV1,
    ),
    Template(
      id: 'fa_poetry_v1',
      name: 'پست شاعرانه',
      category: TemplateCategory.poetryPost,
      language: TemplateLanguage.persian,
      build: _faPoetryV1,
    ),
    Template(
      id: 'fa_promo_v1',
      name: 'پوستر تبلیغاتی',
      category: TemplateCategory.promotionalPoster,
      language: TemplateLanguage.persian,
      build: _faPromoV1,
    ),

    // ───────── Phase C — Focused Category Depth ─────────
    Template(
      id: 'fa_insta_story_bold_word_v1',
      name: 'کلمه جسور',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      build: _faInstaStoryBoldWordV1,
    ),
    Template(
      id: 'fa_insta_story_announcement_v1',
      name: 'اعلان شبانه',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      build: _faInstaStoryAnnouncementV1,
    ),
    Template(
      id: 'fa_insta_story_frame_v1',
      name: 'قاب تصویر',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      build: _faInstaStoryFrameV1,
    ),
    Template(
      id: 'fa_insta_story_minimal_v1',
      name: 'استوری خلوت',
      category: TemplateCategory.instagramStory,
      language: TemplateLanguage.persian,
      build: _faInstaStoryMinimalV1,
    ),
    Template(
      id: 'en_yt_question_v1',
      name: 'Question hook',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      build: _enYoutubeQuestionV1,
    ),
    Template(
      id: 'en_yt_list_v1',
      name: 'Five things',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      build: _enYoutubeListV1,
    ),
    Template(
      id: 'en_yt_reaction_v1',
      name: 'Reaction shock',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      build: _enYoutubeReactionV1,
    ),
    Template(
      id: 'en_yt_tutorial_v1',
      name: 'Fast tutorial',
      category: TemplateCategory.youtubeThumbnail,
      language: TemplateLanguage.english,
      build: _enYoutubeTutorialV1,
    ),
    Template(
      id: 'fa_poetry_minimal_v1',
      name: 'شعر مینیمال',
      category: TemplateCategory.poetryPost,
      language: TemplateLanguage.persian,
      build: _faPoetryMinimalV1,
    ),
    Template(
      id: 'fa_poetry_traditional_v1',
      name: 'قاب کلاسیک',
      category: TemplateCategory.poetryPost,
      language: TemplateLanguage.persian,
      build: _faPoetryTraditionalV1,
    ),
    Template(
      id: 'fa_poetry_overlay_v1',
      name: 'شعر روی تصویر',
      category: TemplateCategory.poetryPost,
      language: TemplateLanguage.persian,
      build: _faPoetryOverlayV1,
    ),
    Template(
      id: 'fa_promo_sale_v1',
      name: 'حراج پررنگ',
      category: TemplateCategory.promotionalPoster,
      language: TemplateLanguage.persian,
      build: _faPromoSaleV1,
    ),
    Template(
      id: 'fa_promo_event_v1',
      name: 'اعلان رویداد',
      category: TemplateCategory.promotionalPoster,
      language: TemplateLanguage.persian,
      build: _faPromoEventV1,
    ),
    Template(
      id: 'fa_promo_launch_v1',
      name: 'معرفی محصول',
      category: TemplateCategory.promotionalPoster,
      language: TemplateLanguage.persian,
      build: _faPromoLaunchV1,
    ),
  ];

  /// Convenience accessor — templates filtered by language. Used by
  /// the browse screen to render two scroll sections.
  static List<Template> byLanguage(TemplateLanguage lang) =>
      all.where((t) => t.language == lang).toList(growable: false);
}

// ─────────────────────────── helpers ────────────────────────────────

/// Square 1080×1080 — the workhorse social size.
const Size _square = Size(1080, 1080);

/// 9:16 1080×1920 — Instagram / TikTok story.
const Size _story = Size(1080, 1920);

/// 16:9 1280×720 — YouTube thumbnail.
const Size _youtubeThumbnail = Size(1280, 720);

/// 4:5 1080×1350 — promotional feed poster.
const Size _portraitPoster = Size(1080, 1350);

// Common Latin display family pairings, by intent.
const String _enDisplayBold = 'Hanken_Grotesk';
const String _enDisplaySerif = 'Raleway';
const String _enDisplayScript = 'Dancing_Script';
const String _enMono = 'Chivo_Mono';
const String _enRetro = 'Bungee_Shade';

// Persian family pairings — chosen so the headline / body split
// reads as crisp + warm. All shipped under assets/fonts/farsi.
const String _faDisplayHeadline = 'BTitrBd';
const String _faDisplayCasual = 'Lalezar';
const String _faBody = 'Vazir_Regular';
const String _faAccentScript = 'Eliya_Regular';

LayerTransform _box({
  required double x,
  required double y,
  required double w,
  required double h,
}) => LayerTransform(position: Offset(x, y), size: Size(w, h));

TextLayer _text({
  required String id,
  required String content,
  required LayerTransform transform,
  Color color = const Color(0xFFFFFFFF),
  FontWeight weight = FontWeight.w700,
  double size = 96,
  TextAlign align = TextAlign.center,
  Color? background,
  double backgroundRadius = 0,
  Color? shadow,
  String? fontFamily,
  double lineHeight = 1.2,
}) {
  return TextLayer(
    id: id,
    transform: transform,
    content: content,
    style: TextStyleSpec(
      fontFamily: fontFamily,
      fontSize: size,
      color: color,
      fontWeight: weight,
      lineHeight: lineHeight,
      alignment: align,
      backgroundColor: background,
      backgroundRadius: backgroundRadius,
      shadowColor: shadow,
    ),
  );
}

ShapeLayer _shape({
  required String id,
  required ShapeKind kind,
  required LayerTransform transform,
  Color fill = const Color(0xFFFFFFFF),
  double cornerRadius = 0,
}) {
  return ShapeLayer(
    id: id,
    transform: transform,
    kind: kind,
    fillColor: fill,
    cornerRadius: cornerRadius,
  );
}

EditorDocument _doc({
  required Size canvas,
  required Color background,
  required List<EditorLayer> layers,
}) {
  return EditorDocument(
    layers: layers,
    width: canvas.width,
    height: canvas.height,
    backgroundColor: background,
  );
}

// ═══════════════════════ ENGLISH TEMPLATES ══════════════════════════

EditorDocument _enQuoteMinimal() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFF7F4EE),
    layers: [
      _shape(
        id: 'rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 120, y: 360, w: 80, h: 6),
        fill: const Color(0xFF1F2937),
      ),
      _text(
        id: 'quote',
        content: '“Done is better\nthan perfect.”',
        transform: _box(x: 96, y: 400, w: 888, h: 360),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 110,
        align: TextAlign.left,
        fontFamily: _enDisplaySerif,
      ),
      _text(
        id: 'attrib',
        content: '— Sheryl Sandberg',
        transform: _box(x: 96, y: 800, w: 888, h: 60),
        color: const Color(0xFF6B7280),
        weight: FontWeight.w500,
        size: 36,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enSaleBold() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFACC15),
    layers: [
      _shape(
        id: 'tag',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 80, y: 120, w: 280, h: 88),
        fill: const Color(0xFF111827),
        cornerRadius: 44,
      ),
      _text(
        id: 'tag-text',
        content: 'LIMITED',
        transform: _box(x: 80, y: 138, w: 280, h: 56),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 40,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'headline',
        content: 'BIG\nSALE',
        transform: _box(x: 80, y: 280, w: 920, h: 560),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 320,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'sub',
        content: 'Up to 50% off — this weekend only',
        transform: _box(x: 80, y: 900, w: 920, h: 60),
        color: const Color(0xFF1F2937),
        weight: FontWeight.w500,
        size: 36,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enBirthday() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFCE7F3),
    layers: [
      _shape(
        id: 'dot1',
        kind: ShapeKind.circle,
        transform: _box(x: 120, y: 120, w: 60, h: 60),
        fill: const Color(0xFFEC4899),
      ),
      _shape(
        id: 'dot2',
        kind: ShapeKind.circle,
        transform: _box(x: 880, y: 880, w: 80, h: 80),
        fill: const Color(0xFFA855F7),
      ),
      _shape(
        id: 'dot3',
        kind: ShapeKind.circle,
        transform: _box(x: 880, y: 160, w: 40, h: 40),
        fill: const Color(0xFFF59E0B),
      ),
      _shape(
        id: 'star1',
        kind: ShapeKind.star,
        transform: _box(x: 80, y: 880, w: 90, h: 90),
        fill: const Color(0xFFF59E0B),
      ),
      _text(
        id: 'happy',
        content: 'happy',
        transform: _box(x: 80, y: 360, w: 920, h: 200),
        color: const Color(0xFFDB2777),
        weight: FontWeight.w400,
        size: 180,
        fontFamily: _enDisplayScript,
      ),
      _text(
        id: 'birthday',
        content: 'BIRTHDAY',
        transform: _box(x: 80, y: 560, w: 920, h: 200),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 180,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'name',
        content: 'to YOU',
        transform: _box(x: 80, y: 760, w: 920, h: 120),
        color: const Color(0xFF6B21A8),
        weight: FontWeight.w600,
        size: 84,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enStoryQuote() {
  return _doc(
    canvas: _story,
    background: const Color(0xFF0F172A),
    layers: [
      _shape(
        id: 'accent',
        kind: ShapeKind.circle,
        transform: _box(x: -200, y: 1300, w: 900, h: 900),
        fill: const Color(0xFF6366F1),
      ),
      _shape(
        id: 'accent2',
        kind: ShapeKind.circle,
        transform: _box(x: 700, y: -200, w: 600, h: 600),
        fill: const Color(0xFFEC4899),
      ),
      _text(
        id: 'kicker',
        content: 'TODAY',
        transform: _box(x: 80, y: 700, w: 920, h: 60),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w700,
        size: 40,
        align: TextAlign.left,
        fontFamily: _enMono,
      ),
      _text(
        id: 'quote',
        content: 'Make\nsomething\nyou love.',
        transform: _box(x: 80, y: 780, w: 920, h: 540),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w800,
        size: 140,
        align: TextAlign.left,
        shadow: const Color(0x66000000),
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enStoryEvent() {
  return _doc(
    canvas: _story,
    background: const Color(0xFF111827),
    layers: [
      _shape(
        id: 'frame',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 80, y: 360, w: 920, h: 1200),
        fill: const Color(0xFFF59E0B),
        cornerRadius: 32,
      ),
      _text(
        id: 'date',
        content: 'FRI · JUN 14',
        transform: _box(x: 80, y: 440, w: 920, h: 60),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 40,
        fontFamily: _enMono,
      ),
      _text(
        id: 'title',
        content: 'SUMMER\nMARKET',
        transform: _box(x: 80, y: 560, w: 920, h: 520),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 200,
        fontFamily: _enDisplayBold,
      ),
      _shape(
        id: 'divider',
        kind: ShapeKind.rectangle,
        transform: _box(x: 460, y: 1120, w: 160, h: 4),
        fill: const Color(0xFF111827),
      ),
      _text(
        id: 'where',
        content: '11 AM – 6 PM\nDolores Park',
        transform: _box(x: 80, y: 1180, w: 920, h: 200),
        color: const Color(0xFF1F2937),
        weight: FontWeight.w600,
        size: 56,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'cta',
        content: 'tap for tickets →',
        transform: _box(x: 80, y: 1460, w: 920, h: 60),
        color: const Color(0xFF111827),
        weight: FontWeight.w700,
        size: 36,
        fontFamily: _enMono,
      ),
    ],
  );
}

EditorDocument _enAnnouncement() {
  return _doc(
    canvas: _square,
    background: const Color(0xFF111827),
    layers: [
      _text(
        id: 'kicker',
        content: 'NEW',
        transform: _box(x: 80, y: 200, w: 920, h: 80),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 56,
        align: TextAlign.left,
        fontFamily: _enMono,
      ),
      _text(
        id: 'title',
        content: "We're\nlaunching\nsoon.",
        transform: _box(x: 80, y: 300, w: 920, h: 600),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 160,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
      _shape(
        id: 'underline',
        kind: ShapeKind.rectangle,
        transform: _box(x: 80, y: 920, w: 200, h: 8),
        fill: const Color(0xFFFACC15),
      ),
      _text(
        id: 'sub',
        content: 'Join the waitlist on our site.',
        transform: _box(x: 80, y: 950, w: 920, h: 60),
        color: const Color(0xFFCBD5E1),
        weight: FontWeight.w500,
        size: 36,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enQuoteEditorial() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFFFFFF),
    layers: [
      _shape(
        id: 'sidebar',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 0, w: 80, h: 1080),
        fill: const Color(0xFF111827),
      ),
      _text(
        id: 'kicker',
        content: 'ESSAY · 02',
        transform: _box(x: 140, y: 160, w: 800, h: 60),
        color: const Color(0xFF6B7280),
        weight: FontWeight.w700,
        size: 32,
        align: TextAlign.left,
        fontFamily: _enMono,
      ),
      _text(
        id: 'quote',
        content:
            '“The future is\nalready here\n— it\'s just not\nevenly distributed.”',
        transform: _box(x: 140, y: 260, w: 860, h: 600),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 92,
        align: TextAlign.left,
        fontFamily: _enDisplaySerif,
      ),
      _text(
        id: 'attrib',
        content: 'WILLIAM GIBSON',
        transform: _box(x: 140, y: 900, w: 860, h: 60),
        color: const Color(0xFF111827),
        weight: FontWeight.w700,
        size: 36,
        align: TextAlign.left,
        fontFamily: _enMono,
      ),
    ],
  );
}

EditorDocument _enMotivationSunrise() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFFEDD5),
    layers: [
      _shape(
        id: 'sun',
        kind: ShapeKind.circle,
        transform: _box(x: 240, y: 540, w: 600, h: 600),
        fill: const Color(0xFFFB923C),
      ),
      _shape(
        id: 'mound',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 880, w: 1080, h: 200),
        fill: const Color(0xFFEA580C),
      ),
      _text(
        id: 'kicker',
        content: 'GOOD MORNING',
        transform: _box(x: 80, y: 160, w: 920, h: 60),
        color: const Color(0xFF7C2D12),
        weight: FontWeight.w800,
        size: 40,
        fontFamily: _enMono,
      ),
      _text(
        id: 'title',
        content: 'rise & shine',
        transform: _box(x: 80, y: 260, w: 920, h: 220),
        color: const Color(0xFF7C2D12),
        weight: FontWeight.w400,
        size: 200,
        fontFamily: _enDisplayScript,
      ),
    ],
  );
}

EditorDocument _enNowHiring() {
  return _doc(
    canvas: _square,
    background: const Color(0xFF1E293B),
    layers: [
      _shape(
        id: 'badge',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 80, y: 120, w: 360, h: 88),
        fill: const Color(0xFF22C55E),
        cornerRadius: 44,
      ),
      _text(
        id: 'badge-text',
        content: 'WE\'RE HIRING',
        transform: _box(x: 80, y: 138, w: 360, h: 56),
        color: const Color(0xFF052E16),
        weight: FontWeight.w800,
        size: 36,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'title',
        content: 'Senior\nFlutter\nEngineer',
        transform: _box(x: 80, y: 280, w: 920, h: 540),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 160,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
      _shape(
        id: 'divider',
        kind: ShapeKind.rectangle,
        transform: _box(x: 80, y: 880, w: 100, h: 4),
        fill: const Color(0xFF22C55E),
      ),
      _text(
        id: 'meta',
        content: 'Remote · Full-time · Apply by Jun 30',
        transform: _box(x: 80, y: 910, w: 920, h: 60),
        color: const Color(0xFFCBD5E1),
        weight: FontWeight.w500,
        size: 32,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enDailyMenu() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFFF7ED),
    layers: [
      _shape(
        id: 'plate',
        kind: ShapeKind.circle,
        transform: _box(x: 660, y: 80, w: 360, h: 360),
        fill: const Color(0xFFFED7AA),
      ),
      _shape(
        id: 'yolk',
        kind: ShapeKind.circle,
        transform: _box(x: 800, y: 220, w: 80, h: 80),
        fill: const Color(0xFFF59E0B),
      ),
      _text(
        id: 'kicker',
        content: 'TODAY\'S MENU',
        transform: _box(x: 60, y: 140, w: 600, h: 60),
        color: const Color(0xFF9A3412),
        weight: FontWeight.w800,
        size: 36,
        align: TextAlign.left,
        fontFamily: _enMono,
      ),
      _text(
        id: 'title',
        content: 'Brunch\nspecials',
        transform: _box(x: 60, y: 220, w: 600, h: 280),
        color: const Color(0xFF7C2D12),
        weight: FontWeight.w900,
        size: 120,
        align: TextAlign.left,
        fontFamily: _enDisplaySerif,
      ),
      _text(
        id: 'list',
        content:
            'Avocado toast — \$8\nButtermilk pancakes — \$10\nEggs benedict — \$12\nFrench press coffee — \$4',
        transform: _box(x: 60, y: 580, w: 960, h: 360),
        color: const Color(0xFF1F2937),
        weight: FontWeight.w500,
        size: 44,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'foot',
        content: 'served 9 am – 2 pm',
        transform: _box(x: 60, y: 980, w: 960, h: 50),
        color: const Color(0xFF9A3412),
        weight: FontWeight.w700,
        size: 30,
        align: TextAlign.left,
        fontFamily: _enMono,
      ),
    ],
  );
}

EditorDocument _enCoffeePromo() {
  return _doc(
    canvas: _square,
    background: const Color(0xFF3F2A1D),
    layers: [
      _shape(
        id: 'cup',
        kind: ShapeKind.circle,
        transform: _box(x: 140, y: 600, w: 360, h: 360),
        fill: const Color(0xFFE7C7A3),
      ),
      _shape(
        id: 'foam',
        kind: ShapeKind.circle,
        transform: _box(x: 200, y: 660, w: 240, h: 240),
        fill: const Color(0xFFFFFFFF),
      ),
      _text(
        id: 'kicker',
        content: 'BREW BAR',
        transform: _box(x: 80, y: 160, w: 920, h: 60),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 40,
        align: TextAlign.left,
        fontFamily: _enMono,
      ),
      _text(
        id: 'title',
        content: 'BUY 1\nGET 1\nFREE',
        transform: _box(x: 540, y: 260, w: 480, h: 600),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 180,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'sub',
        content: 'every Tuesday · 7–10 am',
        transform: _box(x: 80, y: 980, w: 920, h: 60),
        color: const Color(0xFFE7C7A3),
        weight: FontWeight.w600,
        size: 34,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enFlashSale() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFEF4444),
    layers: [
      _shape(
        id: 'bolt',
        kind: ShapeKind.diamond,
        transform: _box(x: 80, y: 80, w: 160, h: 160),
        fill: const Color(0xFFFACC15),
      ),
      _text(
        id: 'kicker',
        content: 'FLASH',
        transform: _box(x: 280, y: 140, w: 700, h: 60),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 60,
        align: TextAlign.left,
        fontFamily: _enRetro,
      ),
      _text(
        id: 'title',
        content: '24h\nONLY',
        transform: _box(x: 80, y: 320, w: 920, h: 480),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 280,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
      _shape(
        id: 'bar',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 80, y: 880, w: 920, h: 100),
        fill: const Color(0xFF111827),
        cornerRadius: 50,
      ),
      _text(
        id: 'sub',
        content: 'use code  ⚡  FLASH50',
        transform: _box(x: 80, y: 900, w: 920, h: 60),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 40,
        fontFamily: _enMono,
      ),
    ],
  );
}

EditorDocument _enStoryMotivation() {
  return _doc(
    canvas: _story,
    background: const Color(0xFFFFFFFF),
    layers: [
      _shape(
        id: 'top-band',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 0, w: 1080, h: 280),
        fill: const Color(0xFF22C55E),
      ),
      _shape(
        id: 'bot-band',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 1640, w: 1080, h: 280),
        fill: const Color(0xFF22C55E),
      ),
      _text(
        id: 'kicker',
        content: 'DAY 03',
        transform: _box(x: 80, y: 100, w: 920, h: 80),
        color: const Color(0xFFF0FDF4),
        weight: FontWeight.w800,
        size: 56,
        fontFamily: _enMono,
      ),
      _text(
        id: 'big',
        content: 'show\nup\nagain',
        transform: _box(x: 80, y: 540, w: 920, h: 900),
        color: const Color(0xFF052E16),
        weight: FontWeight.w900,
        size: 280,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'sub',
        content: 'small reps. big results.',
        transform: _box(x: 80, y: 1740, w: 920, h: 80),
        color: const Color(0xFFF0FDF4),
        weight: FontWeight.w700,
        size: 48,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enThankYou() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFFF1F2),
    layers: [
      _shape(
        id: 'heart',
        kind: ShapeKind.heart,
        transform: _box(x: 440, y: 140, w: 200, h: 200),
        fill: const Color(0xFFE11D48),
      ),
      _text(
        id: 'thank',
        content: 'thank',
        transform: _box(x: 80, y: 380, w: 920, h: 220),
        color: const Color(0xFF881337),
        weight: FontWeight.w400,
        size: 220,
        fontFamily: _enDisplayScript,
      ),
      _text(
        id: 'you',
        content: 'YOU',
        transform: _box(x: 80, y: 620, w: 920, h: 240),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 260,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'sub',
        content: 'for being here',
        transform: _box(x: 80, y: 900, w: 920, h: 60),
        color: const Color(0xFF6B7280),
        weight: FontWeight.w500,
        size: 36,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enFounderQuote() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFE0F2FE),
    layers: [
      _shape(
        id: 'bubble',
        kind: ShapeKind.quoteBubble,
        transform: _box(x: 80, y: 220, w: 920, h: 560),
        fill: const Color(0xFFFFFFFF),
      ),
      _text(
        id: 'quote',
        content: '“Stay close\nto the customer.”',
        transform: _box(x: 140, y: 320, w: 800, h: 360),
        color: const Color(0xFF0C4A6E),
        weight: FontWeight.w800,
        size: 88,
        align: TextAlign.left,
        fontFamily: _enDisplaySerif,
      ),
      _shape(
        id: 'avatar',
        kind: ShapeKind.circle,
        transform: _box(x: 100, y: 840, w: 120, h: 120),
        fill: const Color(0xFF0EA5E9),
      ),
      _text(
        id: 'name',
        content: 'Mina Patel',
        transform: _box(x: 240, y: 860, w: 760, h: 50),
        color: const Color(0xFF0C4A6E),
        weight: FontWeight.w800,
        size: 38,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'role',
        content: 'Founder, Northwind',
        transform: _box(x: 240, y: 910, w: 760, h: 50),
        color: const Color(0xFF075985),
        weight: FontWeight.w500,
        size: 30,
        align: TextAlign.left,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

EditorDocument _enConcert() {
  return _doc(
    canvas: _story,
    background: const Color(0xFF18181B),
    layers: [
      _shape(
        id: 'spot1',
        kind: ShapeKind.circle,
        transform: _box(x: -300, y: -300, w: 800, h: 800),
        fill: const Color(0xFFD946EF),
      ),
      _shape(
        id: 'spot2',
        kind: ShapeKind.circle,
        transform: _box(x: 600, y: 1500, w: 800, h: 800),
        fill: const Color(0xFF06B6D4),
      ),
      _text(
        id: 'kicker',
        content: 'LIVE · ONE NIGHT',
        transform: _box(x: 60, y: 760, w: 960, h: 60),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 44,
        fontFamily: _enMono,
      ),
      _text(
        id: 'name',
        content: 'NEON\nWAVES',
        transform: _box(x: 60, y: 840, w: 960, h: 580),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 280,
        shadow: const Color(0x99000000),
        fontFamily: _enDisplayBold,
      ),
      _shape(
        id: 'rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 460, y: 1440, w: 160, h: 4),
        fill: const Color(0xFFFACC15),
      ),
      _text(
        id: 'date',
        content: 'SAT · OCT 12 · 9 PM',
        transform: _box(x: 60, y: 1500, w: 960, h: 60),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w800,
        size: 48,
        fontFamily: _enMono,
      ),
      _text(
        id: 'where',
        content: 'The Echo · Los Angeles',
        transform: _box(x: 60, y: 1580, w: 960, h: 60),
        color: const Color(0xFFE4E4E7),
        weight: FontWeight.w500,
        size: 36,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

// ═══════════════════════ PERSIAN TEMPLATES ══════════════════════════

EditorDocument _faQuoteMinimal() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFF7F4EE),
    layers: [
      _shape(
        id: 'rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 880, y: 360, w: 80, h: 6),
        fill: const Color(0xFF1F2937),
      ),
      _text(
        id: 'quote',
        content: '«آغاز کن،\nزیبایی در حرکت است.»',
        transform: _box(x: 96, y: 400, w: 888, h: 360),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 96,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'attrib',
        content: '— گمنام',
        transform: _box(x: 96, y: 800, w: 888, h: 60),
        color: const Color(0xFF6B7280),
        weight: FontWeight.w500,
        size: 36,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faSaleBold() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFACC15),
    layers: [
      _shape(
        id: 'tag',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 720, y: 120, w: 280, h: 88),
        fill: const Color(0xFF111827),
        cornerRadius: 44,
      ),
      _text(
        id: 'tag-text',
        content: 'محدود',
        transform: _box(x: 720, y: 138, w: 280, h: 56),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 44,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'headline',
        content: 'حراج\nبزرگ',
        transform: _box(x: 80, y: 280, w: 920, h: 560),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 280,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'sub',
        content: 'تا ۵۰٪ تخفیف — فقط آخر هفته',
        transform: _box(x: 80, y: 900, w: 920, h: 60),
        color: const Color(0xFF1F2937),
        weight: FontWeight.w500,
        size: 40,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faStoryQuote() {
  return _doc(
    canvas: _story,
    background: const Color(0xFF0F172A),
    layers: [
      _shape(
        id: 'accent',
        kind: ShapeKind.circle,
        transform: _box(x: -200, y: 1300, w: 900, h: 900),
        fill: const Color(0xFF6366F1),
      ),
      _shape(
        id: 'accent2',
        kind: ShapeKind.circle,
        transform: _box(x: 700, y: -200, w: 600, h: 600),
        fill: const Color(0xFFEC4899),
      ),
      _text(
        id: 'kicker',
        content: 'امروز',
        transform: _box(x: 80, y: 700, w: 920, h: 60),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w700,
        size: 44,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'quote',
        content: 'چیزی بساز\nکه دوستش داری.',
        transform: _box(x: 80, y: 780, w: 920, h: 540),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w800,
        size: 130,
        align: TextAlign.right,
        shadow: const Color(0x66000000),
        fontFamily: _faDisplayHeadline,
      ),
    ],
  );
}

EditorDocument _faBirthday() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFCE7F3),
    layers: [
      _shape(
        id: 'dot1',
        kind: ShapeKind.circle,
        transform: _box(x: 120, y: 120, w: 60, h: 60),
        fill: const Color(0xFFEC4899),
      ),
      _shape(
        id: 'dot2',
        kind: ShapeKind.circle,
        transform: _box(x: 880, y: 880, w: 80, h: 80),
        fill: const Color(0xFFA855F7),
      ),
      _shape(
        id: 'star1',
        kind: ShapeKind.star,
        transform: _box(x: 80, y: 880, w: 90, h: 90),
        fill: const Color(0xFFF59E0B),
      ),
      _shape(
        id: 'heart',
        kind: ShapeKind.heart,
        transform: _box(x: 880, y: 140, w: 80, h: 80),
        fill: const Color(0xFFEC4899),
      ),
      _text(
        id: 'tavalod',
        content: 'تولدت',
        transform: _box(x: 80, y: 380, w: 920, h: 220),
        color: const Color(0xFFDB2777),
        weight: FontWeight.w900,
        size: 220,
        fontFamily: _faDisplayCasual,
      ),
      _text(
        id: 'mobarak',
        content: 'مبارک',
        transform: _box(x: 80, y: 600, w: 920, h: 220),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 220,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'sub',
        content: 'بهترین‌ها برایت',
        transform: _box(x: 80, y: 840, w: 920, h: 80),
        color: const Color(0xFF6B21A8),
        weight: FontWeight.w600,
        size: 56,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faAnnouncement() {
  return _doc(
    canvas: _square,
    background: const Color(0xFF111827),
    layers: [
      _text(
        id: 'kicker',
        content: 'جدید',
        transform: _box(x: 80, y: 200, w: 920, h: 80),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 60,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'title',
        content: 'به‌زودی\nمی‌آییم.',
        transform: _box(x: 80, y: 300, w: 920, h: 600),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 200,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _shape(
        id: 'underline',
        kind: ShapeKind.rectangle,
        transform: _box(x: 800, y: 920, w: 200, h: 8),
        fill: const Color(0xFFFACC15),
      ),
      _text(
        id: 'sub',
        content: 'برای اطلاع بیشتر منتظر باشید',
        transform: _box(x: 80, y: 950, w: 920, h: 60),
        color: const Color(0xFFCBD5E1),
        weight: FontWeight.w500,
        size: 40,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faEvent() {
  return _doc(
    canvas: _story,
    background: const Color(0xFF111827),
    layers: [
      _shape(
        id: 'frame',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 80, y: 360, w: 920, h: 1200),
        fill: const Color(0xFFF59E0B),
        cornerRadius: 32,
      ),
      _text(
        id: 'date',
        content: 'جمعه ۲۴ خرداد',
        transform: _box(x: 80, y: 440, w: 920, h: 80),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 56,
        fontFamily: _faBody,
      ),
      _text(
        id: 'title',
        content: 'بازارچه\nتابستانی',
        transform: _box(x: 80, y: 580, w: 920, h: 520),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 200,
        fontFamily: _faDisplayHeadline,
      ),
      _shape(
        id: 'divider',
        kind: ShapeKind.rectangle,
        transform: _box(x: 460, y: 1140, w: 160, h: 4),
        fill: const Color(0xFF111827),
      ),
      _text(
        id: 'where',
        content: '۱۱ صبح تا ۶ عصر\nپارک ملت',
        transform: _box(x: 80, y: 1200, w: 920, h: 220),
        color: const Color(0xFF1F2937),
        weight: FontWeight.w600,
        size: 64,
        fontFamily: _faBody,
      ),
      _text(
        id: 'cta',
        content: '← ضربه بزن برای بلیت',
        transform: _box(x: 80, y: 1480, w: 920, h: 60),
        color: const Color(0xFF111827),
        weight: FontWeight.w700,
        size: 40,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faQuoteEditorial() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFFFFFF),
    layers: [
      _shape(
        id: 'sidebar',
        kind: ShapeKind.rectangle,
        transform: _box(x: 1000, y: 0, w: 80, h: 1080),
        fill: const Color(0xFF111827),
      ),
      _text(
        id: 'kicker',
        content: 'یادداشت ۰۲',
        transform: _box(x: 80, y: 160, w: 860, h: 60),
        color: const Color(0xFF6B7280),
        weight: FontWeight.w700,
        size: 36,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'quote',
        content: '«هر روز قدمی\nکوچک بردار،\nسال‌ها قله می‌سازند.»',
        transform: _box(x: 80, y: 260, w: 860, h: 600),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 86,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'attrib',
        content: 'سعدی شیرازی',
        transform: _box(x: 80, y: 900, w: 860, h: 60),
        color: const Color(0xFF111827),
        weight: FontWeight.w700,
        size: 40,
        align: TextAlign.right,
        fontFamily: _faAccentScript,
      ),
    ],
  );
}

EditorDocument _faMotivation() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFFEDD5),
    layers: [
      _shape(
        id: 'sun',
        kind: ShapeKind.circle,
        transform: _box(x: 240, y: 540, w: 600, h: 600),
        fill: const Color(0xFFFB923C),
      ),
      _shape(
        id: 'mound',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 880, w: 1080, h: 200),
        fill: const Color(0xFFEA580C),
      ),
      _text(
        id: 'kicker',
        content: 'صبح بخیر',
        transform: _box(x: 80, y: 160, w: 920, h: 80),
        color: const Color(0xFF7C2D12),
        weight: FontWeight.w800,
        size: 56,
        fontFamily: _faBody,
      ),
      _text(
        id: 'title',
        content: 'روز نو\nامید نو',
        transform: _box(x: 80, y: 260, w: 920, h: 320),
        color: const Color(0xFF7C2D12),
        weight: FontWeight.w900,
        size: 160,
        fontFamily: _faDisplayCasual,
      ),
    ],
  );
}

EditorDocument _faHiring() {
  return _doc(
    canvas: _square,
    background: const Color(0xFF1E293B),
    layers: [
      _shape(
        id: 'badge',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 640, y: 120, w: 360, h: 88),
        fill: const Color(0xFF22C55E),
        cornerRadius: 44,
      ),
      _text(
        id: 'badge-text',
        content: 'استخدام',
        transform: _box(x: 640, y: 138, w: 360, h: 56),
        color: const Color(0xFF052E16),
        weight: FontWeight.w800,
        size: 44,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'title',
        content: 'برنامه‌نویس\nارشد\nفلاتر',
        transform: _box(x: 80, y: 280, w: 920, h: 540),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 150,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _shape(
        id: 'divider',
        kind: ShapeKind.rectangle,
        transform: _box(x: 880, y: 880, w: 100, h: 4),
        fill: const Color(0xFF22C55E),
      ),
      _text(
        id: 'meta',
        content: 'دورکاری · تمام‌وقت · مهلت ۳۱ خرداد',
        transform: _box(x: 80, y: 910, w: 920, h: 60),
        color: const Color(0xFFCBD5E1),
        weight: FontWeight.w500,
        size: 36,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faMenu() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFFF7ED),
    layers: [
      _shape(
        id: 'plate',
        kind: ShapeKind.circle,
        transform: _box(x: 60, y: 80, w: 360, h: 360),
        fill: const Color(0xFFFED7AA),
      ),
      _shape(
        id: 'yolk',
        kind: ShapeKind.circle,
        transform: _box(x: 200, y: 220, w: 80, h: 80),
        fill: const Color(0xFFF59E0B),
      ),
      _text(
        id: 'kicker',
        content: 'منوی امروز',
        transform: _box(x: 440, y: 140, w: 580, h: 60),
        color: const Color(0xFF9A3412),
        weight: FontWeight.w800,
        size: 44,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'title',
        content: 'صبحانه\nویژه',
        transform: _box(x: 440, y: 220, w: 580, h: 300),
        color: const Color(0xFF7C2D12),
        weight: FontWeight.w900,
        size: 130,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'list',
        content:
            'نان و پنیر — ۸۰هزار\nاملت گوجه — ۱۲۰هزار\nعدسی گرم — ۹۰هزار\nچای دارچین — ۳۰هزار',
        transform: _box(x: 60, y: 580, w: 960, h: 360),
        color: const Color(0xFF1F2937),
        weight: FontWeight.w500,
        size: 48,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'foot',
        content: 'سرو از ۸ صبح تا ۱۲ ظهر',
        transform: _box(x: 60, y: 980, w: 960, h: 50),
        color: const Color(0xFF9A3412),
        weight: FontWeight.w700,
        size: 34,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faCoffee() {
  return _doc(
    canvas: _square,
    background: const Color(0xFF3F2A1D),
    layers: [
      _shape(
        id: 'cup',
        kind: ShapeKind.circle,
        transform: _box(x: 580, y: 600, w: 360, h: 360),
        fill: const Color(0xFFE7C7A3),
      ),
      _shape(
        id: 'foam',
        kind: ShapeKind.circle,
        transform: _box(x: 640, y: 660, w: 240, h: 240),
        fill: const Color(0xFFFFFFFF),
      ),
      _text(
        id: 'kicker',
        content: 'کافه گرم',
        transform: _box(x: 80, y: 160, w: 920, h: 60),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 48,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'title',
        content: 'یکی\nبخر،\nدومی\nمهمون!',
        transform: _box(x: 80, y: 260, w: 480, h: 700),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 140,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'sub',
        content: 'سه‌شنبه‌ها · ۷ تا ۱۰ صبح',
        transform: _box(x: 80, y: 980, w: 920, h: 60),
        color: const Color(0xFFE7C7A3),
        weight: FontWeight.w600,
        size: 38,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faFlashSale() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFEF4444),
    layers: [
      _shape(
        id: 'bolt',
        kind: ShapeKind.diamond,
        transform: _box(x: 840, y: 80, w: 160, h: 160),
        fill: const Color(0xFFFACC15),
      ),
      _text(
        id: 'kicker',
        content: 'فلاش',
        transform: _box(x: 80, y: 140, w: 740, h: 80),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 64,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'title',
        content: '۲۴ ساعت\nفقط',
        transform: _box(x: 80, y: 320, w: 920, h: 480),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 220,
        align: TextAlign.right,
        fontFamily: _faDisplayHeadline,
      ),
      _shape(
        id: 'bar',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 80, y: 880, w: 920, h: 100),
        fill: const Color(0xFF111827),
        cornerRadius: 50,
      ),
      _text(
        id: 'sub',
        content: 'کد:  ⚡  FLASH50',
        transform: _box(x: 80, y: 900, w: 920, h: 60),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 44,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faThanks() {
  return _doc(
    canvas: _square,
    background: const Color(0xFFFFF1F2),
    layers: [
      _shape(
        id: 'heart',
        kind: ShapeKind.heart,
        transform: _box(x: 440, y: 140, w: 200, h: 200),
        fill: const Color(0xFFE11D48),
      ),
      _text(
        id: 'thank',
        content: 'سپاس',
        transform: _box(x: 80, y: 380, w: 920, h: 240),
        color: const Color(0xFF881337),
        weight: FontWeight.w900,
        size: 240,
        fontFamily: _faAccentScript,
      ),
      _text(
        id: 'you',
        content: 'از تو',
        transform: _box(x: 80, y: 620, w: 920, h: 240),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 220,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'sub',
        content: 'که همراه ما هستی',
        transform: _box(x: 80, y: 900, w: 920, h: 60),
        color: const Color(0xFF6B7280),
        weight: FontWeight.w500,
        size: 40,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faConcert() {
  return _doc(
    canvas: _story,
    background: const Color(0xFF18181B),
    layers: [
      _shape(
        id: 'spot1',
        kind: ShapeKind.circle,
        transform: _box(x: -300, y: -300, w: 800, h: 800),
        fill: const Color(0xFFD946EF),
      ),
      _shape(
        id: 'spot2',
        kind: ShapeKind.circle,
        transform: _box(x: 600, y: 1500, w: 800, h: 800),
        fill: const Color(0xFF06B6D4),
      ),
      _text(
        id: 'kicker',
        content: 'اجرای زنده · یک شب فقط',
        transform: _box(x: 60, y: 760, w: 960, h: 80),
        color: const Color(0xFFFACC15),
        weight: FontWeight.w800,
        size: 50,
        fontFamily: _faBody,
      ),
      _text(
        id: 'name',
        content: 'موج\nنئون',
        transform: _box(x: 60, y: 860, w: 960, h: 580),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 260,
        shadow: const Color(0x99000000),
        fontFamily: _faDisplayHeadline,
      ),
      _shape(
        id: 'rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 460, y: 1460, w: 160, h: 4),
        fill: const Color(0xFFFACC15),
      ),
      _text(
        id: 'date',
        content: 'شنبه ۲۰ مهر · ساعت ۲۱',
        transform: _box(x: 60, y: 1520, w: 960, h: 60),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w800,
        size: 50,
        fontFamily: _faBody,
      ),
      _text(
        id: 'where',
        content: 'سالن میلاد · تهران',
        transform: _box(x: 60, y: 1600, w: 960, h: 60),
        color: const Color(0xFFE4E4E7),
        weight: FontWeight.w500,
        size: 40,
        fontFamily: _faBody,
      ),
    ],
  );
}

// ═════════════ SPRINT 2 — GRADIENT ENGINE POC TEMPLATES ═════════════
//
// These three templates are the first consumers of the new sealed
// [BackgroundFill] type. Together they cover:
//   * linear canvas gradient + gradient shape fills (Modern sale)
//   * radial canvas gradient (Editorial gradient)
//   * linear canvas gradient on a story aspect (Persian story)
// Adding a new fill variant to [BackgroundFill] will surface here
// (and in the renderer / codec switches) so we always have a real
// document exercising the latest engine surface.

EditorDocument _docFill({
  required Size canvas,
  required BackgroundFill background,
  required List<EditorLayer> layers,
}) {
  return EditorDocument(
    layers: layers,
    width: canvas.width,
    height: canvas.height,
    background: background,
  );
}

/// Square sale post on the violet→magenta [modernGradient] palette.
/// Linear canvas backdrop + a gradient pill shape — the only template
/// in the catalog that uses gradients on both the canvas and a layer.
EditorDocument _enSaleModernGradient() {
  return _docFill(
    canvas: _square,
    background: const LinearGradientBackground(
      startColor: Color(0xFF7C5CFF), // violet (modernGradient.background)
      endColor: Color(0xFFE85DDC), // magenta (modernGradient.accent)
      angleDegrees: 135, // top-left → bottom-right
    ),
    layers: [
      // Decorative bloom in the upper-right — radial gradient on a
      // circle exercises [ShapeLayer.fill] for radial fills.
      ShapeLayer(
        id: 'bloom',
        kind: ShapeKind.circle,
        transform: _box(x: 700, y: -160, w: 600, h: 600),
        fill: const RadialGradientBackground(
          centerColor: Color(0xCCFFFFFF),
          edgeColor: Color(0x00FFFFFF),
        ),
      ),
      // Tag pill — solid contrast badge over the violet field.
      _shape(
        id: 'tag',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 80, y: 120, w: 320, h: 88),
        fill: const Color(0xFF1F0E3D),
        cornerRadius: 44,
      ),
      _text(
        id: 'tag-text',
        content: 'NEW DROP',
        transform: _box(x: 80, y: 138, w: 320, h: 56),
        color: const Color(0xFFE85DDC),
        weight: FontWeight.w800,
        size: 38,
        fontFamily: _enDisplayBold,
      ),
      _text(
        id: 'headline',
        content: 'BIG\nSALE',
        transform: _box(x: 80, y: 280, w: 920, h: 560),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 320,
        align: TextAlign.left,
        shadow: const Color(0x44000000),
        fontFamily: _enDisplayBold,
      ),
      // Linear-gradient CTA bar — second exercise of [ShapeLayer.fill]
      // on a rectangle with a per-shape angle distinct from the canvas.
      ShapeLayer(
        id: 'cta',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 80, y: 880, w: 920, h: 100),
        cornerRadius: 50,
        fill: const LinearGradientBackground(
          startColor: Color(0xFFE85DDC),
          endColor: Color(0xFF7C5CFF),
          angleDegrees: 90, // left → right
        ),
      ),
      _text(
        id: 'cta-text',
        content: 'Shop the drop · 50% off',
        transform: _box(x: 80, y: 904, w: 920, h: 60),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w700,
        size: 40,
        fontFamily: _enDisplayBold,
      ),
    ],
  );
}

/// Square editorial pull-quote on the [editorialMuted] palette with a
/// soft off-centre radial wash on the canvas — gives the page a
/// printed-paper warmth without relying on a raster texture asset.
EditorDocument _enQuoteEditorialGradient() {
  return _docFill(
    canvas: _square,
    background: const RadialGradientBackground(
      // Brighter cream at top-left fading to the darker neutral —
      // mimics a soft window light raking across the page.
      centerColor: Color(0xFFFAF6EE),
      edgeColor: Color(0xFFDDD7CC), // editorialMuted.surface
      focalPoint: Alignment(-0.4, -0.6),
      radius: 1.2,
    ),
    layers: [
      // Terracotta navy callout sidebar — solid colour from the
      // editorialMuted palette so the gradient doesn't dominate.
      _shape(
        id: 'sidebar',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 0, w: 80, h: 1080),
        fill: const Color(0xFF1F3A5F), // editorialMuted.surfaceAlt
      ),
      _text(
        id: 'kicker',
        content: 'ESSAY · 04',
        transform: _box(x: 140, y: 160, w: 800, h: 60),
        color: const Color(0xFFC45D3A), // editorialMuted.accent
        weight: FontWeight.w700,
        size: 32,
        align: TextAlign.left,
        fontFamily: _enMono,
      ),
      _text(
        id: 'quote',
        content: '“We shape our\ntools, and\nthereafter our\ntools shape us.”',
        transform: _box(x: 140, y: 260, w: 860, h: 600),
        color: const Color(0xFF2C2C2C), // editorialMuted.primary
        weight: FontWeight.w800,
        size: 92,
        align: TextAlign.left,
        fontFamily: _enDisplaySerif,
      ),
      _text(
        id: 'attrib',
        content: 'MARSHALL McLUHAN',
        transform: _box(x: 140, y: 900, w: 860, h: 60),
        color: const Color(0xFF6B6359), // editorialMuted.secondary
        weight: FontWeight.w700,
        size: 36,
        align: TextAlign.left,
        fontFamily: _enMono,
      ),
    ],
  );
}

/// Persian story (1080×1920) on the [warmPastel] palette with a soft
/// vertical gradient — cream at the top fading to blush at the
/// bottom. The canvas gradient and a gradient surface card together
/// exercise the linear-gradient renderer at the story aspect ratio.
EditorDocument _faStoryWarmPastel() {
  return _docFill(
    canvas: _story,
    background: const LinearGradientBackground(
      startColor: Color(0xFFFAF3E7), // warmPastel.background — cream
      endColor: Color(0xFFF5C7C7), // warmPastel.surface     — blush
      angleDegrees: 180, // top → bottom
    ),
    layers: [
      // Sage accent bar (RTL: anchored to the right side).
      _shape(
        id: 'bar',
        kind: ShapeKind.rectangle,
        transform: _box(x: 1000, y: 0, w: 80, h: 1920),
        fill: const Color(0xFFA8B89C), // warmPastel.surfaceAlt — sage
      ),
      // Soft gradient card behind the headline so the text has a
      // calm reading surface against the canvas gradient.
      ShapeLayer(
        id: 'card',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 80, y: 540, w: 840, h: 840),
        cornerRadius: 56,
        fill: const LinearGradientBackground(
          startColor: Color(0xFFFFFFFF),
          endColor: Color(0xFFFAF3E7),
          angleDegrees: 200, // gentle diagonal top → bottom-left
        ),
      ),
      _text(
        id: 'kicker',
        content: 'صبح بخیر',
        transform: _box(x: 80, y: 600, w: 840, h: 80),
        color: const Color(0xFF8C7B6E), // warmPastel.secondary
        weight: FontWeight.w700,
        size: 56,
        fontFamily: _faAccentScript,
      ),
      _text(
        id: 'headline',
        content: 'هر روز\nیک شروع\nتازه است',
        transform: _box(x: 80, y: 720, w: 840, h: 540),
        color: const Color(0xFF2D2D2D), // warmPastel.primary
        weight: FontWeight.w900,
        size: 140,
        fontFamily: _faDisplayHeadline,
      ),
      _text(
        id: 'caption',
        content: 'با لبخند آغاز کن',
        transform: _box(x: 80, y: 1280, w: 840, h: 80),
        color: const Color(0xFFD89A9A), // warmPastel.accent — dusty rose
        weight: FontWeight.w700,
        size: 56,
        fontFamily: _faBody,
      ),
      // Three accent dots tying back to the cream/sage/rose palette
      // so the lower third feels balanced.
      _shape(
        id: 'dot1',
        kind: ShapeKind.circle,
        transform: _box(x: 400, y: 1500, w: 60, h: 60),
        fill: const Color(0xFFD89A9A),
      ),
      _shape(
        id: 'dot2',
        kind: ShapeKind.circle,
        transform: _box(x: 490, y: 1500, w: 60, h: 60),
        fill: const Color(0xFFA8B89C),
      ),
      _shape(
        id: 'dot3',
        kind: ShapeKind.circle,
        transform: _box(x: 580, y: 1500, w: 60, h: 60),
        fill: const Color(0xFFF5C7C7),
      ),
    ],
  );
}

// ═════════ PHASE A — FOCUSED USE-CASE SAMPLE TEMPLATES ═════════════

EditorDocument _faInstaStoryV1() {
  const palette = warmPastel;
  return _docFill(
    canvas: _story,
    background: LinearGradientBackground(
      startColor: palette.surface,
      endColor: palette.background,
      angleDegrees: 180,
    ),
    layers: [
      ShapeLayer(
        id: 'lower-right-accent',
        kind: ShapeKind.circle,
        transform: _box(x: 700, y: 1370, w: 620, h: 620),
        fill: const RadialGradientBackground(
          centerColor: Color(0xEED89A9A),
          edgeColor: Color(0x00D89A9A),
          focalPoint: Alignment(-0.35, -0.35),
          radius: 0.9,
        ),
      ),
      _text(
        id: 'headline',
        content: 'داستان امروز',
        transform: _box(x: 100, y: 260, w: 880, h: 180),
        color: palette.primary,
        weight: FontWeight.w800,
        size: 128,
        align: TextAlign.right,
        fontFamily: _faBody,
        lineHeight: 1.05,
      ),
      _text(
        id: 'subtext',
        content: 'اینجا کلیک کن',
        transform: _box(x: 100, y: 455, w: 880, h: 90),
        color: palette.secondary,
        weight: FontWeight.w500,
        size: 48,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _enYoutubeThumbnailV1() {
  const palette = boldHighContrast;
  return _docFill(
    canvas: _youtubeThumbnail,
    background: LinearGradientBackground(
      startColor: palette.surfaceAlt,
      endColor: palette.background,
      angleDegrees: 110,
    ),
    layers: [
      _shape(
        id: 'accent-bar',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 0, w: 34, h: 720),
        fill: palette.accent,
      ),
      _text(
        id: 'headline',
        content: 'WATCH\nTHIS',
        transform: _box(x: 88, y: 112, w: 600, h: 330),
        color: palette.primary,
        weight: FontWeight.w900,
        size: 140,
        align: TextAlign.left,
        shadow: const Color(0x99000000),
        fontFamily: boldDisplay.bodyFont,
        lineHeight: 0.9,
      ),
      _text(
        id: 'subtitle',
        content: "before it's too late",
        transform: _box(x: 92, y: 472, w: 560, h: 70),
        color: palette.accent,
        weight: FontWeight.w500,
        size: 52,
        align: TextAlign.left,
        fontFamily: boldDisplay.bodyFont,
      ),
    ],
  );
}

EditorDocument _faPoetryV1() {
  final gold = vintageFaded.accent;
  return _docFill(
    canvas: _square,
    background: const SolidBackground(color: Color(0xFFF5EFE6)),
    layers: [
      _shape(
        id: 'frame-top',
        kind: ShapeKind.rectangle,
        transform: _box(x: 170, y: 170, w: 740, h: 3),
        fill: gold,
      ),
      _shape(
        id: 'frame-bottom',
        kind: ShapeKind.rectangle,
        transform: _box(x: 170, y: 907, w: 740, h: 3),
        fill: gold,
      ),
      _shape(
        id: 'frame-left',
        kind: ShapeKind.rectangle,
        transform: _box(x: 170, y: 170, w: 3, h: 740),
        fill: gold,
      ),
      _shape(
        id: 'frame-right',
        kind: ShapeKind.rectangle,
        transform: _box(x: 907, y: 170, w: 3, h: 740),
        fill: gold,
      ),
      _shape(
        id: 'corner-tl-h',
        kind: ShapeKind.rectangle,
        transform: _box(x: 120, y: 220, w: 150, h: 4),
        fill: gold,
      ),
      _shape(
        id: 'corner-tl-v',
        kind: ShapeKind.rectangle,
        transform: _box(x: 220, y: 120, w: 4, h: 150),
        fill: gold,
      ),
      _shape(
        id: 'corner-br-h',
        kind: ShapeKind.rectangle,
        transform: _box(x: 810, y: 856, w: 150, h: 4),
        fill: gold,
      ),
      _shape(
        id: 'corner-br-v',
        kind: ShapeKind.rectangle,
        transform: _box(x: 856, y: 810, w: 4, h: 150),
        fill: gold,
      ),
      _text(
        id: 'verse',
        content: 'هر که آمد عمارتی نو ساخت\nرفت و منزل به دیگری پرداخت',
        transform: _box(x: 170, y: 402, w: 740, h: 190),
        color: editorialMuted.primary,
        weight: FontWeight.w400,
        size: 64,
        align: TextAlign.center,
        fontFamily: _faBody,
        lineHeight: 1.5,
      ),
      _text(
        id: 'author',
        content: '— سعدی',
        transform: _box(x: 170, y: 690, w: 740, h: 58),
        color: editorialMuted.secondary,
        weight: FontWeight.w400,
        size: 32,
        align: TextAlign.center,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faPromoV1() {
  const crimson = Color(0xFFE63946);
  return _docFill(
    canvas: _portraitPoster,
    background: const LinearGradientBackground(
      startColor: Color(0xFF101827),
      endColor: Color(0xFF05070D),
      angleDegrees: 150,
    ),
    layers: [
      ShapeLayer(
        id: 'diagonal-accent',
        kind: ShapeKind.rectangle,
        transform: const LayerTransform(
          position: Offset(670, -140),
          size: Size(230, 1640),
          rotation: -0.36,
        ),
        fillColor: crimson,
        fillOpacity: 0.9,
      ),
      _text(
        id: 'label',
        content: 'تخفیف ویژه',
        transform: _box(x: 120, y: 170, w: 840, h: 70),
        color: const Color(0xFFFFD60A),
        weight: FontWeight.w500,
        size: 36,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'hero',
        content: '۵۰٪ تخفیف',
        transform: _box(x: 120, y: 365, w: 840, h: 245),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 180,
        align: TextAlign.right,
        shadow: const Color(0x99000000),
        fontFamily: _faDisplayCasual,
        lineHeight: 0.95,
      ),
      _text(
        id: 'subtext',
        content: 'فقط تا پایان هفته',
        transform: _box(x: 120, y: 650, w: 840, h: 90),
        color: const Color(0xFFE5E7EB),
        weight: FontWeight.w500,
        size: 48,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _shape(
        id: 'cta-bg',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 120, y: 1040, w: 420, h: 112),
        fill: crimson,
        cornerRadius: 56,
      ),
      _text(
        id: 'cta-text',
        content: 'خرید کنید',
        transform: _box(x: 120, y: 1062, w: 420, h: 72),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w700,
        size: 52,
        align: TextAlign.center,
        fontFamily: _faBody,
      ),
    ],
  );
}

// ═════════ PHASE C — FOCUSED CATEGORY DEPTH TEMPLATES ══════════════

EditorDocument _faInstaStoryBoldWordV1() {
  return _docFill(
    canvas: _story,
    background: const LinearGradientBackground(
      startColor: Color(0xFF2D1B4E),
      endColor: Color(0xFF7C5CFF),
      angleDegrees: 180,
    ),
    layers: [
      ShapeLayer(
        id: 'magenta-bloom',
        kind: ShapeKind.circle,
        transform: _box(x: -260, y: -220, w: 720, h: 720),
        fill: const RadialGradientBackground(
          centerColor: Color(0xDDE85DDC),
          edgeColor: Color(0x00E85DDC),
          radius: 0.85,
        ),
      ),
      _shape(
        id: 'baseline-rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 700, y: 1112, w: 240, h: 10),
        fill: const Color(0xFFFFD60A),
      ),
      _text(
        id: 'word',
        content: 'جرئت',
        transform: _box(x: 110, y: 710, w: 860, h: 310),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 245,
        align: TextAlign.right,
        shadow: const Color(0x66000000),
        fontFamily: _faBody,
        lineHeight: 0.95,
      ),
      _text(
        id: 'caption',
        content: 'همین امروز شروع کن',
        transform: _box(x: 120, y: 1055, w: 820, h: 80),
        color: const Color(0xFFE8DFFF),
        weight: FontWeight.w500,
        size: 46,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faInstaStoryAnnouncementV1() {
  return _docFill(
    canvas: _story,
    background: const LinearGradientBackground(
      startColor: Color(0xFF111827),
      endColor: Color(0xFF030712),
      angleDegrees: 165,
    ),
    layers: [
      _shape(
        id: 'top-pill',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 650, y: 270, w: 300, h: 82),
        fill: const Color(0xFFFFD60A),
        cornerRadius: 41,
      ),
      _text(
        id: 'pill-text',
        content: 'اعلان',
        transform: _box(x: 650, y: 286, w: 300, h: 52),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 36,
        align: TextAlign.center,
        fontFamily: _faBody,
      ),
      _shape(
        id: 'card',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 90, y: 560, w: 900, h: 620),
        fill: const Color(0xFF1F2937),
        cornerRadius: 48,
      ),
      _text(
        id: 'headline',
        content: 'امشب ساعت ۹\nخبر مهمی داریم',
        transform: _box(x: 150, y: 675, w: 780, h: 245),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w700,
        size: 74,
        align: TextAlign.right,
        fontFamily: _faBody,
        lineHeight: 1.25,
      ),
      _text(
        id: 'subtext',
        content: 'منتظر بمان',
        transform: _box(x: 150, y: 970, w: 780, h: 80),
        color: const Color(0xFFFFD60A),
        weight: FontWeight.w500,
        size: 44,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _shape(
        id: 'bottom-rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 150, y: 1096, w: 780, h: 2),
        fill: const Color(0x44FFFFFF),
      ),
    ],
  );
}

EditorDocument _faInstaStoryFrameV1() {
  return _docFill(
    canvas: _story,
    background: const SolidBackground(color: Color(0xFFF5EFE6)),
    layers: [
      _shape(
        id: 'photo-frame',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 100, y: 320, w: 880, h: 1120),
        fill: const Color(0xFFE8D5B0),
        cornerRadius: 56,
      ),
      ShapeLayer(
        id: 'photo-wash',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 140, y: 360, w: 800, h: 1040),
        cornerRadius: 42,
        fill: const LinearGradientBackground(
          startColor: Color(0xFFA8B89C),
          endColor: Color(0xFFF5C7C7),
          angleDegrees: 135,
        ),
      ),
      _shape(
        id: 'frame-top',
        kind: ShapeKind.rectangle,
        transform: _box(x: 180, y: 430, w: 720, h: 5),
        fill: const Color(0xFFFFFFFF),
      ),
      _shape(
        id: 'frame-bottom',
        kind: ShapeKind.rectangle,
        transform: _box(x: 180, y: 1325, w: 720, h: 5),
        fill: const Color(0xFFFFFFFF),
      ),
      _shape(
        id: 'frame-left',
        kind: ShapeKind.rectangle,
        transform: _box(x: 180, y: 430, w: 5, h: 900),
        fill: const Color(0xFFFFFFFF),
      ),
      _shape(
        id: 'frame-right',
        kind: ShapeKind.rectangle,
        transform: _box(x: 895, y: 430, w: 5, h: 900),
        fill: const Color(0xFFFFFFFF),
      ),
      _text(
        id: 'title',
        content: 'قاب امروز',
        transform: _box(x: 120, y: 1530, w: 840, h: 90),
        color: const Color(0xFF3D2A1F),
        weight: FontWeight.w800,
        size: 58,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'caption',
        content: 'تصویرت را اینجا بگذار',
        transform: _box(x: 120, y: 1628, w: 840, h: 70),
        color: const Color(0xFF8B6F47),
        weight: FontWeight.w500,
        size: 38,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faInstaStoryMinimalV1() {
  return _docFill(
    canvas: _story,
    background: const SolidBackground(color: Color(0xFFFAF7F1)),
    layers: [
      _shape(
        id: 'tiny-rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 820, y: 310, w: 120, h: 4),
        fill: const Color(0xFFC45D3A),
      ),
      _text(
        id: 'headline',
        content: 'یادداشت کوتاه',
        transform: _box(x: 120, y: 340, w: 820, h: 82),
        color: const Color(0xFF2C2C2C),
        weight: FontWeight.w600,
        size: 52,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'caption',
        content: 'برای امروز',
        transform: _box(x: 120, y: 430, w: 820, h: 56),
        color: const Color(0xFF6B6359),
        weight: FontWeight.w400,
        size: 32,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _shape(
        id: 'bottom-dot',
        kind: ShapeKind.circle,
        transform: _box(x: 506, y: 1510, w: 68, h: 68),
        fill: const Color(0xFFE8D5B0),
      ),
    ],
  );
}

EditorDocument _enYoutubeQuestionV1() {
  return _docFill(
    canvas: _youtubeThumbnail,
    background: const LinearGradientBackground(
      startColor: Color(0xFF0F172A),
      endColor: Color(0xFF1E3A8A),
      angleDegrees: 90,
    ),
    layers: [
      _shape(
        id: 'question-disc',
        kind: ShapeKind.circle,
        transform: _box(x: 875, y: 95, w: 300, h: 300),
        fill: const Color(0xFFFFD60A),
      ),
      _text(
        id: 'question-mark',
        content: '?',
        transform: _box(x: 875, y: 118, w: 300, h: 260),
        color: const Color(0xFF0F172A),
        weight: FontWeight.w900,
        size: 210,
        fontFamily: boldDisplay.bodyFont,
        lineHeight: 0.95,
      ),
      _text(
        id: 'headline',
        content: 'WHY DOES\nTHIS HAPPEN?',
        transform: _box(x: 70, y: 105, w: 720, h: 290),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 98,
        align: TextAlign.left,
        shadow: const Color(0x99000000),
        fontFamily: boldDisplay.bodyFont,
        lineHeight: 0.95,
      ),
      _text(
        id: 'subtitle',
        content: 'the answer is weird',
        transform: _box(x: 76, y: 430, w: 590, h: 64),
        color: const Color(0xFFFFD60A),
        weight: FontWeight.w600,
        size: 46,
        align: TextAlign.left,
        fontFamily: boldDisplay.bodyFont,
      ),
    ],
  );
}

EditorDocument _enYoutubeListV1() {
  return _docFill(
    canvas: _youtubeThumbnail,
    background: const SolidBackground(color: Color(0xFF111827)),
    layers: [
      _shape(
        id: 'number-box',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 70, y: 92, w: 230, h: 230),
        fill: const Color(0xFFFFD60A),
        cornerRadius: 36,
      ),
      _text(
        id: 'number',
        content: '5',
        transform: _box(x: 70, y: 92, w: 230, h: 210),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 180,
        fontFamily: boldDisplay.bodyFont,
        lineHeight: 0.95,
      ),
      _text(
        id: 'headline',
        content: 'THINGS\nYOU NEED',
        transform: _box(x: 330, y: 105, w: 620, h: 250),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 90,
        align: TextAlign.left,
        fontFamily: boldDisplay.bodyFont,
        lineHeight: 0.95,
      ),
      _shape(
        id: 'right-panel',
        kind: ShapeKind.rectangle,
        transform: _box(x: 1010, y: 0, w: 270, h: 720),
        fill: const Color(0xFFE63946),
      ),
      _text(
        id: 'badge',
        content: 'SAVE\nTHIS',
        transform: _box(x: 1035, y: 268, w: 220, h: 150),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 54,
        fontFamily: boldDisplay.bodyFont,
        lineHeight: 0.95,
      ),
      _text(
        id: 'subtitle',
        content: 'before your next upload',
        transform: _box(x: 76, y: 490, w: 760, h: 56),
        color: const Color(0xFF9CA3AF),
        weight: FontWeight.w500,
        size: 38,
        align: TextAlign.left,
        fontFamily: boldDisplay.bodyFont,
      ),
    ],
  );
}

EditorDocument _enYoutubeReactionV1() {
  return _docFill(
    canvas: _youtubeThumbnail,
    background: const LinearGradientBackground(
      startColor: Color(0xFFE63946),
      endColor: Color(0xFF0A0A0A),
      angleDegrees: 125,
    ),
    layers: [
      ShapeLayer(
        id: 'spotlight',
        kind: ShapeKind.circle,
        transform: _box(x: 760, y: 45, w: 420, h: 420),
        fill: const RadialGradientBackground(
          centerColor: Color(0x99FFFFFF),
          edgeColor: Color(0x00FFFFFF),
          radius: 0.85,
        ),
      ),
      _text(
        id: 'headline',
        content: 'NO\nWAY!',
        transform: _box(x: 72, y: 118, w: 590, h: 310),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 132,
        align: TextAlign.left,
        shadow: const Color(0xAA000000),
        fontFamily: boldDisplay.bodyFont,
        lineHeight: 0.9,
      ),
      _shape(
        id: 'face-placeholder',
        kind: ShapeKind.circle,
        transform: _box(x: 860, y: 155, w: 230, h: 230),
        fill: const Color(0xFFFFD60A),
      ),
      _text(
        id: 'face-mark',
        content: '!',
        transform: _box(x: 860, y: 168, w: 230, h: 190),
        color: const Color(0xFF111827),
        weight: FontWeight.w900,
        size: 150,
        fontFamily: boldDisplay.bodyFont,
        lineHeight: 0.9,
      ),
      _shape(
        id: 'subtitle-bg',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 72, y: 485, w: 480, h: 84),
        fill: const Color(0xFFFFD60A),
        cornerRadius: 42,
      ),
      _text(
        id: 'subtitle',
        content: 'watch the ending',
        transform: _box(x: 72, y: 503, w: 480, h: 54),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 38,
        fontFamily: boldDisplay.bodyFont,
      ),
    ],
  );
}

EditorDocument _enYoutubeTutorialV1() {
  return _docFill(
    canvas: _youtubeThumbnail,
    background: const LinearGradientBackground(
      startColor: Color(0xFF063B3F),
      endColor: Color(0xFF0F172A),
      angleDegrees: 135,
    ),
    layers: [
      _shape(
        id: 'top-bar',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 0, w: 1280, h: 22),
        fill: const Color(0xFF22C55E),
      ),
      _text(
        id: 'headline',
        content: 'HOW TO\nEDIT FAST',
        transform: _box(x: 76, y: 118, w: 720, h: 285),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 102,
        align: TextAlign.left,
        fontFamily: boldDisplay.bodyFont,
        lineHeight: 0.95,
      ),
      _shape(
        id: 'timer-pill',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 76, y: 450, w: 500, h: 92),
        fill: const Color(0xFF22C55E),
        cornerRadius: 46,
      ),
      _text(
        id: 'timer-text',
        content: 'IN 60 SECONDS',
        transform: _box(x: 76, y: 470, w: 500, h: 56),
        color: const Color(0xFF052E2B),
        weight: FontWeight.w900,
        size: 40,
        fontFamily: boldDisplay.bodyFont,
      ),
      _shape(
        id: 'preview-window',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 850, y: 150, w: 330, h: 260),
        fill: const Color(0xFF0B1220),
        cornerRadius: 28,
      ),
      _shape(
        id: 'play-button',
        kind: ShapeKind.triangle,
        transform: _box(x: 982, y: 240, w: 88, h: 88),
        fill: const Color(0xFF22C55E),
      ),
    ],
  );
}

EditorDocument _faPoetryMinimalV1() {
  return _docFill(
    canvas: _square,
    background: const SolidBackground(color: Color(0xFFF5F1EB)),
    layers: [
      _text(
        id: 'verse',
        content:
            'از صدای سخن عشق ندیدم خوشتر\nیادگاری که در این گنبد دوار بماند',
        transform: _box(x: 120, y: 410, w: 840, h: 180),
        color: const Color(0xFF3F3A35),
        weight: FontWeight.w400,
        size: 52,
        align: TextAlign.center,
        fontFamily: _faBody,
        lineHeight: 1.55,
      ),
      _text(
        id: 'author',
        content: '— حافظ',
        transform: _box(x: 120, y: 680, w: 840, h: 56),
        color: const Color(0xFF8C8175),
        weight: FontWeight.w400,
        size: 30,
        align: TextAlign.center,
        fontFamily: _faBody,
      ),
      _shape(
        id: 'quiet-dot',
        kind: ShapeKind.circle,
        transform: _box(x: 520, y: 808, w: 40, h: 40),
        fill: const Color(0xFFDDD7CC),
      ),
    ],
  );
}

EditorDocument _faPoetryTraditionalV1() {
  const gold = Color(0xFFD4A24C);
  return _docFill(
    canvas: _square,
    background: const LinearGradientBackground(
      startColor: Color(0xFFFAF3E7),
      endColor: Color(0xFFE8D5B0),
      angleDegrees: 180,
    ),
    layers: [
      _shape(
        id: 'outer-frame',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 120, y: 120, w: 840, h: 840),
        fill: const Color(0xFFF8EED8),
        cornerRadius: 42,
      ),
      _shape(
        id: 'left-rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 168, y: 190, w: 4, h: 700),
        fill: gold,
      ),
      _shape(
        id: 'right-rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 908, y: 190, w: 4, h: 700),
        fill: gold,
      ),
      _shape(
        id: 'top-rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 210, y: 226, w: 660, h: 4),
        fill: gold,
      ),
      _shape(
        id: 'bottom-rule',
        kind: ShapeKind.rectangle,
        transform: _box(x: 210, y: 850, w: 660, h: 4),
        fill: gold,
      ),
      _shape(
        id: 'ornament-top',
        kind: ShapeKind.diamond,
        transform: _box(x: 512, y: 190, w: 56, h: 56),
        fill: gold,
      ),
      _shape(
        id: 'ornament-bottom',
        kind: ShapeKind.diamond,
        transform: _box(x: 512, y: 826, w: 56, h: 56),
        fill: gold,
      ),
      _shape(
        id: 'ornament-left',
        kind: ShapeKind.diamond,
        transform: _box(x: 148, y: 512, w: 44, h: 44),
        fill: gold,
      ),
      _shape(
        id: 'ornament-right',
        kind: ShapeKind.diamond,
        transform: _box(x: 888, y: 512, w: 44, h: 44),
        fill: gold,
      ),
      _text(
        id: 'verse',
        content: 'بشنو از نی چون حکایت می‌کند\nاز جدایی‌ها شکایت می‌کند',
        transform: _box(x: 170, y: 420, w: 740, h: 190),
        color: const Color(0xFF3D2A1F),
        weight: FontWeight.w400,
        size: 58,
        align: TextAlign.center,
        fontFamily: _faBody,
        lineHeight: 1.48,
      ),
      _text(
        id: 'author',
        content: '— مولوی',
        transform: _box(x: 170, y: 690, w: 740, h: 56),
        color: const Color(0xFF8B6F47),
        weight: FontWeight.w400,
        size: 32,
        align: TextAlign.center,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faPoetryOverlayV1() {
  return _docFill(
    canvas: _square,
    background: const LinearGradientBackground(
      startColor: Color(0xFF3D2A1F),
      endColor: Color(0xFF0A0A0A),
      angleDegrees: 170,
    ),
    layers: [
      ShapeLayer(
        id: 'implied-light',
        kind: ShapeKind.circle,
        transform: _box(x: -170, y: -140, w: 620, h: 620),
        fill: const RadialGradientBackground(
          centerColor: Color(0x66D4A24C),
          edgeColor: Color(0x00D4A24C),
          radius: 0.9,
        ),
      ),
      _shape(
        id: 'overlay-panel',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 620, w: 1080, h: 460),
        fill: const Color(0x99000000),
      ),
      _text(
        id: 'verse',
        content: 'این قافله عمر عجب می‌گذرد\nدریاب دمی که با طرب می‌گذرد',
        transform: _box(x: 105, y: 700, w: 870, h: 170),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w500,
        size: 52,
        align: TextAlign.center,
        fontFamily: _faBody,
        lineHeight: 1.45,
      ),
      _text(
        id: 'author',
        content: '— خیام',
        transform: _box(x: 105, y: 905, w: 870, h: 52),
        color: const Color(0xFFD4A24C),
        weight: FontWeight.w400,
        size: 30,
        align: TextAlign.center,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faPromoSaleV1() {
  return _docFill(
    canvas: _portraitPoster,
    background: const SolidBackground(color: Color(0xFFFFD60A)),
    layers: [
      _shape(
        id: 'black-block',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 0, w: 1080, h: 600),
        fill: const Color(0xFF0A0A0A),
      ),
      _text(
        id: 'label',
        content: 'حراج آخر فصل',
        transform: _box(x: 110, y: 115, w: 860, h: 74),
        color: const Color(0xFFFFD60A),
        weight: FontWeight.w700,
        size: 42,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'percent',
        content: '۷۰٪',
        transform: _box(x: 80, y: 245, w: 920, h: 270),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w900,
        size: 220,
        align: TextAlign.center,
        shadow: const Color(0x99000000),
        fontFamily: _faBody,
        lineHeight: 0.95,
      ),
      _text(
        id: 'headline',
        content: 'تخفیف برای همه محصولات',
        transform: _box(x: 90, y: 720, w: 900, h: 92),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 58,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _shape(
        id: 'cta-bg',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 90, y: 1040, w: 470, h: 112),
        fill: const Color(0xFF0A0A0A),
        cornerRadius: 56,
      ),
      _text(
        id: 'cta',
        content: 'همین حالا',
        transform: _box(x: 90, y: 1062, w: 470, h: 72),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w700,
        size: 50,
        align: TextAlign.center,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faPromoEventV1() {
  return _docFill(
    canvas: _portraitPoster,
    background: const LinearGradientBackground(
      startColor: Color(0xFF1F3A5F),
      endColor: Color(0xFF05070D),
      angleDegrees: 180,
    ),
    layers: [
      _shape(
        id: 'date-card',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 660, y: 140, w: 280, h: 280),
        fill: const Color(0xFFFFFFFF),
        cornerRadius: 32,
      ),
      _text(
        id: 'day',
        content: '۲۴',
        transform: _box(x: 660, y: 174, w: 280, h: 120),
        color: const Color(0xFF1F3A5F),
        weight: FontWeight.w900,
        size: 92,
        fontFamily: _faBody,
        lineHeight: 0.95,
      ),
      _text(
        id: 'month',
        content: 'خرداد',
        transform: _box(x: 660, y: 300, w: 280, h: 60),
        color: const Color(0xFFC45D3A),
        weight: FontWeight.w700,
        size: 36,
        fontFamily: _faBody,
      ),
      _text(
        id: 'headline',
        content: 'همایش طراحی\nو خلاقیت',
        transform: _box(x: 90, y: 520, w: 900, h: 250),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w800,
        size: 82,
        align: TextAlign.right,
        fontFamily: _faBody,
        lineHeight: 1.18,
      ),
      _text(
        id: 'venue',
        content: 'سالن اصلی · ساعت ۱۸',
        transform: _box(x: 90, y: 825, w: 900, h: 72),
        color: const Color(0xFFE8D5B0),
        weight: FontWeight.w500,
        size: 42,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _shape(
        id: 'accent-line',
        kind: ShapeKind.rectangle,
        transform: _box(x: 90, y: 1010, w: 900, h: 5),
        fill: const Color(0xFFC45D3A),
      ),
      _text(
        id: 'footer',
        content: 'ثبت‌نام از امروز آغاز شد',
        transform: _box(x: 90, y: 1060, w: 900, h: 70),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w600,
        size: 42,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}

EditorDocument _faPromoLaunchV1() {
  return _docFill(
    canvas: _portraitPoster,
    background: const SolidBackground(color: Color(0xFFF5F1EB)),
    layers: [
      _shape(
        id: 'accent-block',
        kind: ShapeKind.rectangle,
        transform: _box(x: 0, y: 0, w: 1080, h: 470),
        fill: const Color(0xFF0F766E),
      ),
      _shape(
        id: 'product-placeholder',
        kind: ShapeKind.roundedRectangle,
        transform: _box(x: 190, y: 300, w: 700, h: 520),
        fill: const Color(0xFFFFFFFF),
        cornerRadius: 46,
      ),
      ShapeLayer(
        id: 'product-gradient',
        kind: ShapeKind.circle,
        transform: _box(x: 365, y: 388, w: 350, h: 350),
        fill: const RadialGradientBackground(
          centerColor: Color(0xFF22C55E),
          edgeColor: Color(0xFF0F766E),
          radius: 0.82,
        ),
      ),
      _text(
        id: 'label',
        content: 'معرفی محصول',
        transform: _box(x: 90, y: 95, w: 900, h: 70),
        color: const Color(0xFFFFFFFF),
        weight: FontWeight.w600,
        size: 40,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
      _text(
        id: 'headline',
        content: 'نسخه تازه\nاز راه رسید',
        transform: _box(x: 90, y: 875, w: 900, h: 210),
        color: const Color(0xFF111827),
        weight: FontWeight.w800,
        size: 74,
        align: TextAlign.right,
        fontFamily: _faBody,
        lineHeight: 1.2,
      ),
      _text(
        id: 'subtext',
        content: 'طراحی تمیز، امکانات بیشتر',
        transform: _box(x: 90, y: 1110, w: 900, h: 64),
        color: const Color(0xFF6B6359),
        weight: FontWeight.w500,
        size: 38,
        align: TextAlign.right,
        fontFamily: _faBody,
      ),
    ],
  );
}
