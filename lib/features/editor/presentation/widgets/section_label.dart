import 'package:flutter/material.dart';

/// Canonical small section label used inside editor panels
/// and bottom sheets.
///
/// Spec (matches the Paint and Text panel labels — single source of
/// truth so the editor's section rhythm stays aligned across every
/// surface):
///   * sentence-case/localized text
///   * 11 sp, weight 700, letterSpacing 0
///   * `colorScheme.onSurfaceVariant`
///   * 4 / 4 / 4 / 6 inset (extra bottom space for visual breathing
///     room before the section content)
///
/// If a host needs a different inset (e.g. a sheet that already
/// applies its own vertical rhythm), pass a custom [padding].
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 6),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
