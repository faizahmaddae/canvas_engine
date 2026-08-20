import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../../color_picker/presentation/color_picker_sheet.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/panels/text/font_picker/cards.dart'
    show fontSampleText;
import '../../presentation/panels/text/font_picker/inline_browser.dart'
    show recommendedFontEntries;
import '../../presentation/panels/text/font_picker/picker_sheet.dart';
import '../../presentation/widgets/controls/toggle_segment.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
import '../../../../app/ui/app_modal_sheet.dart';
import '../application/text_color_resolver.dart';
import '../application/text_tool_controller.dart';
import '../../../../app/theme/app_icons.dart';
import '../domain/font_catalog.dart';
import '../domain/text_style_presets.dart'
    show
        defaultFontFamilyForContent,
        textDirectionForContent,
        textIsArabicScript;

/// Opens the Studio Composer — the focused writing surface where the
/// full style rail (fonts, inks, size, B/I/U) rides above the
/// keyboard so writing and dressing are one activity
/// (`docs/text-studio-redesign-2026-08.md` §3).
///
/// Returns the confirmed text, or `null` when cancelled.
///
/// When [onLiveChange] is provided, every keystroke is forwarded to the
/// caller — used by both flows to drive a real-time canvas preview.
/// Cancelling the sheet (back / ✕) returns `null`; callers that
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
    // Repaint the sheet so the commit pill enables/disables in
    // lockstep with trimmed input and the font strip re-renders its
    // specimens with what the user actually typed.
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
      // (header + field + the style rail). Let it scroll instead of
      // overflow.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row — title left, quiet ✕ cancel + prominent
            // commit right. Cancel is a bare icon (the draft-session
            // grammar every editor sheet shares) so it doesn't
            // compete with the commit pill, which disables until
            // trimmed input is non-empty so users never end up with
            // an empty layer from a stray tap.
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
                Semantics(
                  button: true,
                  label: context.l10n.cancelAction,
                  child: InkWell(
                    key: const ValueKey('composer-cancel'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox(
                      width: kMinHitTarget,
                      height: kMinHitTarget,
                      child: Icon(
                        AppIcons.close,
                        size: 20,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
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
            const SizedBox(height: 12),
            // Hero input. Multiline (1–3 lines, then scrolls).
            // Decision: the keyboard's Return key inserts a newline
            // (`textInputAction: newline`) and committing is *only*
            // via the commit pill — one clear submit path.
            // Wrapped in a Consumer so the field mirrors the staged
            // style beneath it: face, weight, italic. The field is a
            // preview of what commit will produce, not a
            // differently-styled box next to the controls.
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
                  // right-aligned; Latin → LTR, left-aligned.
                  textDirection: direction,
                  textAlign: direction == TextDirection.rtl
                      ? TextAlign.right
                      : TextAlign.left,
                  style: TextStyle(
                    // The staged FACE, not just weight: picking a
                    // font from the rail below must restyle the
                    // words under the caret, or the rail reads as
                    // disconnected chrome.
                    fontFamily:
                        staged.fontFamily ??
                        defaultFontFamilyForContent(_controller.text),
                    fontSize: 18,
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
                    // every keystroke.
                    widget.onLiveChange?.call(value);
                  },
                  decoration: InputDecoration(
                    hintText: context.l10n.typeSomethingHint,
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
                      vertical: 14,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            // The style rail — the composer's whole point. Every
            // control writes through the controller, which mirrors
            // mid-session edits onto the live overlay: the canvas
            // restyles per tap and NOTHING reaches history until the
            // commit pill seals the one entry.
            _ComposerStyleRail(
              content: _controller.text,
              fieldFocus: _focusNode,
            ),
          ],
        ),
      ),
    );
  }
}

/// The style the composer is currently staging.
///
/// Bound to the staged layer's CURRENT style when one is selected (a
/// live add session writes through to the layer via `liveOverlay`, not
/// to `defaultStyle`), else to the session default. Shared by the rail
/// and the input field so the field is a preview of what commit will
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

// ─────────────────────────────────────────────────────────────────
// The style rail
// ─────────────────────────────────────────────────────────────────

/// Size-nudge clamps. Mirror the Size sheet's absolute range (see
/// `size_panel.dart`) so the composer's −/＋ can never stage a value
/// the dressed-posture controls would refuse.
const double _composerMinFontSize = 4;
const double _composerMaxFontSize = 2000;

/// The full styling rail under the composer's input: a font strip of
/// live specimens plus one quick row (inks · B/I/U · size nudge).
///
/// Everything here writes through [TextToolController] setters, which
/// during a live composer session mirror onto the overlay — the rail
/// can dress the text completely before it ever becomes one history
/// entry (`docs/text-studio-redesign-2026-08.md` §3).
class _ComposerStyleRail extends ConsumerWidget {
  const _ComposerStyleRail({required this.content, required this.fieldFocus});

  final String content;

  /// The input's focus node, so modal detours (font room, colour
  /// sheet) can hand the keyboard back when they close.
  final FocusNode fieldFocus;

  /// Quick inks — the same drawing-biased palette head the paint
  /// bench uses, so "a preset colour" means one thing everywhere.
  static const List<Color> quickInks = <Color>[
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFF22C55E),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final staged = stagedComposerStyle(ref);
    final effectiveFamily =
        staged.fontFamily ?? defaultFontFamilyForContent(content);
    // Strip script: what the user is TYPING wins (the faces on offer
    // must flatter the words under the caret); before any content
    // exists, the staged face's own script decides — a fresh Persian
    // default must open on the Persian list, where it can be shown
    // selected (the July `_autoTab` lesson, applied here).
    final script = content.trim().isNotEmpty
        ? (textIsArabicScript(content) ? FontScript.arabic : FontScript.latin)
        : _scriptOfFamily(effectiveFamily);
    final entries = recommendedFontEntries(script);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Font strip — the hero of the rail. Specimens render the
        // TYPED text so the choice is judged on the user's own words,
        // falling back to each face's sample while the field is empty.
        SizedBox(
          height: 58,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsetsDirectional.only(start: 2, end: 2),
            itemCount: entries.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              if (i == entries.length) {
                return _AllFontsChip(
                  onTap: () => _openFontRoom(context, ref, script, staged),
                );
              }
              final entry = entries[i];
              return _ComposerFontChip(
                entry: entry,
                content: content,
                selected: entry.family == effectiveFamily,
                onTap: () {
                  EditorHaptics.tap();
                  ctrl.setFontFamily(entry.family);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Quick row: fixed anchors (ink dot, B/I/U, size nudge) with
        // the swatch run flexing between them — the paint style-row
        // grammar, applied to type.
        Row(
          children: [
            _ComposerInkDot(
              color: staged.color,
              onTap: () => _openInkSheet(context, ref, staged.color),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsetsDirectional.only(start: 2, end: 4),
                  itemCount: quickInks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 4),
                  itemBuilder: (_, i) {
                    final ink = quickInks[i];
                    final hex = ink
                        .toARGB32()
                        .toRadixString(16)
                        .padLeft(8, '0');
                    return Center(
                      child: _ComposerInkSwatch(
                        key: ValueKey('composer-ink-$hex'),
                        ink: ink,
                        selected: staged.color.toARGB32() == ink.toARGB32(),
                        onTap: () {
                          EditorHaptics.tap();
                          // A swatch tap is a hue choice; alpha stays
                          // the custom picker's concern.
                          ctrl.setColor(ink.withValues(alpha: staged.color.a));
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            _railDivider(tokens),
            const SizedBox(width: 6),
            ToggleSegmentGroup(
              children: [
                Semantics(
                  label: context.l10n.boldAction,
                  button: true,
                  child: ToggleSegment(
                    key: const ValueKey('composer-bold'),
                    icon: AppIcons.bold,
                    selected: staged.isBold,
                    onTap: () => ctrl.setBold(!staged.isBold),
                  ),
                ),
                Semantics(
                  label: context.l10n.italicAction,
                  button: true,
                  child: ToggleSegment(
                    key: const ValueKey('composer-italic'),
                    icon: AppIcons.textItalic,
                    selected: staged.italic,
                    onTap: () => ctrl.setItalic(!staged.italic),
                  ),
                ),
                Semantics(
                  label: context.l10n.underlineAction,
                  button: true,
                  child: ToggleSegment(
                    key: const ValueKey('composer-underline'),
                    icon: AppIcons.textUnderline,
                    selected: staged.underline,
                    onTap: () => ctrl.setUnderline(!staged.underline),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            _railDivider(tokens),
            const SizedBox(width: 6),
            _SizeNudge(
              key: const ValueKey('composer-size-minus'),
              icon: AppIcons.decrement,
              semanticLabel: context.l10n.sizeDecreaseAction,
              onTap: () => _bumpSize(ref, -1),
            ),
            const SizedBox(width: 4),
            _SizeNudge(
              key: const ValueKey('composer-size-plus'),
              icon: AppIcons.add,
              semanticLabel: context.l10n.sizeIncreaseAction,
              onTap: () => _bumpSize(ref, 1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _railDivider(AppTokens tokens) => Container(
    width: 1,
    height: 20,
    color: tokens.border.withValues(alpha: 0.8),
  );

  /// Catalog script of [family], Persian when the family is unknown —
  /// the app's default face is Persian, so the unknown case can only
  /// be the seeded default in practice.
  static FontScript _scriptOfFamily(String? family) {
    for (final e in kFontCatalog) {
      if (e.family == family) return e.script;
    }
    return FontScript.arabic;
  }

  /// Perceptual ±10% size nudge in VISUAL px (the same space the Size
  /// sheet reads and writes), so a composer nudge and a sheet nudge
  /// agree about what "one step" means.
  void _bumpSize(WidgetRef ref, int dir) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final layer = ctrl.selectedTextLayer();
    final current = layer == null
        ? stagedComposerStyle(ref).fontSize
        : ctrl.visualFontSizeOf(layer);
    final s = (current * 0.1).roundToDouble();
    final step = s < 1 ? 1 : s;
    final next = (current + dir * step)
        .clamp(_composerMinFontSize, _composerMaxFontSize)
        .toDouble();
    if ((next - current).abs() < 0.01) return;
    EditorHaptics.tap();
    ctrl.setFontSize(next);
  }

  /// Detour to the Font Room. Highlights stage the face on the live
  /// session (overlay only — zero history mid-composer); dismissing
  /// un-picked restores the face the session had. The keyboard is
  /// handed back to the field either way.
  Future<void> _openFontRoom(
    BuildContext context,
    WidgetRef ref,
    FontScript script,
    TextStyleSpec staged,
  ) async {
    EditorHaptics.tap();
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final before = staged.fontFamily;
    final picked = await showFontPickerSheet(
      context,
      current: before,
      initialScript: script,
      specimenText: content,
      onHighlight: ctrl.setFontFamily,
    );
    if (picked.isDismissed) {
      // Un-picked: put the staged face back (highlights previewed
      // through the same live-session channel, so this is a pure
      // overlay restore — nothing touched history).
      ctrl.setFontFamily(before);
    } else {
      EditorHaptics.confirm();
      ctrl.setFontFamily(picked.family);
    }
    fieldFocus.requestFocus();
  }

  /// Detour to the shared colour picker — live, undimmed, recents
  /// handled inside; mid-session every change mirrors onto the
  /// overlay, so there is nothing to commit or restore on close.
  Future<void> _openInkSheet(
    BuildContext context,
    WidgetRef ref,
    Color current,
  ) async {
    EditorHaptics.tap();
    final ctrl = ref.read(textToolControllerProvider.notifier);
    await showColorPickerSheet(
      context,
      initial: current,
      onLiveChange: ctrl.setColor,
      title: context.l10n.textColorTitle,
    );
    fieldFocus.requestFocus();
  }
}

/// One specimen chip in the composer's font strip: the typed text (or
/// the face's sample) rendered in the candidate face, name caption
/// underneath. Selection wears the panel-wide soft fill + border so
/// the active face is obvious at any scroll position.
class _ComposerFontChip extends StatelessWidget {
  const _ComposerFontChip({
    required this.entry,
    required this.content,
    required this.selected,
    required this.onTap,
  });

  final FontEntry entry;
  final String content;
  final bool selected;
  final VoidCallback onTap;

  /// Cap the specimen to a short excerpt — the chip is a recognition
  /// aid, not a reading surface, and an essay would relayout per
  /// keystroke in every face on the strip (contract §8).
  static const int _excerptCap = 14;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final trimmed = content.trim();
    final sample = trimmed.isEmpty
        ? fontSampleText(entry)
        : (trimmed.length <= _excerptCap
              ? trimmed
              : trimmed.substring(0, _excerptCap));
    final direction = entry.script == FontScript.arabic
        ? TextDirection.rtl
        : TextDirection.ltr;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('composer-font-${entry.family}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.12)
                : tokens.surfaceMuted.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? tokens.accent.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: Directionality(
                    textDirection: direction,
                    child: Text(
                      sample,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontFamily: entry.family,
                        fontFamilyFallback: const <String>[],
                        fontSize: 19,
                        height: 1.0,
                        // The specimen must read as the face's real
                        // personality — never tinted for selection.
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.labelFor(Localizations.localeOf(context).languageCode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? tokens.accent : tokens.textSecondary,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trailing entry to the Font Room, matching the resting chip's
/// surface with a primary-tinted glyph so it reads as a door.
class _AllFontsChip extends StatelessWidget {
  const _AllFontsChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('composer-font-all'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: tokens.surfaceMuted.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: Icon(
                    AppIcons.gridView,
                    size: 20,
                    color: tokens.accent,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.l10n.allFontsTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: tokens.accent,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The current-ink dot — live colour state and the door to the full
/// picker, mirroring the paint bench's current-ink grammar.
class _ComposerInkDot extends StatelessWidget {
  const _ComposerInkDot({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: context.l10n.textColorTitle,
      child: InkWell(
        key: const ValueKey('composer-ink-dot'),
        customBorder: const CircleBorder(),
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        child: Container(
          width: 30,
          height: 30,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: tokens.accent.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: tokens.border.withValues(alpha: 0.7),
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One quick-ink swatch. Selection ring in accent so the active ink
/// reads without relying on the fill itself.
class _ComposerInkSwatch extends StatelessWidget {
  const _ComposerInkSwatch({
    super.key,
    required this.ink,
    required this.selected,
    required this.onTap,
  });

  final Color ink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: ink,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? tokens.accent
                : tokens.border.withValues(alpha: 0.7),
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// Compact −/＋ size nudge. Same visual vocabulary as the Size
/// sheet's pair at a rail-sized footprint.
class _SizeNudge extends StatelessWidget {
  const _SizeNudge({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: tokens.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 32,
            child: Center(child: Icon(icon, size: 16, color: tokens.accent)),
          ),
        ),
      ),
    );
  }
}
