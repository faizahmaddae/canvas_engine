import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_body.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
import '../../../../app/ui/app_modal_sheet.dart';
import '../application/text_color_resolver.dart';
import '../application/text_tool_controller.dart';
import '../../../../app/theme/app_icons.dart';
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
  return showAppSheet<String>(
    context,
    barrier: AppSheetBarrier.whisper,
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

  /// [staged] when it is legible on the composer's own field fill,
  /// else the ordinary input colour.
  ///
  /// The field is `surfaceMuted @45%` over `surface`; compositing that
  /// by hand is exactly what the resolver's ratio helper is for.
  Color _legibleOnField(Color staged, AppTokens tokens) {
    final fill = Color.alphaBlend(
      tokens.surfaceMuted.withValues(alpha: 0.45),
      tokens.surface,
    );
    return TextColorResolver.contrastRatio(staged, fill) >= 4.5
        ? staged
        : tokens.textPrimary;
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
                // `VisualDensity.compact` cut Material's 40dp minimum to
                // 32 — under the repo's own 44dp floor — on the two
                // buttons a thumb has to hit with the keyboard up.
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                    minimumSize: const Size(0, kMinHitTarget),
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
                    minimumSize: const Size(0, kMinHitTarget),
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
            // Wrapped in a Consumer so the field can mirror the quick
            // pills sitting directly under it. Bold and Colour used to
            // toggle their pill and change nothing else on the sheet —
            // the only way to find out what «پررنگ» did was to commit
            // and look at the canvas.
            Consumer(
              builder: (context, ref, _) {
                final staged = stagedComposerStyle(ref);
                return TextField(
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
                    // The exact staged weight, not a two-state guess:
                    // the default is w600, so `isBold ? w700 : null`
                    // previewed the untouched default as w700 and its
                    // "off" state as the theme weight, not w400.
                    fontWeight: staged.fontWeight,
                    fontStyle: staged.italic
                        ? FontStyle.italic
                        : FontStyle.normal,
                    // The staged colour was resolved against the
                    // CANVAS, not against this field. On a white canvas
                    // it lands near-black, and the field's own fill is
                    // near-black in dark mode — 1.13:1, an input you
                    // cannot read while typing into it. Preview the
                    // real colour only where it survives on this fill.
                    color: _legibleOnField(staged.color, tokens),
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
                );
              },
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
/// The style the composer is currently staging.
///
/// Bound to the staged layer's CURRENT style when one is selected (a
/// live add session writes through to the layer via `liveOverlay`, not
/// to `defaultStyle`), else to the session default. Shared by the quick
/// pills and the input field so the field is a preview of what Add will
/// produce rather than a differently-styled box next to the controls.
TextStyleSpec stagedComposerStyle(WidgetRef ref) {
  final session = ref.watch(textToolControllerProvider);
  final doc = ref.watch(renderedDocumentProvider);
  final selectedId = ref.watch(selectionControllerProvider).selectedId;
  final selectedLayer = selectedId == null ? null : doc.layerById(selectedId);
  return (selectedLayer is TextLayer)
      ? selectedLayer.style
      : session.defaultStyle;
}

class _AddTextQuickStyleBar extends ConsumerStatefulWidget {
  const _AddTextQuickStyleBar();

  @override
  ConsumerState<_AddTextQuickStyleBar> createState() =>
      _AddTextQuickStyleBarState();
}

class _AddTextQuickStyleBarState extends ConsumerState<_AddTextQuickStyleBar> {
  bool _paletteOpen = false;

  // No frozen recents snapshot and no retained ScrollController: the
  // shared [ColorShelf] is a fixed 3x6 grid on reserved slots, so
  // nothing reflows under the finger and there is nothing to scroll.
  // Both existed only to compensate for the hand-rolled strip this
  // tray used to render.

  /// [initial] is the STAGED colour — the one the input field, the
  /// pill dot and the shelf are rendering — captured by the caller
  /// from the same [stagedComposerStyle] they all read. It must never
  /// be `session.defaultStyle.color`: during a live add/edit session
  /// `applyStyle` writes the selected layer only, so the session
  /// default stays untouched white and the wheel would open (and emit
  /// its first drag) on a colour the screen isn't showing (P2-9).
  Future<void> _openCustomPicker(Color initial) async {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    // The shared picker sheet — live, undimmed, recents handled
    // inside; nothing to restore or re-commit on close.
    await showColorPickerSheet(
      context,
      initial: initial,
      onLiveChange: ctrl.setColor,
      title: context.l10n.textColorTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final style = stagedComposerStyle(ref);
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
              key: const ValueKey('add-text-color-pill'),
              tooltip: context.l10n.colorLabel,
              active: _paletteOpen,
              leading: _ColorDot(color: style.color),
              label: context.l10n.colorLabel,
              onTap: () {
                EditorHaptics.tap();
                setState(() => _paletteOpen = !_paletteOpen);
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // THE shared shelf — the same widget, cells,
                        // dedupe rule, selection grammar and
                        // semantics the picker renders. What used to
                        // live here was a second implementation that
                        // disagreed with the picker on six points,
                        // including which of a colliding pair wins
                        // the slot.
                        ColorShelf(
                          current: style.color,
                          // Preserve the working alpha: a swatch tap
                          // is a hue choice, and the custom picker
                          // stays the authoritative entry for alpha.
                          // Alpha handling used to be restated here;
                          // it is the shelf host's one job now.
                          onPick: (c) =>
                              ctrl.setColor(c.withValues(alpha: style.color.a)),
                        ),
                        const SizedBox(height: 10),
                        _MoreColorButton(
                          onTap: () => _openCustomPicker(style.color),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Entry to the full custom picker, below the shelf.
///
/// Labelled rather than a bare "+" in a circle: a plus reads as
/// "add a colour to the palette", which is not what it does, and an
/// unlabelled glyph next to twelve colours is the one control on the
/// surface a screen reader could not name. The label is the existing
/// `moreColorsTooltip` string, now visible instead of hover-only.
class _MoreColorButton extends StatelessWidget {
  const _MoreColorButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return TextButton.icon(
      key: const ValueKey('add-text-more-colors'),
      onPressed: onTap,
      icon: Icon(AppIcons.colorTool, size: 18, color: tokens.accentText),
      label: Text(context.l10n.moreColorsTooltip),
      style: TextButton.styleFrom(
        foregroundColor: tokens.accentText,
        minimumSize: const Size(0, kMinHitTarget),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    super.key,
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
                    color: widget.active
                        ? tokens.accentText
                        : tokens.textSecondary,
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
        AppIcons.bold,
        size: 15,
        color: active ? tokens.accentText : tokens.textPrimary,
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
