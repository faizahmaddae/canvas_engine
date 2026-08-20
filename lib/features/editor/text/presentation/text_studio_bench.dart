import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_icons.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../l10n/l10n.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/selection_controller.dart';
import '../../engine/modules/text/text_layer.dart';
import '../../presentation/widgets/editor_breakpoints.dart';
import '../../presentation/widgets/layer_overflow_sheet.dart';
import '../../toolbar/domain/sibling_swipe_strategy.dart';
import '../../toolbar/domain/sub_tools/widget_sub_tool.dart';
import '../../toolbar/presentation/sub_tool_sheet.dart';
import '../application/text_tool_controller.dart';
import '../domain/font_catalog.dart';
import 'text_bodies.dart';
import 'text_edit_flow.dart';

/// The Text Studio bench — text mode's persistent dock surface
/// (`docs/text-studio-redesign-2026-08.md` §4).
///
/// Two rows, always the same two questions answered:
///
///  * **identity row** (top) — *what this text is*: a live specimen
///    chip (the layer's words in its full treatment — the permanent
///    door back to writing), the font pill (family name in its own
///    face), the visual-px size pill and the ink dot. The row IS the
///    typographic state display; each element opens its depth
///    surface.
///  * **aspect row** (bottom) — *which aspect you are dressing*:
///    three wide, state-carrying chips — سبک (presets + B/I/U +
///    effects), چیدمان (alignment, spacing, direction, resize
///    behaviour) and بیشتر (structural layer actions).
///
/// The bench replaces the six-tile `SlotStrip` (`TextModeToolbar`) —
/// six anonymous icons that displayed almost nothing about the text
/// they edited.
class TextStudioBench extends ConsumerWidget {
  const TextStudioBench({super.key});

  /// Dock strip height while text mode owns it. The paint bench's
  /// envelope, so mode switches reflow between two same-sized
  /// benches.
  static double dockHeight(BuildContext context) =>
      EditorBreakpoints.isCompact(context) ? 108 : 124;

  /// Sibling-swipe walk order for the sheets the bench opens.
  static const List<String> sheetOrder = <String>[
    'font',
    'size',
    'color',
    'styles',
    'layout',
  ];

  static TextLayer? selectedTextLayer(WidgetRef ref) {
    final selection = ref.watch(selectionControllerProvider);
    if (!selection.hasSelection) return null;
    final layer = ref
        .watch(renderedDocumentProvider)
        .layerById(selection.selectedId!);
    // Emoji stickers are TextLayer instances but route to the sticker
    // toolbar — the bench must never claim them.
    if (layer is TextLayer && !layer.isSticker) return layer;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = selectedTextLayer(ref);
    if (layer == null) return const SizedBox.shrink();
    final session = ref.watch(textToolControllerProvider);
    final compact = EditorBreakpoints.isCompact(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, compact ? 4 : 8, 12, 6),
      child: Column(
        key: const ValueKey('text-studio-bench'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            // 46 keeps the cluster's tap zones at the 44dp floor once
            // its 1px border is spent on each edge.
            height: compact ? 42 : 46,
            child: _IdentityRow(layer: layer, session: session),
          ),
          SizedBox(height: compact ? 4 : 8),
          Expanded(
            child: _AspectRow(layer: layer, session: session),
          ),
        ],
      ),
    );
  }
}

/// D-e (tb5 accessibility decision): editor chrome clamps its text
/// scale to 1.0–1.3 — the bench's fixed two-row envelope cannot grow
/// with the system setting.
TextScaler _benchTextScaler(BuildContext context) => MediaQuery.textScalerOf(
  context,
).clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3);

// ─────────────────────────────────────────────────────────────────
// Identity row
// ─────────────────────────────────────────────────────────────────

class _IdentityRow extends ConsumerWidget {
  const _IdentityRow({required this.layer, required this.session});

  final TextLayer layer;
  final TextSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final values = EditorValueFormat.of(context);
    final fontEntry = _entryForFamily(layer.style.fontFamily);
    return Row(
      children: [
        Expanded(
          child: _SpecimenChip(
            layer: layer,
            onTap: () {
              EditorHaptics.tap();
              ctrl.closeSheet();
              showEditTextLayerFlow(context, ref, layer);
            },
          ),
        ),
        const SizedBox(width: 8),
        // The type spec reads as ONE instrument — face and size are
        // two halves of a single bordered cluster, not two more
        // free-floating lozenges.
        _TypeCluster(
          fontLabel:
              fontEntry?.labelFor(
                Localizations.localeOf(context).languageCode,
              ) ??
              context.l10n.fontTool,
          fontFamily: layer.style.fontFamily,
          sizeLabel:
              // VISUAL px — what the user sees after corner drags,
              // not the raw fontSize underneath (tb2 12/16).
              values.px(ctrl.visualFontSizeOf(layer).round()),
          fontActive: session.openSheet == 'font',
          sizeActive: session.openSheet == 'size',
          onFontTap: () => ctrl.toggleSheet('font'),
          onSizeTap: () => ctrl.toggleSheet('size'),
        ),
        const SizedBox(width: 8),
        _InkDot(
          color: layer.style.color,
          active: session.openSheet == 'color',
          onTap: () => ctrl.toggleSheet('color'),
        ),
      ],
    );
  }

  static FontEntry? _entryForFamily(String? family) {
    if (family == null) return null;
    for (final e in kFontCatalog) {
      if (e.family == family) return e;
    }
    return null;
  }
}

/// The live specimen: the layer's own words rendered with its full
/// treatment (face, ink, weight/italic/underline, outline, shadow,
/// plate) on an adaptive card. Tapping returns to writing — the one
/// permanent, obvious answer to "how do I change the words".
class _SpecimenChip extends StatelessWidget {
  const _SpecimenChip({required this.layer, required this.onTap});

  final TextLayer layer;
  final VoidCallback onTap;

  /// Recognition aid, not a reading surface — one line, capped.
  static const int _excerptCap = 18;

  /// The card behind the specimen adapts to the ink so white text
  /// never vanishes: same palette the styles panel's preview tiles
  /// use.
  static const Color _lightCard = Color(0xFFF5F5F7);
  static const Color _darkCard = Color(0xFF1F2937);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final style = layer.style;
    final excerpt = _excerptOf(layer.content);
    final direction = textDirectionForContent(
      layer.content,
      mode: layer.textDirectionMode,
    );
    final backdropIsDark =
        style.backgroundColor == null && style.color.computeLuminance() > 0.5;
    final cardColor = backdropIsDark ? _darkCard : _lightCard;

    final fill = TextStyle(
      fontFamily: style.fontFamily,
      fontSize: 16,
      height: 1.0,
      color: style.color,
      fontWeight: style.fontWeight,
      fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
      decoration: style.underline ? TextDecoration.underline : null,
      decorationColor: style.color,
      shadows: style.shadowColor == null
          ? null
          : [
              Shadow(
                color: style.shadowColor!,
                // Scaled down — the chip is a fraction of the layer.
                blurRadius: style.shadowBlur * 0.4,
                offset: style.shadowOffset * 0.3,
              ),
            ],
    );

    Widget glyphs = Text(
      excerpt,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: _benchTextScaler(context),
      style: fill,
    );
    if (style.outlineColor != null) {
      glyphs = Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          Text(
            excerpt,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: _benchTextScaler(context),
            style: fill.copyWith(
              color: null,
              decoration: null,
              shadows: null,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeJoin = StrokeJoin.round
                ..strokeWidth = (style.outlineWidth * 0.5).clamp(0.5, 3.0)
                ..color = style.outlineColor!,
            ),
          ),
          glyphs,
        ],
      );
    }
    if (style.backgroundColor != null) {
      glyphs = TextBackgroundBox(
        color: style.backgroundColor!,
        radiusPercent: style.backgroundRadius,
        paddingX: (style.backgroundPaddingX * 0.3).clamp(2.0, 8.0),
        paddingY: (style.backgroundPaddingY * 0.3).clamp(1.0, 5.0),
        child: glyphs,
      );
    }

    return Semantics(
      button: true,
      label: context.l10n.editTextAction,
      // The hero of the row: the only lifted surface on the bench,
      // so the eye lands on the text itself before its controls.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: tokens.textPrimary.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const ValueKey('text-specimen'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, end: 6),
              // On very narrow phones the identity row can squeeze the
              // specimen down to pencil-well width; the well yields
              // (the whole chip is already the edit door) instead of
              // striping the bench with an overflow.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showPencil = constraints.maxWidth >= 76;
                  return Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Directionality(
                            textDirection: direction,
                            // The specimen's own semantics are noise — the
                            // chip is announced as "edit text".
                            child: ExcludeSemantics(child: glyphs),
                          ),
                        ),
                      ),
                      if (showPencil) ...[
                        const SizedBox(width: 6),
                        // The pencil sits in its own tinted well so the chip
                        // reads as editable, not decorated.
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: backdropIsDark
                                ? _lightCard.withValues(alpha: 0.14)
                                : tokens.surfaceMuted.withValues(alpha: 0.9),
                          ),
                          child: Icon(
                            AppIcons.editText,
                            size: 14,
                            color: backdropIsDark
                                ? _lightCard.withValues(alpha: 0.85)
                                : tokens.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _excerptOf(String content) {
    final oneLine = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (oneLine.length <= _excerptCap) return oneLine;
    return oneLine.substring(0, _excerptCap);
  }
}

/// The type-spec cluster: family name (in its own face) and visual px
/// as two tap zones inside ONE hairline-bordered instrument, split by
/// an internal divider. Grouping the two values that describe "the
/// type" kills the lozenge-soup read the separate pills had.
class _TypeCluster extends StatelessWidget {
  const _TypeCluster({
    required this.fontLabel,
    required this.fontFamily,
    required this.sizeLabel,
    required this.fontActive,
    required this.sizeActive,
    required this.onFontTap,
    required this.onSizeTap,
  });

  final String fontLabel;
  final String? fontFamily;
  final String sizeLabel;
  final bool fontActive;
  final bool sizeActive;
  final VoidCallback onFontTap;
  final VoidCallback onSizeTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    Widget zone({
      required Key key,
      required String semanticLabel,
      required bool active,
      required VoidCallback onTap,
      required Widget child,
      required BorderRadiusDirectional radius,
      required BoxConstraints constraints,
    }) {
      return Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: active
              ? tokens.accent.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: radius.resolve(Directionality.of(context)),
          child: InkWell(
            key: key,
            borderRadius: radius.resolve(Directionality.of(context)),
            onTap: () {
              EditorHaptics.tap();
              onTap();
            },
            child: Container(
              constraints: constraints,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: ExcludeSemantics(child: child),
            ),
          ),
        ),
      );
    }

    // The inner radius hugs the outer 12 minus the 1px border.
    const innerR = Radius.circular(11);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          zone(
            key: const ValueKey('text-pill-font'),
            semanticLabel: context.l10n.fontTool,
            active: fontActive,
            onTap: onFontTap,
            radius: const BorderRadiusDirectional.horizontal(start: innerR),
            constraints: const BoxConstraints(minWidth: 64, maxWidth: 118),
            child: Text(
              fontLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: _benchTextScaler(context),
              style: TextStyle(
                // The zone IS a specimen: the name renders in its
                // own face, so the current font reads at a glance.
                fontFamily: fontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: fontActive ? tokens.accentText : tokens.textPrimary,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            color: tokens.border.withValues(alpha: 0.7),
          ),
          zone(
            key: const ValueKey('text-pill-size'),
            semanticLabel: context.l10n.sizeTool,
            active: sizeActive,
            onTap: onSizeTap,
            radius: const BorderRadiusDirectional.horizontal(end: innerR),
            constraints: const BoxConstraints(minWidth: 56, maxWidth: 84),
            child: Text(
              sizeLabel,
              textScaler: _benchTextScaler(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: sizeActive ? tokens.accentText : tokens.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Current-ink dot — the paint bench's grammar: the live colour with
/// a ring, and the door to the colour sheet.
class _InkDot extends StatelessWidget {
  const _InkDot({
    required this.color,
    required this.active,
    required this.onTap,
  });

  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: context.l10n.textColorTitle,
      child: InkWell(
        key: const ValueKey('text-ink-dot'),
        customBorder: const CircleBorder(),
        onTap: () {
          EditorHaptics.tap();
          onTap();
        },
        // The visual is a 34dp swatch; the tap target is the full
        // 44dp hit-floor box around it.
        child: SizedBox(
          width: kMinHitTarget,
          height: kMinHitTarget,
          child: Center(
            // Resting: one crisp swatch. Active: the accent ring
            // appears around it — the double-ring-at-rest read is
            // gone.
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 34,
              height: 34,
              padding: EdgeInsets.all(active ? 3 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? tokens.accent : Colors.transparent,
                  width: active ? 2 : 0,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: tokens.border.withValues(alpha: 0.8),
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Aspect row
// ─────────────────────────────────────────────────────────────────

class _AspectRow extends ConsumerWidget {
  const _AspectRow({required this.layer, required this.session});

  final TextLayer layer;
  final TextSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(textToolControllerProvider.notifier);
    final l10n = context.l10n;
    final style = layer.style;

    // Treatment badges: which decorations are live right now. The
    // chip carries its state so the user never opens a sheet to
    // learn nothing is on.
    final lookBadges = <Color>[
      if (style.shadowColor != null) style.shadowColor!,
      if (style.outlineColor != null) style.outlineColor!,
      if (style.backgroundColor != null) style.backgroundColor!,
    ];

    final alignIcon = switch (style.alignment) {
      TextAlign.left || TextAlign.start => AppIcons.textAlignLeft,
      TextAlign.right || TextAlign.end => AppIcons.textAlignRight,
      _ => AppIcons.textAlignCenter,
    };

    final tokens = AppTokens.of(context);
    // ONE connected bar, not three chips adrift: three equal segments
    // split by hairlines inside a single bordered track. The row
    // reads as one instrument with three faces — the same "connected
    // control" weight the alignment pill and script switcher carry.
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: tokens.border.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        // Stretch, not center: a segment's tap target is the track's
        // full height, never the 18dp its icon+label happen to need
        // (the thin-chip bug the first bench shipped).
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('text-aspect-look'),
              icon: AppIcons.stylePresets,
              label: l10n.stylesTool,
              active: session.openSheet == 'styles',
              badges: lookBadges,
              onTap: () => ctrl.toggleSheet('styles'),
            ),
          ),
          _segmentDivider(tokens),
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('text-aspect-layout'),
              icon: alignIcon,
              label: l10n.layoutTool,
              active: session.openSheet == 'layout',
              onTap: () => ctrl.toggleSheet('layout'),
            ),
          ),
          _segmentDivider(tokens),
          Expanded(
            child: _AspectSegment(
              key: const ValueKey('text-aspect-more'),
              icon: AppIcons.moreActions,
              label: l10n.moreActionsSemantics,
              active: false,
              onTap: () {
                ctrl.closeSheet();
                final scaffold = Scaffold.maybeOf(context);
                showLayerOverflowSheet(
                  context,
                  ref,
                  layer: layer,
                  onOpenLayers: scaffold == null
                      ? null
                      : () => scaffold.openEndDrawer(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Widget _segmentDivider(AppTokens tokens) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(vertical: 8),
    color: tokens.border.withValues(alpha: 0.55),
  );
}

/// One segment of the aspect bar: icon + label (+ treatment badges).
/// The active segment carries the accent tint edge-to-edge inside the
/// shared track.
class _AspectSegment extends StatelessWidget {
  const _AspectSegment({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badges = const <Color>[],
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final List<Color> badges;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: active
            ? tokens.accent.withValues(alpha: 0.16)
            : Colors.transparent,
        child: InkWell(
          onTap: () {
            EditorHaptics.tap();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: active ? tokens.accentText : tokens.textPrimary,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: _benchTextScaler(context),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: active ? tokens.accentText : tokens.textPrimary,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    for (final b in badges)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 2),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: b,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: tokens.border.withValues(alpha: 0.7),
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Sheet host
// ─────────────────────────────────────────────────────────────────

/// In-dock sheet panel: routes the active sheet id → its body and
/// renders it inside the dock's `expanded` slot, wrapped in the
/// shared [SubToolSheet] chrome with sibling-swipe across
/// [TextStudioBench.sheetOrder].
class TextStudioSheetPanel extends ConsumerWidget {
  const TextStudioSheetPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(textToolControllerProvider);
    final sheetId = session.openSheet;
    if (sheetId == null) return const SizedBox.shrink();
    final layer = TextStudioBench.selectedTextLayer(ref);
    if (layer == null) return const SizedBox.shrink();
    final body = _bodyFor(sheetId);
    if (body == null) return const SizedBox.shrink();

    final swipe = SiblingSwipeStrategy<String>(
      order: TextStudioBench.sheetOrder,
    );
    final prevId = swipe.prev(sheetId);
    final nextId = swipe.next(sheetId);
    final ctrl = ref.read(textToolControllerProvider.notifier);

    final subTool = WidgetSubTool(
      headerTitle: _sheetTitle(context, sheetId),
      headerIcon: _sheetIcon(sheetId),
      builder: (ctx, _) => body(ctx, ref, layer),
    );

    return SubToolSheet(
      subTool: subTool,
      onClose: ctrl.closeSheet,
      // Undo lives on the persistent floating action in the editor
      // chrome — a duplicate chip in every sheet header read as a
      // second history.
      onUndo: null,
      onPrev: prevId == null ? null : () => ctrl.toggleSheet(prevId),
      onNext: nextId == null ? null : () => ctrl.toggleSheet(nextId),
    );
  }

  /// Body builder per sheet id. A stale persisted id (e.g. a removed
  /// legacy sheet) resolves to null and renders nothing — safe.
  static Widget Function(BuildContext, WidgetRef, TextLayer)? _bodyFor(
    String id,
  ) => switch (id) {
    'font' => TextBodies.fontBody,
    'size' => TextBodies.sizeBody,
    'color' => TextBodies.colorBody,
    'styles' => TextBodies.stylesBody,
    'layout' => TextBodies.layoutBody,
    _ => null,
  };

  static String _sheetTitle(BuildContext context, String id) {
    final l10n = context.l10n;
    return switch (id) {
      'font' => l10n.fontTool,
      'size' => l10n.sizeTool,
      'color' => l10n.colorLabel,
      'styles' => l10n.stylesTool,
      'layout' => l10n.layoutTool,
      // The id itself is a more useful signal than a stale word if a
      // future sheet is added without its l10n case.
      _ => id,
    };
  }

  static IconData _sheetIcon(String id) => switch (id) {
    'font' => AppIcons.textTool,
    'size' => AppIcons.fontSize,
    'color' => AppIcons.colorTool,
    'styles' => AppIcons.stylePresets,
    'layout' => AppIcons.textAlignCenter,
    _ => AppIcons.moreActions,
  };
}
