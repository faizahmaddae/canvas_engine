import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../engine/modules/paint/paint_layer.dart';
import '../domain/paint_tool_type.dart';
import '../../../../app/theme/app_icons.dart';

// ─── Per-tool capability matrix ───────────────────────────────────
//
// Drives which sub-tool tiles the strip renders once a tool is
// armed. `tool` is always present so re-picking is one tap. Pure
// data, no enum changes — this lives next to the toolbar because
// it's a UI-layer decision, not a domain rule.
Set<String> allowedPaintSlotsFor(PaintToolType? tool) {
  if (tool == null) return const {'tool'};
  switch (tool) {
    case PaintToolType.freestyle:
      return const {'tool', 'color', 'size', 'opacity'};
    case PaintToolType.arrow:
      return const {'tool', 'color', 'size', 'opacity'};
    // Style is wired to the line-family tools (Solid=line,
    // Dashed=dashLine, Dotted=dashDotLine). Picking a style in
    // the sheet calls selectTool() — so the slot is meaningful
    // only on these three kinds. Shapes don't expose Style
    // because there is no per-layer dash on the engine side.
    case PaintToolType.line:
    case PaintToolType.dashLine:
    case PaintToolType.dashDotLine:
      return const {'tool', 'color', 'size', 'opacity', 'dash'};
    case PaintToolType.rectangle:
    case PaintToolType.circle:
    case PaintToolType.hexagon:
      return const {'tool', 'color', 'size', 'fill', 'opacity'};
    case PaintToolType.polygon:
      return const {'tool', 'color', 'size', 'fill', 'opacity', 'polygon'};
    case PaintToolType.eraser:
      return const {'tool', 'size'};
    case PaintToolType.blur:
      return const {'tool', 'blur'};
  }
}

/// The capability matrix for a SELECTED, already-committed layer
/// (tb4 3/14).
///
/// Keyed by the layer's kind rather than by an armed tool, because
/// restyling answers a different question: not "what can this tool
/// draw?" but "what about this stroke can still change?". `tool`
/// stays present as the escape hatch — picking a tool clears the
/// selection and starts a new stroke.
///
/// The line family shows `dash` because a committed line kind can be
/// restyled into its peers; box shapes show `fill`; only a blur patch
/// shows `blur`. Nothing here is a control that does nothing, which
/// is what the old selected-layer slot-hiding guard was papering over.
Set<String> allowedPaintSlotsForKind(PaintKind kind) {
  switch (kind) {
    case PaintKind.freestyle:
    case PaintKind.arrow:
      return const {'tool', 'color', 'size', 'opacity'};
    case PaintKind.line:
    case PaintKind.dashLine:
    case PaintKind.dashDotLine:
      return const {'tool', 'color', 'size', 'opacity', 'dash'};
    case PaintKind.rectangle:
    case PaintKind.circle:
    case PaintKind.hexagon:
      return const {'tool', 'color', 'size', 'fill', 'opacity'};
    case PaintKind.polygon:
      return const {'tool', 'color', 'size', 'fill', 'opacity', 'polygon'};
    case PaintKind.blur:
      return const {'tool', 'blur'};
  }
}

// ─── Human-friendly value labels ──────────────────────────────────
//
// Tile `valueText` shows a word, not a number. Numbers stay inside
// the sub-tool sheet for power users.
String paintStrokeWord(AppLocalizations l10n, double w) {
  if (w <= 4) return l10n.thinOption;
  if (w <= 12) return l10n.mediumOption;
  if (w <= 24) return l10n.thickOption;
  return l10n.heavyOption;
}

String paintOpacityWord(AppLocalizations l10n, double alpha01) {
  final p = (alpha01.clamp(0.0, 1.0) * 100).round();
  if (p <= 35) return l10n.lightOption;
  if (p <= 75) return l10n.normalOption;
  return l10n.strongOption;
}

String paintBlurWord(AppLocalizations l10n, double r) {
  if (r < 1) return l10n.noneOption;
  if (r <= 16) return l10n.softOption;
  return l10n.strongOption;
}

/// The same word for a COMMITTED layer's kind. `null` when the kind
/// isn't a line style (the caller then falls back to the armed tool).
String? paintDashWordForKind(AppLocalizations l10n, PaintKind? kind) {
  return switch (kind) {
    PaintKind.line => l10n.solidOption,
    PaintKind.dashLine => l10n.dashedOption,
    PaintKind.dashDotLine => l10n.dottedOption,
    _ => null,
  };
}

String paintDashWordForTool(AppLocalizations l10n, PaintToolType? tool) {
  switch (tool) {
    case PaintToolType.dashLine:
      return l10n.dashedOption;
    case PaintToolType.dashDotLine:
      return l10n.dottedOption;
    case PaintToolType.line:
      return l10n.solidOption;
    default:
      return l10n.solidOption;
  }
}

class PaintSpec {
  const PaintSpec({required this.id, required this.icon, required this.label});

  final String id;
  final IconData icon;
  final String label;
}

/// Localised tile/sheet-header label for [spec]. Lives next to the
/// spec registry so the strip and the sheet chrome resolve display
/// copy from one place (moved here from paint_mode_expansion.dart
/// in tb1 14/17, dissolving the toolbar⇄expansion import cycle).
String paintSpecLabel(AppLocalizations l10n, PaintSpec spec) {
  return switch (spec.id) {
    'tool' => l10n.toolLabel,
    'color' => l10n.colorLabel,
    'size' => l10n.sizeTool,
    'fill' => l10n.fillLabel,
    'opacity' => l10n.strokeOpacityLabel,
    'blur' => l10n.blurLabel,
    'polygon' => l10n.sidesTool,
    'dash' => l10n.styleLabel,
    _ => spec.label,
  };
}

// ─── Tool registry ─────────────────────────────────────────────
//
// Flat single-tier strip — Tool · Color · Size · Fill · Opacity ·
// Blur · Sides · Dash. Ordered by expected frequency of use.
final List<PaintSpec> paintToolSpecs = <PaintSpec>[
  PaintSpec(id: 'tool', icon: AppIcons.freehandTool, label: 'Tool'),
  PaintSpec(id: 'color', icon: AppIcons.colorTool, label: 'Color'),
  PaintSpec(id: 'size', icon: AppIcons.strokeWeight, label: 'Size'),
  PaintSpec(id: 'fill', icon: AppIcons.paintFill, label: 'Fill'),
  PaintSpec(id: 'opacity', icon: AppIcons.opacity, label: 'Opacity'),
  PaintSpec(id: 'blur', icon: AppIcons.blur, label: 'Blur'),
  PaintSpec(id: 'polygon', icon: AppIcons.polygonTool, label: 'Sides'),
  PaintSpec(id: 'dash', icon: AppIcons.dashStyle, label: 'Style'),
];
