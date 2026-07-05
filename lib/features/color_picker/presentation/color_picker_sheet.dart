import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../editor/presentation/widgets/color_swatch_dot.dart';
import '../../editor/presentation/widgets/section_label.dart';

/// Reusable colour picker bottom sheet — the single colour-selection
/// surface for the whole editor.
///
/// Returns the picked colour, or `null` if dismissed.
Future<Color?> showColorPickerSheet(
  BuildContext context, {
  required Color initial,
  List<Color> recents = const [],
  ValueChanged<Color>? onLiveChange,
  String? title,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (ctx) => ColorPickerSheet(
      initial: initial,
      recents: recents,
      onLiveChange: onLiveChange,
      title: title ?? context.l10n.colorLabel,
    ),
  );
}

class ColorPickerSheet extends StatefulWidget {
  const ColorPickerSheet({
    super.key,
    required this.initial,
    this.recents = const [],
    this.onLiveChange,
    required this.title,
  });

  final Color initial;
  final List<Color> recents;
  final ValueChanged<Color>? onLiveChange;
  final String title;

  @override
  State<ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<ColorPickerSheet> {
  late HSVColor _hsv;
  late TextEditingController _hexCtrl;
  late FocusNode _hexFocus;
  bool _hexInvalid = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexCtrl = TextEditingController(text: _formatHex(widget.initial));
    _hexFocus = FocusNode();
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  Color get _current => _hsv.toColor();

  void _emit(HSVColor next, {bool syncHex = true}) {
    setState(() {
      _hsv = next;
      _hexInvalid = false;
    });
    if (syncHex && !_hexFocus.hasFocus) {
      final hex = _formatHex(_current);
      if (_hexCtrl.text.toUpperCase() != hex) {
        _hexCtrl.value = TextEditingValue(
          text: hex,
          selection: TextSelection.collapsed(offset: hex.length),
        );
      }
    }
    widget.onLiveChange?.call(_current);
  }

  void _onHexChanged(String raw) {
    final parsed = _parseHex(raw);
    if (parsed == null) {
      setState(() => _hexInvalid = raw.replaceAll('#', '').isNotEmpty);
      return;
    }
    setState(() => _hexInvalid = false);
    // The hex display is `#RRGGBB` (6 chars, alpha-free) so the
    // user can only see and edit the RGB channels — opacity is
    // owned by the dedicated slider above. Parsing a 3- or 6-char
    // input must therefore preserve the current alpha; otherwise
    // typing a fresh hex silently snaps opacity back to 100 % and
    // the slider readout no longer matches the swatch.
    //
    // An explicit 8-char `#AARRGGBB` is treated as an opt-in alpha
    // edit (the user typed the alpha bytes themselves), so its
    // alpha is honoured verbatim.
    final cleanLen = raw
        .trim()
        .toUpperCase()
        .replaceAll('#', '')
        .replaceAll(' ', '')
        .length;
    final next = HSVColor.fromColor(parsed);
    final adjusted = cleanLen == 8 ? next : next.withAlpha(_hsv.alpha);
    _emit(adjusted, syncHex: false);
  }

  @override
  Widget build(BuildContext context) {
    // A single, soft, near-paper surface for the whole sheet — no inner
    // cards, just space and typography.
    final sheetColor = AppTokens.of(context).surface;

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ColoredBox(
            color: sheetColor,
            child: Column(
              children: [
                _GrabHandle(),
                _Header(
                  title: widget.title,
                  onDone: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(ctx).pop(_current);
                  },
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      24,
                      6,
                      24,
                      MediaQuery.viewInsetsOf(ctx).bottom + 32,
                    ),
                    children: [
                      // 1. Color square — saturation/value field.
                      _SaturationValueField(
                        hue: _hsv.hue,
                        saturation: _hsv.saturation,
                        value: _hsv.value,
                        onChanged: (s, v) =>
                            _emit(_hsv.withSaturation(s).withValue(v)),
                      ),
                      const SizedBox(height: 22),
                      // 2. Hue.
                      _HueSlider(
                        hue: _hsv.hue,
                        onChanged: (h) => _emit(_hsv.withHue(h)),
                      ),
                      const SizedBox(height: 14),
                      // 3. Opacity.
                      _OpacitySlider(
                        color: _hsv.withAlpha(1).toColor(),
                        alpha: _hsv.alpha,
                        onChanged: (a) => _emit(_hsv.withAlpha(a)),
                      ),
                      const SizedBox(height: 22),
                      // 4. HEX input.
                      _HexLine(
                        controller: _hexCtrl,
                        focusNode: _hexFocus,
                        invalid: _hexInvalid,
                        onChanged: _onHexChanged,
                      ),
                      if (widget.recents.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        SectionLabel(context.l10n.recentLabel),
                        const SizedBox(height: 4),
                        _RecentsRow(
                          recents: widget.recents,
                          selected: _current,
                          onPick: (c) {
                            HapticFeedback.selectionClick();
                            _emit(HSVColor.fromColor(c));
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
//  Header / chrome
// ---------------------------------------------------------------------------

class _GrabHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        decoration: BoxDecoration(
          color: AppTokens.of(context).textPrimary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onDone});

  final String title;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                fontSize: 17,
              ),
            ),
          ),
          TextButton(
            onPressed: onDone,
            style: TextButton.styleFrom(
              foregroundColor: AppTokens.of(context).accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
            child: Text(context.l10n.doneAction),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Saturation × Value field — the hero
// ---------------------------------------------------------------------------

class _SaturationValueField extends StatelessWidget {
  const _SaturationValueField({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final void Function(double saturation, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 11,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _SVFieldPainter(hue: hue)),
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

// ---------------------------------------------------------------------------
//  Sliders — full-width, label above, no chrome
// ---------------------------------------------------------------------------

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _LabeledSlider(
      label: context.l10n.hueLabel,
      readout: '${hue.round()}°',
      child: _GradientTrack(
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
        value: hue / 360,
        thumbColor: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
        onChanged: (v) => onChanged((v * 360).clamp(0, 359.999)),
      ),
    );
  }
}

class _OpacitySlider extends StatelessWidget {
  const _OpacitySlider({
    required this.color,
    required this.alpha,
    required this.onChanged,
  });
  final Color color;
  final double alpha;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _LabeledSlider(
      label: context.l10n.opacityLabel,
      readout: '${(alpha * 100).round()}%',
      child: _GradientTrack(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 1)],
        ),
        checker: true,
        value: alpha,
        thumbColor: color.withValues(alpha: alpha),
        onChanged: (v) => onChanged(v.clamp(0, 1)),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.readout,
    required this.child,
  });
  final String label;
  final String readout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: SectionLabel(
                  label,
                  padding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
                ),
              ),
              Text(
                readout,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppTokens.of(context).textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class _GradientTrack extends StatelessWidget {
  const _GradientTrack({
    required this.gradient,
    required this.value,
    required this.thumbColor,
    required this.onChanged,
    this.checker = false,
  });

  final Gradient gradient;
  final double value;
  final Color thumbColor;
  final ValueChanged<double> onChanged;
  final bool checker;

  @override
  Widget build(BuildContext context) {
    const trackHeight = 4.0;
    const thumbSize = 16.0;
    return SizedBox(
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

// ---------------------------------------------------------------------------
//  HEX line — borderless, integrated, with subtle underline on focus
// ---------------------------------------------------------------------------

class _HexLine extends StatefulWidget {
  const _HexLine({
    required this.controller,
    required this.focusNode,
    required this.invalid,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool invalid;
  final ValueChanged<String> onChanged;

  @override
  State<_HexLine> createState() => _HexLineState();
}

class _HexLineState extends State<_HexLine> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = AppTokens.of(context);
    final accent = widget.invalid
        ? scheme.error
        : (_focused
              ? tokens.textPrimary
              : tokens.textPrimary.withValues(alpha: 0.10));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2, right: 2),
          child: Row(
            children: [
              Text(
                context.l10n.hexLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tokens.textSecondary.withValues(alpha: 0.7),
                  letterSpacing: 0.1,
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) =>
                    FadeTransition(opacity: a, child: c),
                child: widget.invalid
                    ? Text(
                        context.l10n.invalidLabel,
                        key: const ValueKey('inv'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.error,
                        ),
                      )
                    : const SizedBox(key: ValueKey('ok'), height: 14),
              ),
            ],
          ),
        ),
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: tokens.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f#]')),
            LengthLimitingTextInputFormatter(9),
          ],
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            hintText: '#RRGGBB',
            hintStyle: TextStyle(
              color: tokens.textPrimary.withValues(alpha: 0.25),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: accent, width: 1),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accent, width: 1),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
          ),
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Recents — subtle chips with hairline selection
// ---------------------------------------------------------------------------

class _RecentsRow extends StatelessWidget {
  const _RecentsRow({
    required this.recents,
    required this.selected,
    required this.onPick,
  });

  final List<Color> recents;
  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: recents.length,
        separatorBuilder: (_, i) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final c = recents[i];
          final isSelected = c.toARGB32() == selected.toARGB32();
          return ColorSwatchDot(
            color: c,
            selected: isSelected,
            onTap: () => onPick(c),
            size: 36,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Checker pattern
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
//  HEX helpers
// ---------------------------------------------------------------------------

String _formatHex(Color c) {
  final argb = c.toARGB32();
  final rgb = argb & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? _parseHex(String raw) {
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

// ---------------------------------------------------------------------------
//  Gesture: immediate-pan area
// ---------------------------------------------------------------------------

/// Wraps a child widget so pointer events are consumed **outside** the
/// gesture arena entirely.
///
/// Why a raw [Listener] instead of `GestureDetector` /
/// `RawGestureDetector`: the picker lives inside a
/// `DraggableScrollableSheet` + `ListView`, both of which install pan
/// recognizers that compete for the same pointer. Even an
/// `ImmediateMultiDragGestureRecognizer` is a *participant* in the
/// arena and can be disambiguated against — leading to the "stuck"
/// feeling where a vertical drag inside a slider hijacks the sheet.
///
/// `Listener` doesn't participate in the arena at all. It always
/// receives the pointer events for as long as the pointer is down,
/// regardless of what other recognizers up the tree decide. We pair it
/// with an `AbsorbPointer`-free hit-test (`HitTestBehavior.opaque`) so
/// the down event is still routed to ancestors for the *first* frame
/// (so e.g. taps still work) but every subsequent move event for that
/// pointer flows through us until release.
///
/// To prevent the parent scroll from also picking up the same pointer,
/// we wrap the entire control in a vertical-drag `GestureDetector` that
/// accepts immediately and does nothing — this win-on-down behaviour
/// kicks competing recognizers out of the arena before they can move
/// the sheet.
class _ImmediatePanArea extends StatefulWidget {
  const _ImmediatePanArea({
    required this.onStart,
    required this.onUpdate,
    required this.child,
  });

  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;
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
        if (event.pointer == _activePointer) _activePointer = null;
      },
      onPointerCancel: (event) {
        if (event.pointer == _activePointer) _activePointer = null;
      },
      // Single-axis recognizers wrapped around the child force the
      // gesture arena to resolve in our favour: by claiming both
      // vertical AND horizontal drag immediately, we kick the parent
      // scroll's `VerticalDragGestureRecognizer` (used by both
      // `ListView` and `DraggableScrollableSheet`) out of the arena
      // before it can move the sheet.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // No-op: handlers exist purely to claim arena ownership.
        onVerticalDragStart: (_) {},
        onVerticalDragUpdate: (_) {},
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        child: widget.child,
      ),
    );
  }
}
