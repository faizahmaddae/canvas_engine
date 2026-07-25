import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// Canonical small section label used inside editor panels
/// and bottom sheets.
///
/// Spec (matches the Text panel's `_PanelSectionLabel` — single
/// source of truth so the editor's section rhythm stays aligned
/// across every surface):
///   * sentence-case/localized text
///   * 11 sp, weight 700, letterSpacing 0
///   * `AppTokens.textSecondary`
///   * 4 / 4 / 4 / 6 inset (extra bottom space for visual breathing
///     room before the section content)
///
/// If a host needs a different inset (e.g. a sheet that already
/// applies its own vertical rhythm), pass a custom [padding].
///
/// Paint's `_Label`/`_SectionLabel` copies uppercase their text with
/// `letterSpacing: 0.8` instead — a real visual difference, not
/// drift to silently erase. Pass [uppercase]`: true` and
/// [letterSpacing]`: 0.8` to fold those copies in without changing
/// Paint's visible casing.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 6),
    this.uppercase = false,
    this.letterSpacing = 0,
    this.trailing,
  });

  final String text;
  final EdgeInsetsGeometry padding;

  /// When true, renders [text] via [String.toUpperCase] — matches
  /// Paint's `_Label`/`_SectionLabel` convention.
  final bool uppercase;

  final double letterSpacing;

  /// Optional widget pinned to the row's trailing edge — the section's
  /// current VALUE, sitting on the label's own line.
  ///
  /// A value stacked under its label costs a whole extra row to say
  /// one short thing, and panels are the surface with the least room
  /// to spare. Reserved for values, not for actions: a label row is
  /// not a place a user should have to look for a control.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      uppercase ? text.toUpperCase() : text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
        color: AppTokens.of(context).textSecondary,
      ),
    );
    return Padding(
      padding: padding,
      child: trailing == null
          ? label
          : Row(
              children: [
                label,
                const Spacer(),
                Flexible(child: trailing!),
              ],
            ),
    );
  }
}
