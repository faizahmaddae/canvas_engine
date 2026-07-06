// Shared control kit (Phase 2A §1): extracted verbatim from the
// text_mode_toolbar library (text_bodies.dart) so every tool's
// panels can reuse it. Rename-only promotion; no behaviour change.

import 'package:flutter/material.dart';

import '../../../../../app/theme/app_tokens.dart';

/// Small section label used by panels that group multiple
/// affordances (Background → Shape / Color / …). Same visual weight
/// as the old `_AdvancedGroupHeader` so the eye treats them as
/// peer-level dividers, not nested headers.
class PanelSectionLabel extends StatelessWidget {
  const PanelSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppTokens.of(context).textSecondary,
        ),
      ),
    );
  }
}
