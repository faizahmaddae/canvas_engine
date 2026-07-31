import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/l10n.dart';
import '../../editor/application/canvas_capture.dart';
import '../../editor/application/recent_colors_controller.dart';
import '../../editor/presentation/widgets/editor_breakpoints.dart';
import '../../../app/ui/app_modal_sheet.dart';
import 'eyedropper_overlay.dart';
import '../../../app/theme/app_icons.dart';

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
///     (eyedropper · editable hex · «Custom») above THE SHELF — one
///     3×6 grid of identical cells whose first row is reserved for
///     the colours the user mixed (fed by the app-wide
///     [recentColorsControllerProvider]) and whose remaining two
///     rows are [kColorPickerPalette].
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
///   * A colour is recorded into the app-wide recents store at the
///     COMMIT FENCE ([_seal]) — not on dispose — so a mixed colour
///     lands in the shelf's leading slot the moment it settles.
///     Only mixing earns a slot: wheel settle, a complete hex entry,
///     an eyedropper release. Palette and shelf taps do not, because
///     the palette is one tap away in the same grid and echoing it
///     would only evict genuinely custom colours (tb2 5/16).
///   * The shelf shows exactly what the store holds — visible
///     capacity and [RecentColorsController] cap are both 6, so no
///     colour the user made is ever hidden.
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
  final GlobalKey _hexFieldKey = GlobalKey();
  bool _hexInvalid = false;

  /// The colour at mount time — NOT `widget.initial`, which hosts
  /// rebuild to the latest emitted value, making it useless for the
  /// "did the user actually change anything" check in [_seal].
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
    // Bring the field above the IME once the keyboard has actually
    // taken its space. The panel now reserves `viewInsets.bottom`
    // (dock_sheet_chrome), so there IS somewhere to scroll to; without
    // this the field could still start below the fold in a tall panel.
    // Two frames: one for the focus, one for the inset to land.
    _hexFocus.addListener(() {
      if (!_hexFocus.hasFocus || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _hexFieldKey.currentContext;
          if (ctx == null || !mounted) return;
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        });
      });
    });
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
    _lastEmittedArgb = color.toARGB32();
    widget.onChanged(color);
    if (committed) _seal(recentsWorthy: recentsWorthy);
  }

  /// The single commit fence: seals the host's undo step and, when
  /// this particular commit earned it, records the colour in the
  /// app-wide MRU.
  ///
  /// The store write used to happen once in [dispose] — which meant
  /// nothing the user did in front of the shelf could ever fill it,
  /// and the row they were meant to populate was already gone by the
  /// time it was written. Writing here instead puts a mixed colour in
  /// the leading slot the moment it settles.
  ///
  /// Worthiness is per-COMMIT, deliberately not a sticky session
  /// flag: a wheel drag followed by a palette tap must not launder
  /// the preset into the MRU. Only mixing earns a slot — wheel
  /// settle, a complete hex entry, an eyedropper release — because
  /// the palette is one tap away in the same grid, so echoing it
  /// would evict genuinely custom colours (tb2 5/16).
  ///
  /// No shift-under-finger hazard: the wheel commits on level 2 with
  /// the shelf unmounted, the eyedropper commits under a full-screen
  /// overlay, and hex commits while the keyboard owns focus.
  void _seal({required bool recentsWorthy}) {
    final color = _current;
    widget.onCommitted?.call(color);
    if (recentsWorthy && color.toARGB32() != _initialArgb) {
      _recentsStore.remember(color);
    }
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
      duration: AppMotion.reveal,
      curve: AppMotion.curve,
      alignment: AlignmentDirectional.topStart,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        switchInCurve: AppMotion.curve,
        switchOutCurve: AppMotion.curve,
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
                icon: AppIcons.eyedropper,
                tooltip: context.l10n.eyedropperTooltip,
                onTap: _eyedrop,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _HexField(
                key: _hexFieldKey,
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
        const SizedBox(height: 12),
        ColorShelf(current: _current, onPick: _pickSwatch),
      ],
    );
  }

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
              icon: AppIcons.back,
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
                icon: AppIcons.close,
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
              onChangeEnd: () => _seal(recentsWorthy: true),
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
          onChangeEnd: () => _seal(recentsWorthy: true),
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
          onChangeEnd: () => _seal(recentsWorthy: true),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (_eyedropperAvailable) ...[
              _RoundIconButton(
                key: const ValueKey('color-picker-eyedropper'),
                icon: AppIcons.eyedropper,
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
              icon: AppIcons.copyValue,
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
              border: Border.all(color: tokens.borderStrong),
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
          icon: AppIcons.close,
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
              border: Border.all(color: tokens.borderStrong),
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
            border: Border.all(color: tokens.borderStrong),
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
    super.key,
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
          // `borderStrong`: this hairline is the field's ONLY outline
          // and measured 1.17:1 light / 1.10:1 dark — below both the
          // boundaries that got earlier rounds rejected, on a text
          // input.
          color: invalid ? scheme.error : tokens.borderStrong,
          width: invalid ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          _SwatchPreviewDot(color: swatch, size: 18),
          const SizedBox(width: 8),
          Expanded(
            // The field had no accessible name at all — an EditText
            // with content-desc="" reading only its own hex value.
            child: MergeSemantics(
              // `EditableText` is its own semantics boundary, so a bare
              // Semantics wrapper produced a SECOND, empty,
              // non-clickable EditText carrying the name while the real
              // field stayed unnamed — two edit boxes at identical
              // bounds. Merging collapses the subtree onto the field's
              // own node.
              child: Semantics(
                label: context.l10n.hexColorFieldLabel,
                textField: true,
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

/// THE SHELF — one 3×6 grid of identical cells, and the whole of the
/// picker's level-1 lower section.
///
/// Recents and the palette used to be two objects: a 28dp
/// horizontally-scrolling row inside an `Expanded` (so two entries
/// stretched across the full width, leaving the gap that reads as
/// broken), above an unlabelled 2×6 of 36dp circles on a different
/// pitch, with the whole recents block vanishing when the store was
/// empty. Three sizes, two layout engines, and a section whose
/// height changed between openings of the same panel.
///
/// They are one grid now. Group identity rides on POSITION (the
/// user's own colours always lead), on the only structural asymmetry
/// left (only row 1 can hold empty slots — the palette is always
/// full), on a hairline plus the extra group gutter, and on an
/// explicit semantics container. Never on a second visual language.
///
/// Height is constant in every state, so the section can no longer
/// appear, disappear, or resize under an `AnimatedSize`.
class ColorShelf extends ConsumerWidget {
  const ColorShelf({super.key, required this.current, required this.onPick});

  /// The colour the shelf should mark as selected.
  final Color current;

  /// Fired with the tapped colour. Hosts apply their own alpha
  /// policy; [ColorPickerBody] preserves the working alpha, which is
  /// the behaviour every other host wants too.
  final ValueChanged<Color> onPick;

  /// Columns, and therefore also the number of reserved slots in
  /// row 1. Matches [RecentColorsController] capacity so display
  /// equals truth: nothing the user made is ever hidden.
  static const int slots = 6;

  /// Recents de-duped against the palette rows and themselves, so a
  /// colour can never appear twice in one grid.
  ///
  /// Palette wins every collision. With the two groups sharing one
  /// grid that rule stops being arbitrary: the same red in two cells
  /// of one surface would read as a bug. Owned here rather than by a
  /// host so the two surfaces that render a shelf cannot disagree —
  /// the composer's tray used to apply the OPPOSITE rule.
  static List<Color> visibleRecents(List<Color> recents) {
    final paletteRgb = kColorPickerPalette.map(_rgbOf).toSet();
    final seen = <int>{};
    return <Color>[
      for (final c in recents)
        if (!paletteRgb.contains(_rgbOf(c)) && seen.add(_rgbOf(c))) c,
    ].take(slots).toList(growable: false);
  }

  static int _rgbOf(Color c) => c.toARGB32() & 0x00FFFFFF;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final mine = visibleRecents(ref.watch(recentColorsControllerProvider));
    final currentRgb = _rgbOf(current);
    final currentArgb = current.toARGB32();
    // ONE gutter, both axes, DERIVED — and spent through explicit
    // separators rather than `spaceBetween`. The old grid clamped the
    // gutter for its vertical gap but let `spaceBetween` distribute
    // the UNCLAMPED value horizontally, so above ~384dp of content
    // width the two silently diverged. Centring the intrinsic-width
    // grid splits any leftover evenly instead.
    return LayoutBuilder(
      builder: (context, constraints) {
        // The ceiling is 12, not the old grid's 24: a two-row grid
        // spent the gutter once vertically, this one spends it three
        // times (row 1 → seam → palette → palette), and the colour
        // panel must fit its dock cap without internal scroll —
        // drag controls inside a scrollable is the pattern this
        // picker exists to avoid. At phone widths the DERIVED value
        // is ~14 anyway, so the clamp only bites on wide panels,
        // where it reads as a deliberate compact block rather than
        // scattered dots.
        final gutter =
            ((constraints.maxWidth - slots * kMinHitTarget) / (slots - 1))
                .clamp(2.0, 12.0);

        Widget row(List<Widget> cells) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) SizedBox(width: gutter),
              cells[i],
            ],
          ],
        );

        final mineCells = <Widget>[
          for (var i = 0; i < slots; i++)
            if (i < mine.length)
              _Swatch(
                key: ValueKey('color-picker-recent-${_hex6(mine[i])}'),
                color: mine[i],
                semanticLabel: colorSwatchName(context, mine[i]),
                // A mixed colour is an EXACT colour, so it compares on
                // full ARGB; a palette entry is a hue, and taps
                // preserve alpha, so those compare RGB-masked. One
                // documented rule, two correct answers. The row
                // self-dedupes on RGB, so the HEX6 keys stay unique.
                selected: mine[i].toARGB32() == currentArgb,
                onTap: () => onPick(mine[i]),
              )
            else
              _EmptySlot(key: ValueKey('color-picker-slot-$i')),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShelfHeading(
              // Shown ONLY at zero, and in the heading's trailing slot
              // rather than where the swatches go: the empty state is
              // the shape of the full state, pre-drawn, plus one line
              // saying what fills it. Six empty rings would be honest
              // about capacity and say nothing about why it is empty.
              hint: mine.isEmpty ? context.l10n.colorsMixedHint : null,
            ),
            Semantics(
              container: true,
              label: context.l10n.recentLabel,
              child: Center(child: row(mineCells)),
            ),
            SizedBox(height: gutter),
            // The group seam: a hairline spanning the grid, with the
            // gutter above and below doing the Gestalt work.
            // Direction-agnostic, and it costs one token.
            Container(height: 1, color: tokens.border),
            SizedBox(height: gutter),
            Semantics(
              container: true,
              label: context.l10n.colorsLabel,
              child: Column(
                children: [
                  for (
                    var start = 0;
                    start < kColorPickerPalette.length;
                    start += slots
                  ) ...[
                    if (start > 0) SizedBox(height: gutter),
                    Center(
                      child: row([
                        for (final c
                            in kColorPickerPalette.skip(start).take(slots))
                          _Swatch(
                            key: ValueKey('color-picker-swatch-${_hex6(c)}'),
                            color: c,
                            semanticLabel: colorSwatchName(context, c),
                            selected: (c.toARGB32() & 0x00FFFFFF) == currentRgb,
                            onTap: () => onPick(c),
                          ),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The shelf's single heading. One heading for the whole grid — a
/// second one is what made the old section read as two objects.
class _ShelfHeading extends StatelessWidget {
  const _ShelfHeading({this.hint});

  final String? hint;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(
      // Full strength: at 75% this caption measured 3.32:1 light and
      // 4.32:1 dark — normal text, so 4.5:1 applies.
      color: tokens.textSecondary,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(context.l10n.colorsLabel, style: label),
          if (hint != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint!,
                style: label?.copyWith(fontWeight: FontWeight.w400),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A reserved, un-filled slot in the shelf's first row.
///
/// Inert by construction: no ink, no press state, and excluded from
/// semantics so a screen reader hears six colours and not six
/// nothings. Its whole job is to make "two of six filled" read as a
/// state rather than an accident.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: kMinHitTarget,
        height: kMinHitTarget,
        child: Center(
          child: Container(
            width: _Swatch.discSize,
            height: _Swatch.discSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Clearly perceivable, unmistakably inert beside the
              // 4.06:1 live swatch ring.
              border: Border.all(
                color: tokens.textSecondary.withValues(alpha: 0.30),
              ),
            ),
          ),
        ),
      ),
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
    this.semanticLabel,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// Spoken name. Without it a screen reader reads twelve unnamed
  /// "button"s in a row — the swatch's only identity is its fill.
  final String? semanticLabel;

  /// The painted disc. ONE size for every cell in the shelf — the
  /// old 28dp-recents / 36dp-preset split is most of why the two
  /// groups read as unrelated objects.
  static const double discSize = 32;

  /// Outer diameter of the selection halo: the disc plus a 3dp
  /// transparent gap and a 2dp stroke, leaving 1dp of clearance
  /// inside the [kMinHitTarget] cell.
  static const double haloSize = discSize + 2 * 3 + 2 * 2;

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
    // Painted at [_Swatch.discSize]; the TOUCH box is the
    // [kMinHitTarget] floor, which is also the grid's cell pitch.
    final disc = Container(
      width: _Swatch.discSize,
      height: _Swatch.discSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color,
        border: Border.all(
          // Every swatch gets a real boundary, selected or not.
          // Whichever end of the ramp matches the sheet disappears
          // into it — white on cream in light mode, black on ink in
          // dark — so a brightness-conditional ring only ever fixes
          // one of the two. `textSecondary` is a mid-tone in BOTH
          // themes. 0.70 computed to 3.23:1 against white but
          // MEASURED 2.95:1 once rendered (the 1dp ring antialiases
          // against the fill it encloses), so it is 0.85: 4.34:1
          // against white and 4.06:1 against the light sheet, 6.31:1
          // against black and 5.20:1 against the dark sheet. The old
          // 55%-of-`border` hairline was 1.31:1.
          color: tokens.textSecondary.withValues(alpha: 0.85),
        ),
      ),
      child: widget.selected
          ? Icon(
              AppIcons.confirm,
              size: _Swatch.discSize * 0.4,
              color: checkColor,
            )
          : null,
    );

    final swatch = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          child: SizedBox(
            width: kMinHitTarget,
            height: kMinHitTarget,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Selection is an OUTER halo, separated from the
                  // disc — never a thicker edge ON it. Drawn on the
                  // swatch edge it had to contrast against arbitrary
                  // user colour and measured 1.49:1 against the grey
                  // preset in light and 1.02:1 against green in dark:
                  // invisible exactly where it matters. Out here it
                  // only ever has to clear the sheet — accentText is
                  // 6.73:1 light / 7.47:1 dark on `surface`.
                  AnimatedOpacity(
                    duration: AppMotion.state,
                    curve: AppMotion.curve,
                    opacity: widget.selected ? 1 : 0,
                    child: Container(
                      width: _Swatch.haloSize,
                      height: _Swatch.haloSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: tokens.accentText, width: 2),
                      ),
                    ),
                  ),
                  // Only the DISC scales under the finger — a selected
                  // swatch's halo stays put instead of pumping.
                  AnimatedScale(
                    scale: _down ? 0.94 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: disc,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      selected: widget.selected,
      // The node must carry the ACTION too. Naming it while excluding
      // the subtree's own semantics left the accessibility tree with a
      // Button that had `clickable=false` and no click action, so every
      // swatch was announced and then unusable — worse than the
      // unnamed-but-tappable state it replaced.
      onTap: widget.onTap,
      child: ExcludeSemantics(child: swatch),
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
  await showAppSheet<void>(
    context,
    barrier: AppSheetBarrier.none,
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

/// Spoken name for a swatch in [kColorPickerPalette].
///
/// The grid's twelve entries carry no text, so a screen reader read
/// twelve bare "button"s in a row — the fill was the only identity
/// and it is exactly the channel a blind user does not have. Colours
/// outside the fixed palette (recents, eyedropper picks) fall back to
/// their hex.
String colorSwatchName(BuildContext context, Color c) {
  final l10n = context.l10n;
  return switch (c.toARGB32() & 0x00FFFFFF) {
    0x000000 => l10n.colorBlack,
    0xFFFFFF => l10n.colorWhite,
    0x6B7280 => l10n.colorSlate,
    0xEF4444 => l10n.colorRed,
    0xF59E0B => l10n.colorAmber,
    0xFACC15 => l10n.colorYellow,
    0x22C55E => l10n.colorGreen,
    0x06B6D4 => l10n.colorCyan,
    0x3B82F6 => l10n.colorBlue,
    0x8B5CF6 => l10n.colorPurple,
    0xEC4899 => l10n.colorPink,
    0x14B8A6 => l10n.colorTeal,
    _ => l10n.colorCustomSwatch('#${_hex6(c)}'),
  };
}
