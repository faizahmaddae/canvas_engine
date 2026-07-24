import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/widgets/editor_modal_sheet.dart';
import '../../application/recent_colors_controller.dart';
import '../application/text_tool_controller.dart';
import '../domain/text_style_presets.dart'
    show defaultFontFamilyForContent, textDirectionForContent;

/// Opens a focused text input flow optimized for mobile creation/editing.
///
/// Returns the confirmed text, or `null` when cancelled.
///
/// When [onLiveChange] is provided, every keystroke is forwarded to the
/// caller — used by the edit flow to drive a real-time canvas preview.
/// Cancelling the sheet (back / Cancel) returns `null`; callers that
/// applied live previews should revert their state in that branch.
Future<String?> showTextInputFlowSheet(
  BuildContext context, {
  String initial = '',
  String? title,
  String? confirmLabel,
  TextDirectionMode textDirectionMode = TextDirectionMode.auto,
  ValueChanged<String>? onLiveChange,
}) {
  // Whisper barrier (contract §9 — unified here from the interim
  // 20% to the canonical 6%): typing live-previews on the canvas
  // behind the composer, so the dim must stay a whisper. Keyboard-
  // aware: the input row rides above the IME.
  return showEditorSheet<String>(
    context,
    barrier: EditorSheetBarrier.whisper,
    keyboardAware: true,
    builder: (_) => _TextInputFlowSheet(
      initial: initial,
      title: title ?? context.l10n.addTextTitle,
      confirmLabel: confirmLabel ?? context.l10n.doneAction,
      textDirectionMode: textDirectionMode,
      onLiveChange: onLiveChange,
    ),
  );
}

class _TextInputFlowSheet extends StatefulWidget {
  const _TextInputFlowSheet({
    required this.initial,
    required this.title,
    required this.confirmLabel,
    required this.textDirectionMode,
    this.onLiveChange,
  });

  final String initial;
  final String title;
  final String confirmLabel;
  final TextDirectionMode textDirectionMode;
  final ValueChanged<String>? onLiveChange;

  @override
  State<_TextInputFlowSheet> createState() => _TextInputFlowSheetState();
}

class _TextInputFlowSheetState extends State<_TextInputFlowSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _focusNode = FocusNode();
    // Repaint the header so the Add button enables/disables in
    // lockstep with trimmed input. Cheaper than a ValueListenableBuilder
    // around the whole header — only the Add button reads the value.
    _controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    EditorHaptics.confirm();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final direction = textDirectionForContent(
      _controller.text,
      mode: widget.textDirectionMode,
    );

    // Chrome (floating card, handle, keyboard inset) comes from the
    // shared modal host (tb2 8/16); this body keeps its padding and
    // scroll guard only.
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      // Scroll guard: the keyboard is always up (the field
      // autofocuses), so on short/landscape phones the available
      // height above it can be smaller than this min-sized Column
      // (header + field + quick-style bar, plus the expandable
      // colour tray). Let it scroll instead of overflow.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row — title left, subtle Cancel + prominent
            // Add right. Cancel is intentionally text-only with
            // muted onSurfaceVariant so it doesn't compete with
            // Add (the primary action). Add is FilledButton and
            // disables until trimmed input is non-empty so users
            // never end up with an empty layer from a stray tap.
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  child: Text(context.l10n.cancelAction),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  key: const ValueKey('add-text-confirm'),
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.brand,
                    foregroundColor: tokens.onBrand,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                  child: Text(widget.confirmLabel),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Hero input. Multiline (1–3 lines, then scrolls).
            // Decision: the keyboard's Return key inserts a newline
            // (`textInputAction: newline`) and committing is *only*
            // via the Add button — picking one clear submit path
            // per the composer spec ("multiline input with explicit
            // Add button"). Cursor / selection / focus border all
            // tinted to the theme accent so the input reads as the
            // single hero element on the sheet.
            TextField(
              key: const ValueKey('add-text-input'),
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              // Suppress the keyboard's prediction strip and
              // learned-phrase autocorrect so previously-typed
              // unrelated content (notes, pasted text) can't be
              // surfaced as suggestions inside the composer.
              enableSuggestions: false,
              autocorrect: false,
              cursorColor: tokens.accent,
              cursorWidth: 2,
              scrollPadding: const EdgeInsets.all(20),
              // Direction + alignment follow the dominant script of
              // the current content so the editor mirrors what the
              // canvas will render: Persian/Arabic → RTL,
              // right-aligned; Latin → LTR, left-aligned. The font
              // is the app's Persian default (Vazir) for every
              // script — it carries Latin glyphs too.
              textDirection: direction,
              textAlign: direction == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
              style: TextStyle(
                fontFamily: defaultFontFamilyForContent(_controller.text),
                fontSize: 18,
              ),
              onChanged: (value) {
                // Keep the staged canvas layer in lockstep with
                // every keystroke. Note: the layer's committed
                // font is governed by the controller and a
                // user-picked font from the Font tool is never
                // overwritten.
                widget.onLiveChange?.call(value);
              },
              decoration: InputDecoration(
                hintText: context.l10n.typeSomethingHint,
                // Hint follows the same direction + font as the
                // input itself so the empty-state visual matches
                // what the user will see once they start typing.
                hintTextDirection: direction,
                hintStyle: TextStyle(
                  fontFamily: defaultFontFamilyForContent(_controller.text),
                  color: tokens.textSecondary.withValues(alpha: 0.7),
                ),
                isDense: true,
                filled: true,
                fillColor: tokens.surfaceMuted.withValues(alpha: 0.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: tokens.border.withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: tokens.border.withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: tokens.accent, width: 1.6),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Quick-style strip — intentionally minimal for the
            // Add flow. Bold + Color cover the two most common
            // pre-commit decisions; full styling (italic / under-
            // line / size / font / shadow / alignment …) lives
            // in the post-create text panel. Keeping the strip
            // tight here preserves the composer's "type → Add"
            // single-purpose feel.
            const _AddTextQuickStyleBar(),
          ],
        ),
      ),
    );
  }
}

/// Compact quick-style bar shown above the soft keyboard inside the
/// Add Text composer. Pre-commit only the two highest-leverage
/// decisions are exposed: **Bold** and **Color**. Everything else
/// (italic, underline, alignment, size, font, shadow, …) ships in
/// the full Text panel that opens after the layer is created.
///
/// The colour swatch toggles an inline palette directly below this
/// bar — we deliberately avoid routing to the dock's Color sheet
/// (it would render behind the modal and be invisible) or pushing
/// a second modal (it would steal keyboard focus and stack UI).
class _AddTextQuickStyleBar extends ConsumerStatefulWidget {
  const _AddTextQuickStyleBar();

  @override
  ConsumerState<_AddTextQuickStyleBar> createState() =>
      _AddTextQuickStyleBarState();
}

class _AddTextQuickStyleBarState extends ConsumerState<_AddTextQuickStyleBar> {
  bool _paletteOpen = false;
  // Snapshot of `recents` taken when the tray opens. Selecting a
  // swatch updates the live recents list (so it persists across
  // sessions) but we keep rendering this frozen order while the
  // tray is open — otherwise the just-picked colour would jump to
  // the front of the row, shifting every other swatch and making
  // the strip appear to scroll back to the start.
  List<Color>? _recentsAtOpen;
  // Stable controller so swatch taps that *do* trigger a list
  // rebuild keep the user's current scroll offset instead of
  // resetting to the start.
  final ScrollController _trayScroll = ScrollController();

  @override
  void dispose() {
    _trayScroll.dispose();
    super.dispose();
  }

  // The picker's own preset palette so the inline tray and the
  // shared picker feel like the same surface.
  static const List<Color> _palette = kColorPickerPalette;

  Future<void> _openCustomPicker() async {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final session = ref.read(textToolControllerProvider);
    // The shared picker sheet — live, undimmed, recents handled
    // inside; nothing to restore or re-commit on close.
    await showColorPickerSheet(
      context,
      initial: session.defaultStyle.color,
      onLiveChange: ctrl.setColor,
      title: context.l10n.textColorTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(textToolControllerProvider);
    final ctrl = ref.read(textToolControllerProvider.notifier);
    // Bind UI state to the staged layer's *current* style when one
    // is selected (live add session) — _applyStyle writes through
    // to the layer (via liveOverlay), not defaultStyle, so reading
    // defaultStyle here would leave Bold/Color toggles stuck on
    // stale state. Watch the merged view + selection so the bar
    // rebuilds whenever the staged layer changes.
    final doc = ref.watch(renderedDocumentProvider);
    final selectedId = ref.watch(selectionControllerProvider).selectedId;
    final selectedLayer = selectedId == null ? null : doc.layerById(selectedId);
    final style = (selectedLayer is TextLayer)
        ? selectedLayer.style
        : session.defaultStyle;
    final currentArgb = style.color.toARGB32();
    final recents = ref.watch(recentColorsControllerProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Quick controls row — Bold left, Color right. Two matched
        // pills sharing height/radius/padding/active style; no outer
        // glass card so the row reads as light controls, not a
        // settings strip.
        Row(
          children: [
            _QuickPill(
              tooltip: context.l10n.boldAction,
              active: style.isBold,
              leading: _BoldGlyph(active: style.isBold),
              label: context.l10n.boldAction,
              onTap: () {
                EditorHaptics.toggle();
                ctrl.setBold(!style.isBold);
              },
            ),
            const SizedBox(width: 10),
            _QuickPill(
              tooltip: context.l10n.colorLabel,
              active: _paletteOpen,
              leading: _ColorDot(color: style.color),
              label: context.l10n.colorLabel,
              onTap: () {
                EditorHaptics.tap();
                setState(() {
                  _paletteOpen = !_paletteOpen;
                  if (_paletteOpen) {
                    // Freeze the recents order shown in the tray
                    // for this open session.
                    _recentsAtOpen = List<Color>.unmodifiable(recents);
                  } else {
                    _recentsAtOpen = null;
                  }
                });
              },
            ),
          ],
        ),
        // Color tray — appears below the controls row when the
        // Color pill is active. AnimatedSize handles the open/close
        // smoothly; AnimatedSwitcher cross-fades the content so the
        // tray fades in rather than snapping.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: !_paletteOpen
                ? const SizedBox(
                    key: ValueKey('palette-closed'),
                    width: double.infinity,
                  )
                : Padding(
                    key: const ValueKey('palette-open'),
                    padding: const EdgeInsets.only(top: 10),
                    child: _ColorTray(
                      palette: _palette,
                      recents: _recentsAtOpen ?? recents,
                      currentArgb: currentArgb,
                      scrollController: _trayScroll,
                      onPick: (c) {
                        EditorHaptics.tap();
                        // Preserve current alpha so a quick swatch
                        // tap doesn't wipe a previously-dialed-in
                        // opacity. Custom picker remains the
                        // authoritative entry for alpha changes.
                        // Palette taps are deliberately NOT
                        // remembered — presets never earn a recents
                        // slot (they're always one tap away), same
                        // policy as the shared picker.
                        ctrl.setColor(c.withValues(alpha: style.color.a));
                      },
                      onCustom: _openCustomPicker,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Compact color tray rendered below the Add Text quick controls
/// when the Color pill is active. A small "Colors" label sits above
/// a single horizontally-scrollable row of generously-sized swatches:
/// recents (if any) lead, then a curated 12-colour palette, then a
/// "More" button that opens the full custom colour picker. The tray
/// owns its own glass card so it reads as a separate surface from
/// the controls row above it.
class _ColorTray extends StatelessWidget {
  const _ColorTray({
    required this.palette,
    required this.recents,
    required this.currentArgb,
    required this.onPick,
    required this.onCustom,
    required this.scrollController,
  });

  final List<Color> palette;
  final List<Color> recents;
  final int currentArgb;
  final ValueChanged<Color> onPick;
  final VoidCallback onCustom;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // De-dupe palette against recents so the same swatch doesn't
    // appear twice. Recents win the slot.
    final recentArgbs = recents.map((c) => c.toARGB32()).toSet();
    final dedupedPalette = palette
        .where((c) => !recentArgbs.contains(c.toARGB32()))
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              context.l10n.colorsLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.separated(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              // Generous internal inset so the first/last swatches
              // (and their selected halos) never kiss the tray
              // edges, even when the row doesn't overflow.
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: recents.length + dedupedPalette.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                if (i < recents.length) {
                  final c = recents[i];
                  return _PaletteDot(
                    color: c,
                    selected: c.toARGB32() == currentArgb,
                    onTap: () => onPick(c),
                  );
                }
                final j = i - recents.length;
                if (j < dedupedPalette.length) {
                  final c = dedupedPalette[j];
                  return _PaletteDot(
                    color: c,
                    selected: c.toARGB32() == currentArgb,
                    onTap: () => onPick(c),
                  );
                }
                return _MoreColorButton(onTap: onCustom);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Single colour dot used inside the inline swatch strip. Press-scales,
/// shows a primary ring + check when selected.
class _PaletteDot extends StatefulWidget {
  const _PaletteDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PaletteDot> createState() => _PaletteDotState();
}

class _PaletteDotState extends State<_PaletteDot> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // Compute a checkmark colour with sufficient contrast against
    // the swatch — black on light, white on dark.
    final luminance = widget.color.computeLuminance();
    final tickColor = luminance > 0.55 ? Colors.black87 : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        // Outer halo: an independent ring rendered *around* the
        // swatch when selected. Keeps the swatch's own subtle edge
        // intact (critical for white/very-light colours where the
        // swatch outline is the only thing separating it from the
        // tray background).
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.selected ? tokens.accent : Colors.transparent,
              width: widget.selected ? 2 : 0,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: 0.20),
                      blurRadius: 8,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: tokens.border.withValues(alpha: 0.55),
                width: 1,
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: widget.selected
                  ? Icon(
                      Icons.check_rounded,
                      key: const ValueKey('check'),
                      size: 18,
                      color: tickColor,
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
        ),
      ),
    );
  }
}

/// Trailing "+" button in the inline palette that opens the full
/// custom colour picker (existing `showColorPickerSheet`). Visually
/// distinct from a swatch so users read it as an action, not a colour.
class _MoreColorButton extends StatelessWidget {
  const _MoreColorButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Tooltip(
      message: context.l10n.moreColorsTooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: tokens.border, width: 1.2),
          ),
          child: Icon(Icons.add_rounded, size: 20, color: tokens.textSecondary),
        ),
      ),
    );
  }
}

/// Compact tappable "Color" pill — colour dot + label — used inside
/// [_AddTextQuickStyleBar] to toggle the inline palette below the
/// bar. The label gives the lonely dot a clear affordance so it
/// reads as an action (not just a decorative swatch). `active` lifts
/// the pill with a primary tint + ring so users see the bar and
/// palette are linked.
class _QuickPill extends StatefulWidget {
  const _QuickPill({
    required this.tooltip,
    required this.leading,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_QuickPill> createState() => _QuickPillState();
}

class _QuickPillState extends State<_QuickPill> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final ringColor = widget.active
        ? tokens.accent
        : tokens.border.withValues(alpha: 0.45);
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 36,
            padding: const EdgeInsets.fromLTRB(8, 4, 14, 4),
            decoration: BoxDecoration(
              color: widget.active
                  ? tokens.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: ringColor,
                width: widget.active ? 1.4 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.leading,
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.active ? tokens.accent : tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bold pill's leading glyph — the Material bold icon in a circle so
/// it visually rhymes with the Color pill's leading colour dot.
class _BoldGlyph extends StatelessWidget {
  const _BoldGlyph({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? tokens.accent.withValues(alpha: 0.18)
            : tokens.surfaceMuted.withValues(alpha: 0.6),
        shape: BoxShape.circle,
      ),
      // Weight icon, not a Latin 'B' — the label beside it is Persian
      // (پررنگ) and the sibling toggles use the Material format icons
      // (format_italic / format_underline), so bold matches the set.
      child: Icon(
        Icons.format_bold_rounded,
        size: 15,
        color: active ? tokens.accent : tokens.textPrimary,
      ),
    );
  }
}

/// Color pill's leading dot — shows the current text colour.
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: tokens.border.withValues(alpha: 0.7),
          width: 1,
        ),
      ),
    );
  }
}
