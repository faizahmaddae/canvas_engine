import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../application/document_controller.dart';
import '../../../../app/ui/app_modal_sheet.dart';
import 'history_labels.dart';
import '../../../../app/theme/app_icons.dart';

/// Opens the history browser — the shipped counterpart of the
/// approved prototype's top-bar history popover.
///
/// The timeline is navigable (audit P3-4): tapping a row jumps the
/// document to that point. A jump is nothing but a replayed run of
/// the existing single-step undo/redo — one step per timeline entry,
/// so grouped-undo entries stay grouped and nothing is ever discarded;
/// every jump is itself reversible by jumping (or undo/redoing) back.
/// The sheet stays open across jumps so the user can scrub the
/// timeline and watch the canvas change behind the whisper barrier.
Future<void> showHistoryBrowser(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(
    context,
    title: context.l10n.historyTitle,
    titleIcon: AppIcons.history,
    // Whisper, not full: jumping repaints the canvas behind the sheet,
    // so keeping it visible is the whole point — the browser is a
    // scrubber over what you see, not a form over it.
    barrier: AppSheetBarrier.whisper,
    maxHeightFraction: 0.7,
    builder: (context) => const HistoryBrowserView(),
  );
}

/// The scrollable timeline itself, hostable on its own so tests and the
/// capture harness can pump it without a modal route.
class HistoryBrowserView extends ConsumerStatefulWidget {
  const HistoryBrowserView({super.key});

  @override
  ConsumerState<HistoryBrowserView> createState() => _HistoryBrowserViewState();
}

class _HistoryBrowserViewState extends ConsumerState<HistoryBrowserView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Land on the current step: a 200-entry timeline opened at the top
    // buries where the user actually is. Deferred one frame so the list
    // has laid out and the offset is real.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    final doc = ref.read(documentControllerProvider.notifier);
    final current = doc.historyCurrentIndex;
    final rows = doc.historyTimeline.length + 1; // +1 for the start row
    if (rows <= 1) return;
    // Row 0 is the start anchor; timeline index i sits at row i+1.
    final targetRow = current + 1;
    final max = _scrollController.position.maxScrollExtent;
    final offset = (targetRow * _kRowExtent - _kRowExtent * 2).clamp(0.0, max);
    _scrollController.jumpTo(offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Jump the document to the tapped row.
  ///
  /// Row → history index mapping (must mirror [build]'s itemBuilder,
  /// which renders row 0 as the start anchor and timeline[i] at row
  /// i + 1):
  ///
  ///   row 0      = "Document opened"  → historyCurrentIndex -1
  ///   row r ≥ 1  = timeline[r - 1]    → historyCurrentIndex r - 1
  ///
  /// So the jump target is always `row - 1`. The start row is the
  /// state BEFORE timeline[0] — the classic off-by-one is treating it
  /// as timeline[0], which would leave the oldest step applied when
  /// the user asked for the opened document.
  ///
  /// Tapping an applied row undoes down to it, an undone row redoes
  /// up to it inclusively, and the current row is a no-op (checked
  /// here so a no-op tap gives no haptic and bumps nothing).
  void _jumpToRow(int row) {
    final doc = ref.read(documentControllerProvider.notifier);
    final target = row - 1;
    if (doc.historyCurrentIndex == target) return;
    EditorHaptics.tap();
    doc.jumpToHistoryIndex(target);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on committed changes only — the browser tracks history,
    // which moves only on execute/undo/redo, never on overlay previews.
    ref.watch(documentCommitVersionProvider);
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final doc = ref.read(documentControllerProvider.notifier);
    final timeline = doc.historyTimeline;
    final current = doc.historyCurrentIndex;

    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      // +1 leading "start" row for the document's initial state.
      itemCount: timeline.length + 1,
      itemBuilder: (context, row) {
        if (row == 0) {
          return _HistoryRow(
            label: l10n.historyStartLabel,
            state: current < 0 ? _RowState.current : _RowState.applied,
            tokens: tokens,
            l10n: l10n,
            isStart: true,
            onTap: () => _jumpToRow(row),
          );
        }
        final i = row - 1;
        final entry = timeline[i];
        final _RowState state;
        if (!entry.done) {
          state = _RowState.undone;
        } else if (i == current) {
          state = _RowState.current;
        } else {
          state = _RowState.applied;
        }
        return _HistoryRow(
          label: localizedHistoryLabel(
            l10n,
            entry.label,
            // Batch labels carry a member count — render it in locale
            // digits so fa rows don't get a Latin-digit island.
            formatCount: (n) => EditorValueFormat.of(context).digits(n),
          ),
          state: state,
          tokens: tokens,
          l10n: l10n,
          isStart: false,
          onTap: () => _jumpToRow(row),
        );
      },
    );
  }
}

/// One row's visual state — the three the prototype distinguished.
enum _RowState {
  /// Applied step at or before the current position.
  applied,

  /// The current document position.
  current,

  /// An undone step, reachable by redo.
  undone,
}

const double _kRowExtent = 48;

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.label,
    required this.state,
    required this.tokens,
    required this.l10n,
    required this.isStart,
    required this.onTap,
  });

  final String label;
  final _RowState state;
  final AppTokens tokens;
  final AppLocalizations l10n;
  final bool isStart;

  /// Jumps the document to this row's point in history. Wired for
  /// every row — the current row's handler no-ops upstream, so the
  /// tap grammar stays uniform while a redundant tap costs nothing.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == _RowState.current;
    final isUndone = state == _RowState.undone;

    final Color textColor = switch (state) {
      _RowState.current => tokens.accentText,
      _RowState.undone => tokens.textMuted,
      _RowState.applied => tokens.textPrimary,
    };

    // The state a screen reader hears appended to the label — the dot
    // and the dimming are invisible to it.
    final String? stateSemantic = switch (state) {
      _RowState.current => l10n.historyCurrentSemantic,
      _RowState.undone => l10n.historyUndoneSemantic,
      _RowState.applied => null,
    };

    return Semantics(
      container: true,
      selected: isCurrent,
      button: true,
      onTap: onTap,
      label: stateSemantic == null ? label : '$label · $stateSemantic',
      // No hint on the current row: promising a jump that no-ops
      // would mislead a screen-reader user about what a double-tap
      // does. Every other row announces the jump affordance.
      hint: isCurrent ? null : l10n.historyJumpHint,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.state),
        height: _kRowExtent,
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: isCurrent
              ? tokens.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        // Material INSIDE the tinted container, not the sheet's own
        // transparent Material underneath it: ink must paint above the
        // current row's accent wash, or the splash vanishes behind it.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            // The Semantics above already carries the label, state and
            // tap action as ONE node; letting the InkWell add its own
            // would give screen readers two stops per row.
            excludeFromSemantics: true,
            child: Padding(
              // Was the AnimatedContainer's padding — moved inside the
              // InkWell so the whole 48dp row extent is tappable.
              padding: const EdgeInsetsDirectional.only(start: 8, end: 12),
              child: Row(
                children: [
                  _Marker(state: state, tokens: tokens, isStart: isStart),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: textColor,
                        // Undone steps read as "not applied" — the strike
                        // makes that unmistakable without relying on the
                        // dim alone (which colour-blind users can miss).
                        decoration: isUndone
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: tokens.textMuted,
                      ),
                    ),
                  ),
                  if (isCurrent)
                    Icon(
                      AppIcons.historyCurrentStep,
                      size: 16,
                      color: tokens.accentText,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The leading dot: filled at/before current, ringed for the current
/// step, hollow for undone. The vertical connector reads the rows as
/// one timeline.
class _Marker extends StatelessWidget {
  const _Marker({
    required this.state,
    required this.tokens,
    required this.isStart,
  });

  final _RowState state;
  final AppTokens tokens;
  final bool isStart;

  @override
  Widget build(BuildContext context) {
    final Color dot = switch (state) {
      _RowState.current => tokens.accent,
      _RowState.undone => tokens.border,
      _RowState.applied => tokens.textMuted,
    };
    return SizedBox(
      width: 16,
      child: Center(
        child: Container(
          width: state == _RowState.current ? 12 : 8,
          height: state == _RowState.current ? 12 : 8,
          decoration: BoxDecoration(
            color: state == _RowState.undone ? Colors.transparent : dot,
            shape: BoxShape.circle,
            border: Border.all(
              color: dot,
              width: state == _RowState.current ? 3 : 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
