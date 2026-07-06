// Shared control kit (Phase 2A §1): extracted verbatim from the
// text_mode_toolbar library (text_panel_primitives.dart) so every
// tool's panels can reuse it. Rename-only promotion; no behaviour
// change.

import 'package:flutter/material.dart';

import '../../../../../app/theme/app_tokens.dart';

/// Hairline divider rendered above an "Adjust precisely" expanded
/// body so the appearing sliders read as a clearly-bounded new
/// block rather than a sudden vertical jump. Shared by Size,
/// Background, Border, and Shadow precision disclosures.
class PrecisionDivider extends StatelessWidget {
  const PrecisionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Container(
        height: 1,
        color: AppTokens.of(context).border.withValues(alpha: 0.35),
      ),
    );
  }
}
