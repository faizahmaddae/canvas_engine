// Shared control kit (Phase 2A §1). LayoutSliderCard (the
// expandable preset-chip card) was retired in the 2026-07
// compactness pass — the Layout panel uses plain EditorSliderRows
// now. Only the shared flat-row text styles remain here.

import 'package:flutter/material.dart';

import '../../../../../app/theme/app_tokens.dart';

/// Label style shared by every migrated flat-row slider in the
/// Background/Border/Shadow precision disclosures — larger and
/// bolder than [EditorSliderRow]'s shape/image default, so the
/// text-panel row keeps its existing look after unifying onto the
/// shared primitive.
TextStyle? flatSliderLabelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodyMedium?.copyWith(
    color: AppTokens.of(context).textPrimary,
    fontWeight: FontWeight.w600,
    fontSize: 13,
  );
}

/// Readout style shared by the same rows — tabular figures keep the
/// digits from jittering width while dragging.
TextStyle? flatSliderReadoutStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelMedium?.copyWith(
    color: AppTokens.of(context).textSecondary,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
