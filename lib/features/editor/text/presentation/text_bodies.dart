// Sheet-body builders for the text-mode toolbar (Phase 2A commit 5:
// the last part file becomes a standalone import — the library is
// now bar + registry + dispatch only). Rename-only promotion of
// TextBodies, the registry's builder table.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/panels/text/font_picker/inline_browser.dart';
import '../../presentation/panels/text/font_picker/picker_sheet.dart';
import '../../presentation/panels/text/layout_panel.dart';
import '../../presentation/panels/text/size_panel.dart';
import '../../presentation/panels/text/styles_panel.dart';
import '../application/text_tool_controller.dart';

/// Holder for the per-category body builders. Each method takes
/// (context, ref, layer) and returns a vertical column of compact
/// rows / sliders / segmented toggles.
class TextBodies {
  const TextBodies();

  // ─── Font ────────────────────────────────────────────────────────
  //
  // Inline font body: horizontal strip of typeface pills (each
  // rendered IN its own face so the user previews before tapping)
  // + a "Browse all" entry that opens the full sectioned picker
  // only when the user actually needs it. Keeps the canvas
  // visible for the most common case — picking from the last few
  // fonts used or the top of the catalog.
  static Widget fontBody(BuildContext context, WidgetRef ref, TextLayer layer) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final current = layer.style.fontFamily;
    return InlineFontBody(
      layerId: layer.id,
      current: current,
      content: layer.content,
      onPick: (family) {
        EditorHaptics.tap();
        ctrl.setFontFamily(family);
      },
      // The All-fonts sheet opens scoped to whichever tab the user
      // is currently browsing. They can still switch script inside
      // the sheet — we just don't drop them into a mixed list.
      onBrowseAll: (script) async {
        final picked = await showFontPickerSheet(
          context,
          current: current,
          initialScript: script,
        );
        if (picked == FontPickResult.unchanged) return;
        EditorHaptics.confirm();
        ctrl.setFontFamily(picked.family);
      },
    );
  }

  // ─── Color ───────────────────────────────────────────────────────
  //
  // The shared two-level picker, embedded: the dock chrome provides
  // the header (title + ×), the body provides swatches/recents/hex/
  // eyedropper with the custom wheel expanding inline. Everything
  // applies live — the canvas above is the preview. Alpha
  // preservation and recents bookkeeping live inside the picker.
  static Widget colorBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    return ColorPickerBody(
      initial: layer.style.color,
      title: context.l10n.textColorTitle,
      onChanged: ctrl.setColor,
    );
  }

  // ─── Size ────────────────────────────────────────────────────────
  //
  // Canva-style: a pair of big A−/A+ buttons for instant nudge,
  // a row of named size chips (S/M/L/XL/XXL) for confident jumps,
  // and the precise numeric slider tucked under "Advanced". The
  // canvas above shows the live result; no in-sheet hero needed.
  static Widget sizeBody(BuildContext context, WidgetRef ref, TextLayer layer) {
    return SizeBody(layer: layer);
  }

  // ─── Styles (one-tap presets) ────────────────────────────────────
  //
  // Renders ready-made text looks as 2-column preview cards. Tap
  // applies the preset's full TextStyleSpec to the selected layer
  // (font + size + colour + decoration + shadow + outline +
  // background) in a single undoable step; layer content,
  // position, rotation, and resize-mode are left alone.
  static Widget stylesBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    return StylesBody(layer: layer);
  }

  // ─── Style ───────────────────────────────────────────────────────
  //
  // Removed in Phase 2: the Style tile is gone from the bottom dock.
  // Bold / Italic / Underline are toggle actions, not category sheets,
  // and now live in the floating bar's "More" sheet (see
  // the unified layer overflow sheet). Opacity remains
  // adjustable via the Color picker's alpha channel.

  // ─── Background / Border / Shadow / Behavior ────────────────────
  //
  // Removed in the bar-consolidation pass: the decoration sheets'
  // standalone dock tiles duplicated the Styles panel's effect
  // chips, so their bodies now live as compact sections in
  // `effect_sections.dart` (زمینه / خط دور / سایه) and resize
  // behaviour is reached via the «بیشتر» sheet's picker.

  // ─── Layout ──────────────────────────────────────────────────────
  //
  // Alignment segmented control + one always-visible slider row
  // each for line height and letter spacing (compactness pass).
  static Widget layoutBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    return LayoutPanel(layer: layer);
  }
}
