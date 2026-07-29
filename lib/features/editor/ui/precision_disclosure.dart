import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../presentation/widgets/editor_breakpoints.dart';
import '../../../app/theme/app_icons.dart';

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
    this.animationDuration = AppMotion.reveal,
    this.chevronColorClosed,
    this.chevronColorOpen,
    this.titleSize = 13,
    this.chevronSize = 22,
    this.compact = false,
  });

  /// The approved prototype's disclosure grammar (tb7 1/7): ONE line,
  /// no leading icon, no subtitle, accent-coloured title, small
  /// chevron — a text link rather than a card row.
  ///
  /// The two-line form this widget was born with came from the Phase 4
  /// inventory, before the prototype existed. It costs ~54dp of pure
  /// chrome before the user reaches a single control, and a panel with
  /// two disclosures (Look) spent ~108dp saying nothing. Compact keeps
  /// the same tap semantics and the same 44dp hit floor — only the
  /// PAINTED row shrinks, the same trick [ModeDoneButton] uses.
  ///
  /// [subtitle] is still honoured when set: it moves into the
  /// accessibility label so screen-reader users lose nothing.
  final bool compact;

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
        ? (widget.chevronColorOpen ?? tokens.accentText)
        : (widget.chevronColorClosed ?? tokens.textSecondary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A screen reader has to hear the STATE, not just the label:
        // without `expanded` the header announces identically open and
        // closed, so a VoiceOver user cannot tell whether tapping will
        // reveal the sliders or hide them (tb5 2/9).
        Semantics(
          container: true,
          button: true,
          expanded: _open,
          // Compact drops the visible subtitle but not the information:
          // it rides along in the spoken label.
          label: widget.compact && widget.subtitle != null
              ? '$title · ${widget.subtitle}'
              : title,
          // The visible title/subtitle Texts inside would otherwise
          // concatenate onto this node, so the header announced
          // «تنظیم دقیق · روشنایی، … / تنظیم دقیق» — the title twice.
          // `onTap` moves up here because excluding the subtree also
          // excludes the InkWell's tap action.
          onTap: () {
            EditorHaptics.tap();
            setState(() => _open = !_open);
          },
          child: ExcludeSemantics(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  EditorHaptics.tap();
                  setState(() => _open = !_open);
                },
                child: ConstrainedBox(
                  // Painted row shrinks; the touch floor does not.
                  constraints: BoxConstraints(
                    minHeight: widget.compact ? kMinHitTarget : 0,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: widget.compact ? 4 : 10,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        if (widget.icon != null && !widget.compact) ...[
                          Icon(widget.icon, size: 16, color: tokens.accentText),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: widget.compact
                              ? Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: chevronColor,
                                    letterSpacing: 0.1,
                                  ),
                                )
                              : widget.subtitle != null
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
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: chevronColor,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                          const SizedBox(width: 2),
                        ],
                        // A quarter turn CLOCKWISE only points the
                        // caret downward while it is pointing right.
                        // `drillIn` mirrors under RTL, so in Persian
                        // the closed caret points LEFT and +0.25 turned
                        // it UP — an expanded section claiming it was
                        // collapsed. Turn the other way when mirrored.
                        AnimatedRotation(
                          turns: _open ? disclosureOpenTurns(context) : 0,
                          duration: widget.animationDuration,
                          child: Icon(
                            AppIcons.drillIn,
                            size: widget.compact ? 18 : widget.chevronSize,
                            color: chevronColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: widget.animationDuration,
          curve: AppMotion.curve,
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

/// Which way a disclosure caret has to turn to end up pointing DOWN.
///
/// The caret glyph mirrors under RTL (it is the drill-in caret), so the
/// closed state points right under LTR and left under RTL. A fixed
/// +0.25 turn lands on "down" only from the right-pointing state; from
/// the left-pointing one it lands on "up", which reads as still
/// collapsed. Shared by every disclosure that animates its caret.
double disclosureOpenTurns(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl ? -0.25 : 0.25;
