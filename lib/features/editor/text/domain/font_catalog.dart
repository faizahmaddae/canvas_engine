// Curated font catalog (assets/fonts).
//
// `script` separates the two writing systems we ship today
// (English/Latin and Farsi/Arabic). `category` is a finer-grained
// stylistic bucket used by the font picker to group families so a
// 60+ entry list stays scannable.

/// Writing system. Used as the top-level group in the picker and
/// as a hint for choosing a sensible default per language.
enum FontScript { latin, arabic }

/// Stylistic family. Buckets within a script.
///
/// * `sans`        — clean modern sans-serif (UI/body workhorses).
/// * `display`     — decorative, headline-only typefaces.
/// * `script`      — connected handwriting / brush.
/// * `mono`        — fixed-width.
/// * `traditional` — classical Naskh-style Arabic/Farsi text faces.
/// * `nastaliq`    — Persian calligraphic (Nastaliq, Shekaste, etc.).
enum FontCategory { sans, display, script, mono, traditional, nastaliq }

/// Single registered font family available in the editor.
/// `family` matches the value passed to `TextStyle.fontFamily`
/// and the entry registered in `pubspec.yaml`.
class FontEntry {
  const FontEntry({
    required this.family,
    required this.label,
    required this.script,
    required this.category,
  });
  final String family;
  final String label;
  final FontScript script;
  final FontCategory category;
}

/// Human label for a script — what the picker shows as the top-level
/// section header.
String scriptLabel(FontScript script) {
  switch (script) {
    case FontScript.latin:
      return 'English';
    case FontScript.arabic:
      return 'Farsi';
  }
}

/// Human-readable label for a category, scoped to a script (so we
/// can say "Modern" for Farsi sans vs "Sans" for Latin).
String categoryLabel(FontScript script, FontCategory category) {
  switch (category) {
    case FontCategory.sans:
      return script == FontScript.arabic ? 'Modern' : 'Sans';
    case FontCategory.display:
      return 'Display';
    case FontCategory.script:
      return 'Script';
    case FontCategory.mono:
      return 'Mono';
    case FontCategory.traditional:
      return 'Traditional';
    case FontCategory.nastaliq:
      return 'Nastaliq';
  }
}

/// Display order matches the picker (script → category → name).
const List<FontEntry> kFontCatalog = <FontEntry>[
  // ── English · Sans ────────────────────────────────────────────
  FontEntry(family: 'Hanken_Grotesk', label: 'Hanken Grotesk', script: FontScript.latin, category: FontCategory.sans),
  FontEntry(family: 'Josefin_Sans', label: 'Josefin Sans', script: FontScript.latin, category: FontCategory.sans),
  FontEntry(family: 'Lato', label: 'Lato', script: FontScript.latin, category: FontCategory.sans),
  FontEntry(family: 'Raleway', label: 'Raleway', script: FontScript.latin, category: FontCategory.sans),
  FontEntry(family: 'Roboto', label: 'Roboto', script: FontScript.latin, category: FontCategory.sans),
  FontEntry(family: 'Titillium_Web', label: 'Titillium Web', script: FontScript.latin, category: FontCategory.sans),

  // ── English · Mono ────────────────────────────────────────────
  FontEntry(family: 'Chivo_Mono', label: 'Chivo Mono', script: FontScript.latin, category: FontCategory.mono),

  // ── English · Script ──────────────────────────────────────────
  FontEntry(family: 'Dancing_Script', label: 'Dancing Script', script: FontScript.latin, category: FontCategory.script),

  // ── English · Display ─────────────────────────────────────────
  FontEntry(family: 'Barriecito', label: 'Barriecito', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Bungee_Shade', label: 'Bungee Shade', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Lobster', label: 'Lobster', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Rubik_80s_Fade', label: 'Rubik 80s Fade', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Rubik_Gemstones', label: 'Rubik Gemstones', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Rubik_Puddles', label: 'Rubik Puddles', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Rubik_Storm', label: 'Rubik Storm', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Rubik_Vinyl', label: 'Rubik Vinyl', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Rubik_Wet_Paint', label: 'Rubik Wet Paint', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Sevillana', label: 'Sevillana', script: FontScript.latin, category: FontCategory.display),
  FontEntry(family: 'Zen_Tokyo_Zoo', label: 'Zen Tokyo Zoo', script: FontScript.latin, category: FontCategory.display),

  // ── Farsi · Modern (sans) ─────────────────────────────────────
  FontEntry(family: 'B_Yekan', label: 'B Yekan', script: FontScript.arabic, category: FontCategory.sans),
  FontEntry(family: 'Dirooz', label: 'Dirooz', script: FontScript.arabic, category: FontCategory.sans),
  FontEntry(family: 'Eliya_Regular', label: 'Eliya Regular', script: FontScript.arabic, category: FontCategory.sans),
  FontEntry(family: 'Gandom', label: 'Gandom', script: FontScript.arabic, category: FontCategory.sans),
  FontEntry(family: 'IranianSans', label: 'IranianSans', script: FontScript.arabic, category: FontCategory.sans),
  FontEntry(family: 'Samim_Bold', label: 'Samim Bold', script: FontScript.arabic, category: FontCategory.sans),
  FontEntry(family: 'Shabnam', label: 'Shabnam', script: FontScript.arabic, category: FontCategory.sans),
  FontEntry(family: 'Vazir_Regular', label: 'Vazir', script: FontScript.arabic, category: FontCategory.sans),

  // ── Farsi · Traditional (Naskh) ───────────────────────────────
  FontEntry(family: 'BNazanin', label: 'BNazanin', script: FontScript.arabic, category: FontCategory.traditional),
  FontEntry(family: 'BRoya', label: 'BRoya', script: FontScript.arabic, category: FontCategory.traditional),
  FontEntry(family: 'BTitrBd', label: 'BTitr Bd', script: FontScript.arabic, category: FontCategory.traditional),
  FontEntry(family: 'BTraffic', label: 'BTraffic', script: FontScript.arabic, category: FontCategory.traditional),
  FontEntry(family: 'B_Koodak_Bold_0', label: 'B Koodak Bold', script: FontScript.arabic, category: FontCategory.traditional),
  FontEntry(family: 'B_Koodak_Outline_0', label: 'B Koodak Outline', script: FontScript.arabic, category: FontCategory.traditional),
  FontEntry(family: 'B_Mitra_Bold', label: 'B Mitra Bold', script: FontScript.arabic, category: FontCategory.traditional),
  FontEntry(family: 'Casablanca', label: 'Casablanca', script: FontScript.arabic, category: FontCategory.traditional),
  FontEntry(family: 'Hekayat', label: 'Hekayat', script: FontScript.arabic, category: FontCategory.traditional),
  FontEntry(family: 'Lalezar', label: 'Lalezar', script: FontScript.arabic, category: FontCategory.traditional),

  // ── Farsi · Nastaliq / Calligraphic ───────────────────────────
  FontEntry(family: 'DimaTahriri', label: 'Dima Tahriri', script: FontScript.arabic, category: FontCategory.nastaliq),
  FontEntry(family: 'Dima_Shekaste', label: 'Dima Shekaste', script: FontScript.arabic, category: FontCategory.nastaliq),
  FontEntry(family: 'Far_Ferdowsi', label: 'Far Ferdowsi', script: FontScript.arabic, category: FontCategory.nastaliq),
  FontEntry(family: 'IranNastaliq', label: 'Iran Nastaliq', script: FontScript.arabic, category: FontCategory.nastaliq),
  FontEntry(family: 'MjGhalam2', label: 'Mj Ghalam 2', script: FontScript.arabic, category: FontCategory.nastaliq),
  FontEntry(family: 'Mj_Sayeh_1', label: 'Mj Sayeh', script: FontScript.arabic, category: FontCategory.nastaliq),
  FontEntry(family: 'Neirizi', label: 'Neirizi', script: FontScript.arabic, category: FontCategory.nastaliq),
  FontEntry(family: 'W_hesam', label: 'W Hesam', script: FontScript.arabic, category: FontCategory.nastaliq),
  FontEntry(family: 'leyla', label: 'Leyla', script: FontScript.arabic, category: FontCategory.nastaliq),

  // ── Farsi · Display ───────────────────────────────────────────
  FontEntry(family: 'ANegaar', label: 'ANegaar', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'ARezvan', label: 'ARezvan', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'A_Ordibehesht_shablon', label: 'A Ordibehesht Shablon', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'A_Soraya', label: 'A Soraya', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Afsaneh', label: 'Afsaneh', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Araz', label: 'Araz', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Delbar_Bold', label: 'Delbar Bold', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Far_khodkar', label: 'Far Khodkar', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Fedra_Arabic_Display_AR_LT_Black', label: 'Fedra Arabic Display Black', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Mj_Dinar_Medium', label: 'Mj Dinar Medium', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Mj_Flow_Regular', label: 'Mj Flow', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Mj_SS_Three_Light', label: 'Mj SS Three Light', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Mosalas', label: 'Mosalas', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'SOGAND', label: 'SOGAND', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'Shams', label: 'Shams', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'persian_badkht2', label: 'Persian Badkht', script: FontScript.arabic, category: FontCategory.display),
  FontEntry(family: 'persian_khat_khati_02', label: 'Persian Khat Khati', script: FontScript.arabic, category: FontCategory.display),
];
