import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/l10n.dart';
import '../../editor/application/canvas_capture.dart';
import '../../editor/application/recent_colors_controller.dart';
import '../../editor/presentation/widgets/editor_modal_sheet.dart';
import 'eyedropper_overlay.dart';

/// Curated preset palette — neutrals first, then warm → cool
/// primaries. Exactly 12 entries so the picker's preset grid is
/// always two clean rows of six. The single source of truth for
/// every surface that shows quick-pick colours (the picker itself,
/// the add-text tray).
const List<Color> kColorPickerPalette = <Color>[
  Color(0xFF000000),
  Color(0xFFFFFFFF),
  Color(0xFF6B7280),
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFFFACC15),
  Color(0xFF22C55E),
  Color(0xFF06B6D4),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
];

/// The ONE colour-picking surface for the whole app.
///
/// Two levels, both compact, both live (every change is emitted
/// immediately via [onChanged] so the user sees the colour land on
/// the design — no canvas dim, no confirm step):
///
///   * **Level 1 — swatches** (the 90 % case): an action row
///     (eyedropper · editable hex · «Custom»), a recents row fed by
///     the app-wide [recentColorsControllerProvider], and a 2×6
///     preset grid.
///   * **Level 2 — custom** (tap «Custom»): HSV square, hue +
///     opacity sliders, editable hex, eyedropper, copy — with a
///     back arrow returning to level 1.
///
/// Hosting modes:
///   * **Embedded** (dock panels): leave [onClose] null — the panel
///     chrome already owns the header. Embedded bodies render level
///     1 ONLY: dock panels cap their height and scroll their body,
///     and the wheel is all drag controls — drag controls inside a
///     scrollable is a broken pattern (the finger drags colour, so
///     the user can never scroll to a hidden row). «Custom» hands
///     off to [showColorPickerSheet] with `startAtCustom`; pass
///     [title] so that sheet gets the contextual header.
///   * **Sheet** ([showColorPickerSheet]): pass [onClose] too — the
///     widget renders its own header (contextual title + the single
///     × close) and levels swap inline. The sheet is sized to its
///     content with NO internal scrolling — the one sanctioned
///     exception to the compact panel cap, because the wheel needs
///     its height and every control must stay reachable.
///
/// Cross-cutting behaviour owned here so call sites can't drift:
///   * Swatch/recent/eyedropper picks preserve the current alpha —
///     they are hue choices; opacity is owned by the level-2 slider
///     (and an explicit 8-char #AARRGGBB hex).
///   * The final colour is recorded into the app-wide recents store
///     on dispose (panel close / sheet dismiss) when it changed AND
///     the session was recents-worthy: custom wheel drags, hex
///     entries, and eyedropper picks qualify; preset-palette and
///     recents-row taps do not (tb2 5/16).
class ColorPickerBody extends ConsumerStatefulWidget {
  const ColorPickerBody({
    super.key,
    required this.initial,
    required this.onChanged,
    this.onCommitted,
    this.title,
    this.onClose,
    this.startAtCustom = false,
  });

  /// Colour shown when the picker mounts.
  final Color initial;

  /// Fires on every change, including mid-drag — hosts apply it
  /// live (`live: true` for command-based panels).
  final ValueChanged<Color> onChanged;

  /// Fires when a change settles: swatch tap, drag end, valid hex
  /// entry, eyedropper release. Command-based panels use this for
  /// the non-live commit that seals the undo step.
  final ValueChanged<Color>? onCommitted;

  /// Contextual header title («رنگ متن» / «رنگ سایه» / …). Rendered
  /// when [onClose] is provided (sheet mode); in embedded mode it
  /// titles the custom-wheel hand-off sheet instead.
  final String? title;

  /// Renders the single × close action. Null in embedded mode.
  final VoidCallback? onClose;

  /// Open directly on the custom level (used when the caller's
  /// entry point is itself a "custom colour" affordance).
  final bool startAtCustom;

  @override
  ConsumerState<ColorPickerBody> createState() => _ColorPickerBodyState();
}

class _ColorPickerBodyState extends ConsumerState<ColorPickerBody> {
  late HSVColor _hsv;
  late bool _custom;
  late final TextEditingController _hexCtrl;
  late final FocusNode _hexFocus;
  bool _hexInvalid = false;

  /// Whether this session earned a recents-MRU write: only custom
  /// wheel drags, eyedropper picks, and explicit hex entries do.
  /// Preset-palette and recents-row taps deliberately do NOT — the
  /// palette is already one tap away, so echoing it into recents
  /// only evicts genuinely custom colours (tb2 5/16).
  bool _recentsWorthy = false;

  /// The colour at mount time — NOT `widget.initial`, which hosts
  /// rebuild to the latest emitted value, making it useless for the
  /// "did the user actually change anything" check on dispose.
  late final int _initialArgb;

  /// Last ARGB this widget emitted, so [didUpdateWidget] can tell
  /// an echo of our own change apart from an external one (undo,
  /// preset apply) that must reset the wheel.
  int? _lastEmittedArgb;

  /// Cached at mount because `ref` must not be touched in
  /// [dispose]; the notifier itself is non-autoDispose and safely
  /// outlives this widget.
  late final RecentColorsController _recentsStore;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _custom = widget.startAtCustom;
    _initialArgb = widget.initial.toARGB32();
    _hexCtrl = TextEditingController(text: formatColorHex(widget.initial));
    _hexFocus = FocusNode();
    _recentsStore = ref.read(recentColorsControllerProvider.notifier);
    // Eyedropper availability keys off the canvas boundary being
    // mounted; when the panel and the canvas mount in the same
    // frame the first build can race it, so recheck once after.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ColorPickerBody old) {
    super.didUpdateWidget(old);
    final incoming = widget.initial.toARGB32();
    if (incoming != old.initial.toARGB32() && incoming != _lastEmittedArgb) {
      // External change (undo / preset) — adopt it.
      _hsv = HSVColor.fromColor(widget.initial);
      _syncHex();
    }
  }

  @override
  void dispose() {
    final current = _current;
    if (_recentsWorthy && current.toARGB32() != _initialArgb) {
      // Deferred: mutating the store synchronously here notifies
      // this very widget's recents-row watcher mid-unmount.
      final store = _recentsStore;
      Future<void>.microtask(() => store.remember(current));
    }
    _hexCtrl.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  Color get _current => _hsv.toColor();

  void _syncHex() {
    if (_hexFocus.hasFocus) return;
    final hex = formatColorHex(_current);
    if (_hexCtrl.text.toUpperCase() != hex) {
      _hexCtrl.value = TextEditingValue(
        text: hex,
        selection: TextSelection.collapsed(offset: hex.length),
      );
    }
  }

  void _emit(
    HSVColor next, {
    bool syncHex = true,
    bool committed = false,
    bool recentsWorthy = false,
  }) {
    setState(() {
      _hsv = next;
      _hexInvalid = false;
    });
    if (syncHex) _syncHex();
    final color = _current;
    if (recentsWorthy) _recentsWorthy = true;
    _lastEmittedArgb = color.toARGB32();
    widget.onChanged(color);
    if (committed) widget.onCommitted?.call(color);
  }

  /// Preserves the current alpha — a swatch tap is a hue choice,
  /// not an alpha reset.
  void _pickSwatch(Color c) {
    EditorHaptics.tap();
    _emit(HSVColor.fromColor(c).withAlpha(_hsv.alpha), committed: true);
  }

  void _onHexChanged(String raw) {
    final parsed = parseColorHex(raw);
    if (parsed == null) {
      setState(() => _hexInvalid = raw.replaceAll('#', '').isNotEmpty);
      return;
    }
    final cleanLen = raw.trim().replaceAll('#', '').replaceAll(' ', '').length;
    // Commit only on COMPLETE input while typing: a 6- or 8-digit
    // code is unambiguous, but a 3-char shorthand is also the prefix
    // of a longer code — mid-entry "F00" must not fire a commit the
    // user never meant (tb2 5/16). Shorthand commits on submit.
    if (cleanLen != 6 && cleanLen != 8) {
      setState(() => _hexInvalid = false);
      return;
    }
    _applyHex(parsed, cleanLen);
  }

  /// Keyboard submit — the explicit "I'm done" for 3-char shorthand
  /// (complete 6/8-digit entries already committed while typing).
  void _onHexSubmitted(String raw) {
    final parsed = parseColorHex(raw);
    if (parsed == null) {
      setState(() => _hexInvalid = raw.replaceAll('#', '').isNotEmpty);
      return;
    }
    final cleanLen = raw.trim().replaceAll('#', '').replaceAll(' ', '').length;
    _applyHex(parsed, cleanLen);
  }

  void _applyHex(Color parsed, int cleanLen) {
    // 3- and 6-char hex edits the RGB channels only and must keep
    // the current alpha; an explicit 8-char #AARRGGBB is an opt-in
    // alpha edit and is honoured verbatim.
    final next = HSVColor.fromColor(parsed);
    final adjusted = cleanLen == 8 ? next : next.withAlpha(_hsv.alpha);
    // An exact typed code is a custom pick — recents-worthy.
    _emit(adjusted, syncHex: false, committed: true, recentsWorthy: true);
  }

  Future<void> _eyedrop() async {
    final boundaryKey = ref.read(canvasBoardBoundaryKeyProvider);
    if (boundaryKey.currentContext == null) return;
    EditorHaptics.tap();
    final before = _hsv;
    final picked = await startCanvasEyedropper(
      context,
      boundaryKey: boundaryKey,
      // Live sampling — the colour lands on the design while the
      // finger is still down (preview channel; hosts stage it).
      onSample: (c) => _emit(HSVColor.fromColor(c).withAlpha(before.alpha)),
    );
    if (!mounted) return;
    if (picked == null) {
      // Cancelled — restore the pre-eyedrop colour AND seal it so
      // the host closes its preview session with a commit at the
      // original value, which no-ops into ZERO history entries
      // (§3 no net-zero entries; tb2 5/16). Not recents-worthy.
      _emit(before, committed: true);
      return;
    }
    EditorHaptics.confirm();
    _emit(
      HSVColor.fromColor(picked).withAlpha(before.alpha),
      committed: true,
      recentsWorthy: true,
    );
  }

  Future<void> _copyHex() async {
    EditorHaptics.tap();
    await Clipboard.setData(ClipboardData(text: formatColorHex(_current)));
  }

  bool get _eyedropperAvailable =>
      ref.read(canvasBoardBoundaryKeyProvider).currentContext != null;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topStart,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: _custom
            ? _buildCustomLevel(context)
            : _buildSwatchLevel(context),
      ),
    );
  }

  // ─── Level 1 — swatches ────────────────────────────────────────

  Widget _buildSwatchLevel(BuildContext context) {
    final recents = _visibleRecents(ref.watch(recentColorsControllerProvider));
    return Column(
      key: const ValueKey('color-picker-level-swatches'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onClose != null) ...[
          _PickerHeader(title: widget.title, onClose: widget.onClose!),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            if (_eyedropperAvailable) ...[
              _RoundIconButton(
                key: const ValueKey('color-picker-eyedropper'),
                icon: Icons.colorize_rounded,
                tooltip: context.l10n.eyedropperTooltip,
                onTap: _eyedrop,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _HexField(
                controller: _hexCtrl,
                focusNode: _hexFocus,
                invalid: _hexInvalid,
                swatch: _current,
                onChanged: _onHexChanged,
                onSubmitted: _onHexSubmitted,
              ),
            ),
            const SizedBox(width: 8),
            _CustomLevelPill(
              onTap: () {
                EditorHaptics.tap();
                if (widget.onClose != null) {
                  // Sheet mode — the host is content-sized, so the
                  // wheel can swap in place without ever scrolling.
                  setState(() => _custom = true);
                } else {
                  // Embedded mode — the dock panel is height-capped
                  // and scrollable, which the all-drag wheel must
                  // never live inside. Hand off to the content-sized
                  // sheet opened directly on the custom level; live
                  // changes flow through the same callbacks.
                  showColorPickerSheet(
                    context,
                    initial: _current,
                    title: widget.title,
                    startAtCustom: true,
                    onLiveChange: widget.onChanged,
                    onCommitted: widget.onCommitted,
                  );
                }
              },
            ),
          ],
        ),
        if (recents.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RecentsRow(
            recents: recents,
            currentRgb: _rgb(_current),
            onPick: _pickSwatch,
          ),
        ],
        const SizedBox(height: 12),
        _PresetGrid(currentRgb: _rgb(_current), onPick: _pickSwatch),
      ],
    );
  }

  /// Recents de-duped against the preset grid and themselves so
  /// the row only ever shows colours the grid can't offer.
  List<Color> _visibleRecents(List<Color> recents) {
    final paletteRgb = kColorPickerPalette.map(_rgb).toSet();
    final seen = <int>{};
    return <Color>[
      for (final c in recents)
        if (!paletteRgb.contains(_rgb(c)) && seen.add(_rgb(c))) c,
    ];
  }

  static int _rgb(Color c) => c.toARGB32() & 0x00FFFFFF;

  // ─── Level 2 — custom ──────────────────────────────────────────

  Widget _buildCustomLevel(BuildContext context) {
    return Column(
      key: const ValueKey('color-picker-level-custom'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _RoundIconButton(
              key: const ValueKey('color-picker-back'),
              icon: Icons.arrow_back_rounded,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onTap: () {
                EditorHaptics.tap();
                setState(() => _custom = false);
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title ?? context.l10n.customLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (widget.onClose != null)
              _RoundIconButton(
                key: const ValueKey('color-picker-close'),
                icon: Icons.close_rounded,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onTap: widget.onClose!,
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Adaptive height: keep the natural square on a normal sheet,
        // but let the SV field shrink (to a usable floor) when the
        // sheet is short or the keyboard is up. The field + tracks are
        // all drag surfaces, so we adapt height here rather than
        // wrapping the wheel in a scroll view (which would hijack the
        // drag — see this sheet's no-scroll rationale).
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: _SaturationValueField.minHeight,
              maxHeight: _SaturationValueField.naturalHeight,
            ),
            child: _SaturationValueField(
              key: const ValueKey('color-picker-sv'),
              hue: _hsv.hue,
              saturation: _hsv.saturation,
              value: _hsv.value,
              onChanged: (s, v) => _emit(
                _hsv.withSaturation(s).withValue(v),
                recentsWorthy: true,
              ),
              onChangeEnd: () => widget.onCommitted?.call(_current),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _GradientTrack(
          key: const ValueKey('color-picker-hue'),
          gradient: const LinearGradient(
            colors: [
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
          ),
          value: _hsv.hue / 360,
          thumbColor: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
          onChanged: (v) => _emit(
            _hsv.withHue((v * 360).clamp(0, 359.999)),
            recentsWorthy: true,
          ),
          onChangeEnd: () => widget.onCommitted?.call(_current),
        ),
        const SizedBox(height: 8),
        _GradientTrack(
          key: const ValueKey('color-picker-opacity'),
          gradient: LinearGradient(
            colors: [
              _hsv.withAlpha(1).toColor().withValues(alpha: 0),
              _hsv.withAlpha(1).toColor(),
            ],
          ),
          checker: true,
          value: _hsv.alpha,
          thumbColor: _current,
          onChanged: (v) =>
              _emit(_hsv.withAlpha(v.clamp(0, 1)), recentsWorthy: true),
          onChangeEnd: () => widget.onCommitted?.call(_current),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (_eyedropperAvailable) ...[
              _RoundIconButton(
                key: const ValueKey('color-picker-eyedropper'),
                icon: Icons.colorize_rounded,
                tooltip: context.l10n.eyedropperTooltip,
                onTap: _eyedrop,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _HexField(
                controller: _hexCtrl,
                focusNode: _hexFocus,
                invalid: _hexInvalid,
                swatch: _current,
                onChanged: _onHexChanged,
                onSubmitted: _onHexSubmitted,
              ),
            ),
            const SizedBox(width: 8),
            _RoundIconButton(
              key: const ValueKey('color-picker-copy'),
              icon: Icons.copy_rounded,
              tooltip: context.l10n.copyColorTooltip,
              onTap: _copyHex,
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Entry affordance for panels too dense to embed the picker
// ─────────────────────────────────────────────────────────────────

/// Slim tappable row — current swatch + hex readout + a rainbow
/// «Custom»-grammar ring — that opens the shared picker sheet.
/// Used by surfaces (text effect sections) where embedding the full
/// level-1 body would blow the panel height cap.
class ColorEntryButton extends StatelessWidget {
  const ColorEntryButton({
    super.key,
    required this.color,
    required this.onTap,
    this.semanticLabel,
  });

  final Color color;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            EditorHaptics.tap();
            onTap();
          },
          child: Container(
            height: 34,
            padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SwatchPreviewDot(color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  formatColorHex(color),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: tokens.textPrimary,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                const _RainbowRing(size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Header / chrome pieces
// ─────────────────────────────────────────────────────────────────

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({required this.title, required this.onClose});

  final String? title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title ?? context.l10n.colorLabel,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              fontSize: 15,
            ),
          ),
        ),
        _RoundIconButton(
          key: const ValueKey('color-picker-close'),
          icon: Icons.close_rounded,
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onTap: onClose,
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
            ),
            child: Icon(icon, size: 18, color: tokens.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// «Custom» pill — rainbow ring + label; expands to level 2.
class _CustomLevelPill extends StatelessWidget {
  const _CustomLevelPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      key: const ValueKey('color-picker-custom'),
      color: Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 12, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _RainbowRing(size: 18),
              const SizedBox(width: 6),
              Text(
                context.l10n.customLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The spectrum ring glyph shared by every "custom colour" entry
/// point — a sweep-gradient circle with a punched-out centre.
class _RainbowRing extends StatelessWidget {
  const _RainbowRing({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFFFF5252),
            Color(0xFFFFD740),
            Color(0xFF69F0AE),
            Color(0xFF40C4FF),
            Color(0xFFB388FF),
            Color(0xFFFF5252),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: size * 0.5,
          height: size * 0.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.surface,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Editable hex field (both levels)
// ─────────────────────────────────────────────────────────────────

class _HexField extends StatelessWidget {
  const _HexField({
    required this.controller,
    required this.focusNode,
    required this.invalid,
    required this.swatch,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool invalid;
  final Color swatch;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('color-picker-hex'),
      height: 36,
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: invalid ? scheme.error : tokens.border.withValues(alpha: 0.6),
          width: invalid ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          _SwatchPreviewDot(color: swatch, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.characters,
              // Hex codes are LTR content even under an RTL locale.
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: tokens.textPrimary,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f#]')),
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '#RRGGBB',
                hintStyle: TextStyle(
                  color: tokens.textPrimary.withValues(alpha: 0.25),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny current-colour dot with a checker underlay so translucent
/// colours read correctly.
class _SwatchPreviewDot extends StatelessWidget {
  const _SwatchPreviewDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _CheckerPattern(),
            ColoredBox(color: color),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Recents + preset grid
// ─────────────────────────────────────────────────────────────────

class _RecentsRow extends StatelessWidget {
  const _RecentsRow({
    required this.recents,
    required this.currentRgb,
    required this.onPick,
  });

  final List<Color> recents;
  final int currentRgb;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 10),
            child: Text(
              context.l10n.recentLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: recents.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _Swatch(
                key: ValueKey('color-picker-recent-${_hex6(recents[i])}'),
                color: recents[i],
                size: 28,
                selected: (recents[i].toARGB32() & 0x00FFFFFF) == currentRgb,
                onTap: () => onPick(recents[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Exactly two rows of six — the compact quick-pick grid.
class _PresetGrid extends StatelessWidget {
  const _PresetGrid({required this.currentRgb, required this.onPick});

  final int currentRgb;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    const perRow = 6;
    Widget row(List<Color> colors) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final c in colors)
          _Swatch(
            key: ValueKey('color-picker-swatch-${_hex6(c)}'),
            color: c,
            selected: (c.toARGB32() & 0x00FFFFFF) == currentRgb,
            onTap: () => onPick(c),
          ),
      ],
    );
    return Column(
      children: [
        row(kColorPickerPalette.sublist(0, perRow)),
        const SizedBox(height: 10),
        row(kColorPickerPalette.sublist(perRow)),
      ],
    );
  }
}

String _hex6(Color c) =>
    (c.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// Brightness-aware circular swatch with a slim selected ring and a
/// check tick — the same visual grammar in the recents row and the
/// preset grid so users learn it once.
class _Swatch extends StatefulWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 36,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final checkColor =
        ThemeData.estimateBrightnessForColor(widget.color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                border: Border.all(
                  color: widget.selected
                      ? tokens.accent
                      : tokens.border.withValues(alpha: 0.55),
                  width: widget.selected ? 2.0 : 1,
                ),
              ),
              child: widget.selected
                  ? Icon(
                      Icons.check_rounded,
                      size: widget.size * 0.4,
                      color: checkColor,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Saturation × Value field
// ─────────────────────────────────────────────────────────────────

class _SaturationValueField extends StatelessWidget {
  const _SaturationValueField({
    super.key,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double hue;
  final double saturation;
  final double value;
  final void Function(double saturation, double value) onChanged;
  final VoidCallback onChangeEnd;

  /// Natural height — an aspect-driven square is too tall at 400+dp
  /// content widths. The wheel only ever renders inside the
  /// content-sized sheet (never under the dock cap), so this is
  /// sized for usability while still letting the whole custom level
  /// fit a 667dp phone with the canvas peeking above. The caller caps
  /// the field at this height and lets it shrink to [minHeight] when
  /// the sheet is height-constrained (short screen / keyboard up).
  static const double naturalHeight = 160;

  /// Smallest still-usable height the field may shrink to before the
  /// custom level would otherwise overflow a short sheet.
  static const double minHeight = 96;

  @override
  Widget build(BuildContext context) {
    // Fills the (already bounded + capped) height handed down by the
    // Flexible/ConstrainedBox in _buildCustomLevel.
    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            void update(Offset local) {
              final s = (local.dx / size.width).clamp(0.0, 1.0);
              final v = (1 - local.dy / size.height).clamp(0.0, 1.0);
              onChanged(s.toDouble(), v.toDouble());
            }

            return _ImmediatePanArea(
              onStart: (local) {
                HapticFeedback.selectionClick();
                update(local);
              },
              onUpdate: update,
              onEnd: onChangeEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _SVFieldPainter(hue: hue)),
                  // The SV field is a physical colour space — the
                  // reticle is pinned with physical (LTR) coordinates.
                  Positioned(
                    left: saturation * size.width - 13,
                    top: (1 - value) * size.height - 13,
                    child: _Reticle(
                      color: HSVColor.fromAHSV(
                        1,
                        hue,
                        saturation,
                        value,
                      ).toColor(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SVFieldPainter extends CustomPainter {
  _SVFieldPainter({required this.hue});
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final satGradient = ui.Gradient.linear(rect.topLeft, rect.topRight, [
      Colors.white,
      HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
    ]);
    canvas.drawRect(rect, Paint()..shader = satGradient);
    final valGradient = ui.Gradient.linear(rect.topLeft, rect.bottomLeft, [
      Colors.transparent,
      Colors.black,
    ]);
    canvas.drawRect(rect, Paint()..shader = valGradient);
  }

  @override
  bool shouldRepaint(covariant _SVFieldPainter old) => old.hue != hue;
}

class _Reticle extends StatelessWidget {
  const _Reticle({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Gradient slider track (hue / opacity)
// ─────────────────────────────────────────────────────────────────

class _GradientTrack extends StatelessWidget {
  const _GradientTrack({
    super.key,
    required this.gradient,
    required this.value,
    required this.thumbColor,
    required this.onChanged,
    required this.onChangeEnd,
    this.checker = false,
  });

  final Gradient gradient;
  final double value;
  final Color thumbColor;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;
  final bool checker;

  @override
  Widget build(BuildContext context) {
    const trackHeight = 4.0;
    const thumbSize = 16.0;
    // Colour spectra are physical, not reading-direction content —
    // force LTR so hue 0° is always on the left.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: thumbSize + 6,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            void update(Offset local) {
              onChanged((local.dx / w).clamp(0.0, 1.0).toDouble());
            }

            return _ImmediatePanArea(
              onStart: (local) {
                HapticFeedback.selectionClick();
                update(local);
              },
              onUpdate: update,
              onEnd: onChangeEnd,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Center(
                    child: Container(
                      height: trackHeight,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (checker) const _CheckerPattern(),
                          DecoratedBox(
                            decoration: BoxDecoration(gradient: gradient),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: (value * w).clamp(0.0, w) - thumbSize / 2,
                    child: _SliderThumb(color: thumbColor, size: thumbSize),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SliderThumb extends StatelessWidget {
  const _SliderThumb({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _CheckerPattern(),
            ColoredBox(color: color),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Checker pattern (translucency underlay)
// ─────────────────────────────────────────────────────────────────

class _CheckerPattern extends StatelessWidget {
  const _CheckerPattern();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CheckerPainter());
  }
}

class _CheckerPainter extends CustomPainter {
  static const double _square = 5;
  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = const Color(0xFFEFEFEF);
    final darkPaint = Paint()..color = const Color(0xFFD2D2D2);
    canvas.drawRect(Offset.zero & size, lightPaint);
    for (var y = 0.0; y < size.height; y += _square) {
      for (var x = 0.0; x < size.width; x += _square) {
        final isDark = (((x / _square) + (y / _square)).floor() % 2) == 0;
        if (isDark) {
          canvas.drawRect(Rect.fromLTWH(x, y, _square, _square), darkPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────
//  HEX helpers
// ─────────────────────────────────────────────────────────────────

/// `#RRGGBB` — alpha-free, matching the picker's contract that
/// opacity is owned by the slider unless the user types an explicit
/// 8-char code.
String formatColorHex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Accepts `RGB`, `RRGGBB`, `AARRGGBB` (each optionally with `#`).
Color? parseColorHex(String raw) {
  final clean = raw
      .trim()
      .toUpperCase()
      .replaceAll('#', '')
      .replaceAll(' ', '');
  if (clean.isEmpty) return null;
  final int? n = int.tryParse(clean, radix: 16);
  if (n == null) return null;
  switch (clean.length) {
    case 6:
      return Color(0xFF000000 | n);
    case 8:
      return Color(n);
    case 3:
      final r = (n >> 8) & 0xF;
      final g = (n >> 4) & 0xF;
      final b = n & 0xF;
      final expanded = (r * 0x11) << 16 | (g * 0x11) << 8 | (b * 0x11);
      return Color(0xFF000000 | expanded);
    default:
      return null;
  }
}

// ─────────────────────────────────────────────────────────────────
//  Sheet host — the content-sized, no-dim floating home
// ─────────────────────────────────────────────────────────────────

/// Opens the shared [ColorPickerBody] as a compact floating sheet —
/// the single colour-selection surface for every call site that
/// can't embed the body directly, and the ONLY home of the custom
/// wheel (embedded panels hand off here via `startAtCustom`).
///
/// Deliberately **no barrier dim**: the colour is applied live via
/// [onLiveChange] and the user must see it land on the design.
/// Exactly one close action (the header ×; swipe-down and tapping
/// outside are gesture equivalents, not extra buttons).
///
/// Sized to its content with NO internal scrolling — the wheel is
/// all drag controls, so a scroll view around it would be
/// unusable (the finger drags colour, never the viewport).
///
/// Returns the last colour the user picked, or `null` if they
/// dismissed without changing anything. Recents bookkeeping happens
/// inside the picker itself — callers only apply the colour.
Future<Color?> showColorPickerSheet(
  BuildContext context, {
  required Color initial,
  ValueChanged<Color>? onLiveChange,
  ValueChanged<Color>? onCommitted,
  String? title,
  bool startAtCustom = false,
}) async {
  Color? last;
  // Barrier NONE (contract §9): live colour — never dim the canvas
  // behind the picker. Card + handle come from the shared modal
  // host; keyboard-aware so the hex field stays above the IME.
  await showEditorSheet<void>(
    context,
    barrier: EditorSheetBarrier.none,
    keyboardAware: true,
    builder: (ctx) => _ColorPickerSheet(
      initial: initial,
      title: title ?? ctx.l10n.colorLabel,
      startAtCustom: startAtCustom,
      onChanged: (c) {
        last = c;
        onLiveChange?.call(c);
      },
      onCommitted: onCommitted,
    ),
  );
  // Resolves the same way for ×, swipe-down, and tap-outside — the
  // caller's final commit never depends on *how* the sheet closed.
  return last;
}

class _ColorPickerSheet extends StatelessWidget {
  const _ColorPickerSheet({
    required this.initial,
    required this.title,
    required this.onChanged,
    required this.onCommitted,
    required this.startAtCustom,
  });

  final Color initial;
  final String title;
  final ValueChanged<Color> onChanged;
  final ValueChanged<Color>? onCommitted;
  final bool startAtCustom;

  @override
  Widget build(BuildContext context) {
    // Chrome (floating card, handle, keyboard inset, safe area) comes
    // from the shared modal host (tb2 8/16); this body keeps only the
    // picker padding + the height-adaptive Flexible.
    //
    // Flexible bounds the body to the sheet's available height
    // (full-screen minus the keyboard inset), so the custom level's
    // adaptive SV field can shrink instead of overflowing when the
    // keyboard is up on a short phone. Loose fit → on a normal sheet
    // the body still takes its natural, content-sized height.
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 14),
      child: ColorPickerBody(
        initial: initial,
        title: title,
        startAtCustom: startAtCustom,
        onChanged: onChanged,
        onCommitted: onCommitted,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Gesture: immediate-pan area
// ─────────────────────────────────────────────────────────────────

/// Wraps a control so pointer events are consumed **outside** the
/// gesture arena entirely — see the original rationale in the
/// pre-redesign picker: the SV field and tracks live inside
/// scrollables whose recognizers would otherwise steal the drag.
/// A raw [Listener] always receives moves for a captured pointer;
/// the inner no-op drag [GestureDetector] claims the arena so the
/// ancestor scrollable never scrolls mid-drag.
class _ImmediatePanArea extends StatefulWidget {
  const _ImmediatePanArea({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_ImmediatePanArea> createState() => _ImmediatePanAreaState();
}

class _ImmediatePanAreaState extends State<_ImmediatePanArea> {
  int? _activePointer;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _activePointer = event.pointer;
        widget.onStart(event.localPosition);
      },
      onPointerMove: (event) {
        if (event.pointer != _activePointer) return;
        widget.onUpdate(event.localPosition);
      },
      onPointerUp: (event) {
        if (event.pointer == _activePointer) {
          _activePointer = null;
          widget.onEnd();
        }
      },
      onPointerCancel: (event) {
        if (event.pointer == _activePointer) {
          _activePointer = null;
          widget.onEnd();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // No-op handlers exist purely to claim arena ownership.
        onVerticalDragStart: (_) {},
        onVerticalDragUpdate: (_) {},
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        child: widget.child,
      ),
    );
  }
}
