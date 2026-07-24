import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n.dart';
import '../engine/modules/shape/shape_catalogue.dart';
import '../engine/modules/shape/shape_layer.dart';
import '../engine/modules/shape/shape_paths.dart';
import 'widgets/editor_modal_sheet.dart';

/// Bottom sheet for picking a [ShapeKind] — shared by the editor's
/// "Add shape" and "Replace shape" flows (Phase 4 plan §5.2, split
/// out of editor_screen.dart). Returns `null` on dismiss/back so the
/// caller can bail cleanly.
///
/// Pass [currentKind] for the Replace flow so its tile lights up as
/// selected; leave it `null` for a plain Add-shape picker. [title]/
/// [subtitle] default to the Add-shape copy.
Future<ShapeKind?> pickShapeKind(
  BuildContext context, {
  String? title,
  String? subtitle,
  ShapeKind? currentKind,
}) {
  final l10n = context.l10n;
  // FULL barrier (contract §9: pickers). Card + handle + the 0.75
  // height cap come from the shared modal host (tb2 8/16).
  return showEditorSheet<ShapeKind>(
    context,
    maxHeightFraction: 0.75,
    builder: (ctx) {
      final tokens = AppTokens.of(ctx);
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                title ?? l10n.addShapeTitle,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                subtitle ?? l10n.addShapeSubtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: tokens.textSecondary,
                ),
              ),
            ),
            // One section per [ShapeKindCatalogueSection] with
            // a discreet uppercase header — keeps the grid
            // scannable now that the catalogue spans bubbles,
            // symbols and four arrow directions on top of the
            // basic primitives.
            for (var s = 0; s < kShapeCatalogueSections.length; s++) ...[
              if (s > 0) const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  _shapeSectionLabel(l10n, s).toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tokens.textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
                children: [
                  for (final entry in _pickerEntriesForSection(l10n, tokens, s))
                    _ShapePickerTile(
                      kind: entry.kind,
                      label: entry.label,
                      gradient: entry.gradient,
                      selected: currentKind == entry.kind,
                      onTap: () {
                        EditorHaptics.tap();
                        Navigator.pop(ctx, entry.kind);
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Picker entries for a single section, with section-stable
/// gradients (alternating accent/accentDeep) so each section reads
/// as visually coherent.
List<_ShapePickerEntry> _pickerEntriesForSection(
  AppLocalizations l10n,
  AppTokens tokens,
  int sectionIndex,
) {
  final a = tokens.accent;
  final b = tokens.accentDeep;
  final entries = kShapeCatalogueSections[sectionIndex].entries;
  return [
    for (var i = 0; i < entries.length; i++)
      _ShapePickerEntry(
        entries[i].kind,
        _shapeKindLabel(l10n, entries[i].kind),
        i.isEven ? [a, b] : [b, a],
      ),
  ];
}

String _shapeSectionLabel(AppLocalizations l10n, int sectionIndex) {
  return switch (sectionIndex) {
    0 => l10n.shapeSectionBasic,
    1 => l10n.shapeSectionBubbles,
    2 => l10n.shapeSectionSymbols,
    3 => l10n.shapeSectionLinesArrows,
    _ => kShapeCatalogueSections[sectionIndex].title,
  };
}

String _shapeKindLabel(AppLocalizations l10n, ShapeKind kind) {
  return switch (kind) {
    ShapeKind.rectangle => l10n.shapeKindRectangle,
    ShapeKind.roundedRectangle => l10n.shapeKindRoundedRectangle,
    ShapeKind.circle => l10n.circleOption,
    ShapeKind.oval => l10n.shapeKindOval,
    ShapeKind.triangle => l10n.shapeKindTriangle,
    ShapeKind.diamond => l10n.shapeKindDiamond,
    ShapeKind.hexagon => l10n.shapeKindHexagon,
    ShapeKind.star => l10n.starOption,
    ShapeKind.heart => l10n.heartOption,
    ShapeKind.speechBubble => l10n.shapeKindSpeechBubble,
    ShapeKind.quoteBubble => l10n.shapeKindQuoteBubble,
    ShapeKind.plus => l10n.shapeKindPlus,
    ShapeKind.check => l10n.shapeKindCheck,
    ShapeKind.cross => l10n.shapeKindCross,
    ShapeKind.line => l10n.shapeKindLine,
    ShapeKind.arrow => l10n.shapeKindArrowRight,
    ShapeKind.arrowLeft => l10n.shapeKindArrowLeft,
    ShapeKind.arrowUp => l10n.shapeKindArrowUp,
    ShapeKind.arrowDown => l10n.shapeKindArrowDown,
  };
}

/// Picker entry catalogue row.
class _ShapePickerEntry {
  const _ShapePickerEntry(this.kind, this.label, this.gradient);
  final ShapeKind kind;
  final String label;
  final List<Color> gradient;
}

/// Premium grid tile used in the shape picker. Renders an actual
/// preview of [kind] inside a gradient panel so users see what
/// they're picking — not just an icon glyph. Tile lights up with
/// the accent tint when [selected] is true (used by the Replace
/// flow to mark the current kind).
class _ShapePickerTile extends StatelessWidget {
  const _ShapePickerTile({
    required this.kind,
    required this.label,
    required this.gradient,
    required this.onTap,
    this.selected = false,
  });

  final ShapeKind kind;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.08)
                : tokens.surfaceMuted,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? tokens.accent.withValues(alpha: 0.6)
                  : tokens.border.withValues(alpha: 0.5),
              width: selected ? 1.4 : 0.5,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: _ShapePickerPreview(kind: kind, gradient: gradient),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? tokens.accent : tokens.textPrimary,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightweight visual-only preview of a [ShapeKind] for picker
/// tiles. Mirrors the production renderer for the box-based kinds
/// (so a roundedRectangle preview already shows the rounded look)
/// and uses the same [ShapePaths] geometry for path-based kinds so
/// the tile looks identical to what the user inserts.
class _ShapePickerPreview extends StatelessWidget {
  const _ShapePickerPreview({required this.kind, required this.gradient});

  final ShapeKind kind;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final paint = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: gradient,
    );
    final shadow = BoxShadow(
      color: gradient.first.withValues(alpha: 0.32),
      blurRadius: 12,
      offset: const Offset(0, 4),
    );
    switch (kind) {
      case ShapeKind.rectangle:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: paint,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [shadow],
          ),
        );
      case ShapeKind.roundedRectangle:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: paint,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [shadow],
          ),
        );
      case ShapeKind.circle:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: paint,
            shape: BoxShape.circle,
            boxShadow: [shadow],
          ),
        );
      case ShapeKind.oval:
        // Squashed pill so the picker preview reads as an oval at a
        // glance — distinct from the circle tile beside it.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: paint,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [shadow],
            ),
          ),
        );
      case ShapeKind.triangle:
      case ShapeKind.diamond:
      case ShapeKind.hexagon:
      case ShapeKind.star:
      case ShapeKind.heart:
      case ShapeKind.speechBubble:
      case ShapeKind.quoteBubble:
      case ShapeKind.plus:
      case ShapeKind.check:
      case ShapeKind.cross:
      case ShapeKind.line:
      case ShapeKind.arrow:
      case ShapeKind.arrowLeft:
      case ShapeKind.arrowUp:
      case ShapeKind.arrowDown:
        return CustomPaint(
          painter: _PreviewPainter(kind: kind, color: gradient.first),
        );
    }
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({required this.kind, required this.color});
  final ShapeKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroked = isStrokedShapeKind(kind);
    final paint = Paint()
      ..color = color
      ..style = stroked ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroked ? 4 : 0;
    canvas.drawPath(_pathFor(kind, size), paint);
  }

  Path _pathFor(ShapeKind k, Size size) {
    switch (k) {
      case ShapeKind.triangle:
        return ShapePaths.triangle(size);
      case ShapeKind.diamond:
        return ShapePaths.diamond(size);
      case ShapeKind.hexagon:
        return ShapePaths.hexagon(size);
      case ShapeKind.star:
        return ShapePaths.star(size);
      case ShapeKind.heart:
        return ShapePaths.heart(size);
      case ShapeKind.speechBubble:
        return ShapePaths.speechBubble(size);
      case ShapeKind.quoteBubble:
        return ShapePaths.quoteBubble(size);
      case ShapeKind.plus:
        return ShapePaths.plus(size);
      case ShapeKind.check:
        return ShapePaths.check(size);
      case ShapeKind.cross:
        return ShapePaths.cross(size);
      case ShapeKind.line:
        return ShapePaths.line(size);
      case ShapeKind.arrow:
        return ShapePaths.arrow(size);
      case ShapeKind.arrowLeft:
        return ShapePaths.arrowLeft(size);
      case ShapeKind.arrowUp:
        return ShapePaths.arrowUp(size);
      case ShapeKind.arrowDown:
        return ShapePaths.arrowDown(size);
      case ShapeKind.rectangle:
      case ShapeKind.roundedRectangle:
      case ShapeKind.circle:
      case ShapeKind.oval:
        return Path();
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) =>
      old.kind != kind || old.color != color;
}
