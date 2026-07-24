import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';

/// Canonical "Adjust precisely" expand/collapse disclosure.
///
/// Unifies the 10 header/disclosure copies inventoried in the Phase
/// 4 plan (four header-only `_AdjustHeader`s in shape/image shadow,
/// image adjust, image border, plus a `_VignetteHeader` copy — all
/// icon + two-line title/subtitle; five self-stateful
/// `_*PrecisionAdvanced` shells in the text panels — single-line,
/// no icon, title text itself swaps between the closed/open copy).
///
/// Both grammars are expressed here without changing either
/// family's pixels: pass [icon] + [subtitle] for the icon-header
/// look, or leave both null and pass [titleOpen] for the text-panel
/// swap-on-open look (`titleOpen` defaults to [titleClosed], so a
/// caller that only ever shows one string doesn't need to think
/// about it).
///
/// The chevron rotates 0.25 turns over [animationDuration]
/// (default 180 ms / easeOutCubic — the Phase 4 plan's D4
/// standardises every disclosure on this timing; the text panels
/// previously used 240 ms / easeInOutCubic, a deliberately accepted
/// visible change).
class PrecisionDisclosure extends StatefulWidget {
  const PrecisionDisclosure({
    super.key,
    this.icon,
    required this.titleClosed,
    this.titleOpen,
    this.subtitle,
    this.headerValue,
    required this.children,
    this.initiallyOpen = false,
    this.animationDuration = const Duration(milliseconds: 180),
    this.chevronColorClosed,
    this.chevronColorOpen,
    this.titleSize = 13,
    this.chevronSize = 22,
  });

  /// Leading icon. `null` omits it (the text-panel look).
  final IconData? icon;

  final String titleClosed;

  /// Shown while expanded. Defaults to [titleClosed] (the icon-header
  /// family never changes its title text).
  final String? titleOpen;

  /// Second line under the title. `null` omits it (the text-panel
  /// look is single-line).
  final String? subtitle;

  /// Formatted current value shown between the title and the
  /// chevron (e.g. `"24px"`). `null` omits it. Colour follows the
  /// same open/closed rule as the chevron
  /// ([chevronColorOpen]/[chevronColorClosed]) — matches the text
  /// Size panel's and paint's value-in-header precision disclosures.
  final String? headerValue;

  final List<Widget> children;
  final bool initiallyOpen;
  final Duration animationDuration;

  /// Chevron colour while collapsed. Defaults to
  /// `tokens.textSecondary`. The icon-header family (shape/
  /// image) used a constant accent colour regardless of state;
  /// pass the same colour for both params at a migrated call site to
  /// preserve that exactly.
  final Color? chevronColorClosed;

  /// Chevron colour while expanded. Defaults to `tokens.accent`.
  final Color? chevronColorOpen;

  final double titleSize;
  final double chevronSize;

  @override
  State<PrecisionDisclosure> createState() => _PrecisionDisclosureState();
}

class _PrecisionDisclosureState extends State<PrecisionDisclosure> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final title = _open
        ? (widget.titleOpen ?? widget.titleClosed)
        : widget.titleClosed;
    final chevronColor = _open
        ? (widget.chevronColorOpen ?? tokens.accent)
        : (widget.chevronColorClosed ?? tokens.textSecondary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              EditorHaptics.tap();
              setState(() => _open = !_open);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 16, color: tokens.accent),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: widget.subtitle != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: widget.titleSize,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                widget.subtitle!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            title,
                            style: TextStyle(
                              fontSize: widget.titleSize,
                              fontWeight: FontWeight.w600,
                              color: tokens.textPrimary,
                            ),
                          ),
                  ),
                  if (widget.headerValue != null) ...[
                    Text(
                      widget.headerValue!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: chevronColor,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: widget.animationDuration,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: widget.chevronSize,
                      color: chevronColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: widget.animationDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
