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
import '../../presentation/panels/text/precision/background_precision.dart';
import '../../presentation/panels/text/precision/border_precision.dart';
import '../../presentation/panels/text/precision/shadow_precision.dart';
import '../../presentation/panels/text/resize_panel.dart';
import '../../presentation/panels/text/size_panel.dart';
import '../../presentation/panels/text/styles_panel.dart';
import '../../presentation/widgets/controls/section_label.dart';
import '../../presentation/widgets/inline_color_body.dart';
import '../../ui/panel_direction_pad.dart';
import '../../application/recent_colors_controller.dart';
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
  // Inline color body — replaces the modal picker for the common
  // case. Renders the user's recent palette + a quick-pick row of
  // common defaults; "Custom" opens the full spectrum picker for
  // when none of the recents fit. Keeps the canvas visible the
  // whole time the user is auditioning colours.
  static Widget colorBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final current = layer.style.color;
    return InlineColorBody(
      current: current,
      recents: ref.watch(recentColorsControllerProvider),
      palette: InlineColorBody.defaultPalette,
      compactRecents: true,
      onPick: (c) {
        EditorHaptics.tap();
        // Preserve current alpha so a quick swatch tap doesn't
        // wipe a previously-dialed-in opacity. The custom picker
        // remains the authoritative entry point for changing alpha.
        ctrl.setColor(c.withValues(alpha: current.a));
      },
      onCustom: () async {
        final original = current;
        final picked = await showColorPickerSheet(
          context,
          initial: original,
          recents: ref.read(recentColorsControllerProvider),
          onLiveChange: ctrl.setColor,
          title: context.l10n.textColorTitle,
        );
        if (picked == null) {
          ctrl.setColor(original);
          return;
        }
        EditorHaptics.confirm();
        ctrl.setColor(picked);
        ctrl.rememberRecentColor(picked);
      },
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
  // showTextMoreSheet in text_floating_toolbar.dart). Opacity remains
  // adjustable via the Color picker's alpha channel.

  // ─── Background ──────────────────────────────────────────────────
  //
  // Style-first: 4 named shape tiles (None/Pill/Card/Tag) commit
  // radius+padding in one undo entry, then a curated swatch row
  // applies a fill colour. Numeric sliders (roundness, vertical /
  // horizontal padding, opacity) live under Advanced. The canvas
  // is the live preview — no in-sheet preview block.
  static Widget backgroundBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasBg = style.backgroundColor != null;

    void enableIfNeeded() {
      if (!hasBg) ctrl.setBackgroundEnabled(true);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelSectionLabel(context.l10n.shapeLabel),
        StyleTileRow(
          tiles: [
            StyleTile(
              icon: Icons.block_rounded,
              label: context.l10n.noneOption,
              selected: !hasBg,
              onTap: () => ctrl.setBackgroundEnabled(false),
            ),
            StyleTile(
              icon: Icons.crop_16_9_rounded,
              label: context.l10n.pillOption,
              selected: hasBg && bgMatches(style, backgroundPresets[1]),
              onTap: () {
                enableIfNeeded();
                applyBgPreset(ref, backgroundPresets[1]);
              },
            ),
            StyleTile(
              icon: Icons.crop_square_rounded,
              label: context.l10n.cardOption,
              selected: hasBg && bgMatches(style, backgroundPresets[2]),
              onTap: () {
                enableIfNeeded();
                applyBgPreset(ref, backgroundPresets[2]);
              },
            ),
            StyleTile(
              icon: Icons.local_offer_outlined,
              label: context.l10n.tagOption,
              selected: hasBg && bgMatches(style, backgroundPresets[3]),
              onTap: () {
                enableIfNeeded();
                applyBgPreset(ref, backgroundPresets[3]);
              },
            ),
          ],
        ),
        if (hasBg) ...[
          const SizedBox(height: 10),
          // Pilot color UI — same compact layout the Text → Color
          // panel uses so the two text panels speak one visual
          // language. Behaviour (alpha-preserving picks, custom
          // sheet, recents) is unchanged.
          InlineColorBody(
            current: style.backgroundColor!,
            recents: ref.watch(recentColorsControllerProvider),
            palette: kCuratedTextSwatches,
            compactRecents: true,
            onPick: (c) {
              // Preserve current alpha so the user keeps any opacity
              // they set in Advanced when swapping hues.
              final a = style.backgroundColor?.a ?? 0.85;
              ctrl.setBackgroundColor(c.withValues(alpha: a));
            },
            onCustom: () async {
              final original = style.backgroundColor!;
              final picked = await showColorPickerSheet(
                context,
                initial: original,
                recents: ref.read(recentColorsControllerProvider),
                onLiveChange: ctrl.setBackgroundColor,
                title: context.l10n.backgroundColorTitle,
              );
              if (picked == null) {
                ctrl.setBackgroundColor(original);
                return;
              }
              ctrl.setBackgroundColor(picked);
              ctrl.rememberRecentColor(picked);
            },
          ),
          const SizedBox(height: 6),
          BackgroundPrecisionAdvanced(style: style),
        ],
      ],
    );
  }

  // ─── Border (glyph outline) ─────────────────────────────────────
  //
  // Style-first: 4 thickness tiles (None / Hairline / Solid / Bold)
  // commit width in one tap, then a swatch row picks the colour.
  // Exact width + opacity live under Advanced.
  static Widget borderBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasOutline = style.outlineColor != null;

    void enableIfNeeded() {
      if (!hasOutline) ctrl.setOutlineEnabled(true);
    }

    bool widthMatches(double target) =>
        hasOutline && (style.outlineWidth - target).abs() < 0.25;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mirror Background's breathing room above the first section
        // label so the STYLE header is not pinned to the sheet edge,
        // especially when the Adjust-precisely disclosure is open.
        const SizedBox(height: 6),
        PanelSectionLabel(context.l10n.styleLabel),
        StyleTileRow(
          tiles: [
            StyleTile(
              icon: Icons.block_rounded,
              label: context.l10n.noneOption,
              selected: !hasOutline,
              onTap: () => ctrl.setOutlineEnabled(false),
            ),
            StyleTile(
              icon: Icons.horizontal_rule_rounded,
              label: context.l10n.hairlineOption,
              iconSize: 16,
              selected: widthMatches(0.5),
              onTap: () {
                enableIfNeeded();
                ctrl.setOutlineWidth(0.5);
              },
            ),
            StyleTile(
              icon: Icons.horizontal_rule_rounded,
              label: context.l10n.solidOption,
              iconSize: 22,
              selected: widthMatches(2),
              onTap: () {
                enableIfNeeded();
                ctrl.setOutlineWidth(2);
              },
            ),
            StyleTile(
              icon: Icons.horizontal_rule_rounded,
              label: context.l10n.boldAction,
              iconSize: 30,
              selected: widthMatches(4),
              onTap: () {
                enableIfNeeded();
                ctrl.setOutlineWidth(4);
              },
            ),
          ],
        ),
        if (hasOutline) ...[
          const SizedBox(height: 10),
          // Approved compact color UI — same widget Text Color
          // and Background use, so all three text panels speak
          // one visual language. Behaviour (alpha-preserving
          // picks, custom sheet, recents) is unchanged.
          InlineColorBody(
            current: style.outlineColor!,
            recents: ref.watch(recentColorsControllerProvider),
            palette: kCuratedTextSwatches,
            compactRecents: true,
            onPick: (c) {
              final a = style.outlineColor?.a ?? 1.0;
              ctrl.setOutlineColor(c.withValues(alpha: a));
            },
            onCustom: () async {
              final original = style.outlineColor!;
              final picked = await showColorPickerSheet(
                context,
                initial: original,
                recents: ref.read(recentColorsControllerProvider),
                onLiveChange: ctrl.setOutlineColor,
                title: context.l10n.borderColorTitle,
              );
              if (picked == null) {
                ctrl.setOutlineColor(original);
                return;
              }
              ctrl.setOutlineColor(picked);
              ctrl.rememberRecentColor(picked);
            },
          ),
          const SizedBox(height: 6),
          BorderPrecisionAdvanced(style: style),
        ],
      ],
    );
  }

  // ─── Shadow ─────────────────────────────────────────────────────
  //
  // Style-first: 4 named shadow tiles (Soft / Hard / Glow / Lift)
  // commit blur+opacity macros, a 3×3 direction pad replaces the two
  // numeric Offset sliders, swatches pick colour. Numeric blur /
  // distance / opacity sit under Advanced.
  static Widget shadowBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = layer.style;
    final hasShadow = style.shadowColor != null;

    void enableIfNeeded() {
      if (!hasShadow) ctrl.setShadowEnabled(true);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Match Background/Border breathing room above first label.
        const SizedBox(height: 6),
        PanelSectionLabel(context.l10n.styleLabel),
        StyleTileRow(
          tiles: [
            StyleTile(
              icon: Icons.block_rounded,
              label: context.l10n.noneOption,
              selected: !hasShadow,
              onTap: () => ctrl.setShadowEnabled(false),
            ),
            for (int i = 0; i < shadowPresets.length; i++)
              StyleTile(
                icon: shadowPresetIcons[i],
                label: shadowPresetLabel(context.l10n, shadowPresets[i]),
                selected: hasShadow && shadowMatches(style, shadowPresets[i]),
                onTap: () {
                  enableIfNeeded();
                  applyShadowPreset(
                    ref,
                    shadowPresets[i],
                    baseColor: style.shadowColor ?? const Color(0xFF000000),
                  );
                },
              ),
          ],
        ),
        if (hasShadow) ...[
          const SizedBox(height: 10),
          // Approved compact color UI — same widget Color /
          // Background / Border use, so all four text panels
          // speak one visual language. Behaviour (alpha-
          // preserving picks, custom sheet, recents) is
          // unchanged. The compact swap also trims ~26-52dp off
          // the color section, comfortably absorbing the
          // direction pad below.
          InlineColorBody(
            current: style.shadowColor!,
            recents: ref.watch(recentColorsControllerProvider),
            palette: kCuratedTextSwatches,
            compactRecents: true,
            onPick: (c) {
              final a = style.shadowColor?.a ?? 0.5;
              ctrl.setShadowColor(c.withValues(alpha: a));
            },
            onCustom: () async {
              final original = style.shadowColor!;
              final picked = await showColorPickerSheet(
                context,
                initial: original,
                recents: ref.read(recentColorsControllerProvider),
                onLiveChange: ctrl.setShadowColor,
                title: context.l10n.shadowColorTitle,
              );
              if (picked == null) {
                ctrl.setShadowColor(original);
                return;
              }
              ctrl.setShadowColor(picked);
              ctrl.rememberRecentColor(picked);
            },
          ),
          const SizedBox(height: 10),
          PanelSectionLabel(context.l10n.directionLabel),
          // Constrain width so the pad reads as a secondary control,
          // not a hero element. Centred to keep the panel balanced.
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 168,
              child: PanelDirectionPad(
                offset: style.shadowOffset,
                magnitude: shadowDirectionMagnitude(style.shadowOffset),
                size: 144,
                onPick: (off) {
                  EditorHaptics.toggle();
                  ctrl.setShadowOffset(off);
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          ShadowPrecisionAdvanced(style: style),
        ],
      ],
    );
  }

  // ─── Layout ──────────────────────────────────────────────────────
  //
  // Mobile-first redesign:
  //   * Alignment segmented control (always visible).
  //   * Two card-shaped blocks ("Line height", "Letter spacing")
  //     each with: label, current value, preset chips (always
  //     visible, 1-tap apply), and a chevron that expands a
  //     fine-tune slider INLINE inside that card only.
  //   * No `Advanced controls` wrapper, no nested arrows, no
  //     duplicated rows. Only one slider may be expanded at a
  //     time — opening one closes the other so the canvas never
  //     loses real estate to unused sliders.
  static Widget layoutBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    return LayoutPanel(layer: layer);
  }

  // ─── Resize ──────────────────────────────────────────────────────
  //
  // Two inline option tiles under a single `Behavior` section label
  // — same spacing rhythm as Background/Border/Shadow. Plain-language
  // labels: "Scale text" / "Reflow box", with corner-drag subtitles
  // so the user understands what the gesture will do.
  static Widget behaviorBody(
    BuildContext context,
    WidgetRef ref,
    TextLayer layer,
  ) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final mode = layer.resizeMode;
    final isScale = mode == TextResizeMode.scaleText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        PanelSectionLabel(context.l10n.behaviorLabel),
        ResizeOptionTile(
          icon: Icons.zoom_out_map_rounded,
          title: context.l10n.scaleTextTitle,
          hint: context.l10n.cornerDragScalesTextHint,
          selected: isScale,
          onTap: () {
            if (mode == TextResizeMode.scaleText) return;
            ctrl.setResizeMode(TextResizeMode.scaleText);
          },
        ),
        const SizedBox(height: 2),
        ResizeOptionTile(
          icon: Icons.crop_landscape_rounded,
          title: context.l10n.reflowBoxTitle,
          hint: context.l10n.cornerDragWrapWidthHint,
          selected: !isScale,
          onTap: () {
            if (mode == TextResizeMode.resizeBox) return;
            ctrl.setResizeMode(TextResizeMode.resizeBox);
          },
        ),
      ],
    );
  }
}



