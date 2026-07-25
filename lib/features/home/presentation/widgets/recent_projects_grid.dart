import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/editor_value_format.dart';
import '../../../../core/utils/text_measure.dart';
import '../../../../core/utils/user_error.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../editor/application/imported_image_path_codec.dart';
import '../../../editor/engine/core/editor_document.dart';
import '../../../editor/engine/rendering/document_thumbnail.dart';
import '../../../editor/engine/serialization/document_codec.dart';
import '../../application/project_delete_service.dart';
import '../../application/project_store.dart';
import '../../domain/project.dart';
import 'project_thumb.dart' show EmptyDesignPlaceholder, isEmptyDesignJson;

const _uuid = Uuid();

/// Full grid of recent projects, used by the dedicated
/// `RecentProjectsScreen` reached from Home's "See all" affordance.
///
/// Architecture:
/// - Pure presentation. Reads state from [projectStoreProvider] and
///   [lastOpenedProjectIdProvider]; mutations go through provider
///   notifiers — never reaches into engine internals.
/// - [onOpen] is delegated upward so navigation stays in one place.
class RecentProjectsGrid extends ConsumerWidget {
  const RecentProjectsGrid({
    super.key,
    required this.onCreate,
    required this.onOpen,
    this.limit,
    this.onSeeAll,
  });

  /// Called from the empty-state CTA.
  final VoidCallback onCreate;

  /// Called when the user taps a project. The home screen wires this
  /// to its existing `_openProject` so navigation logic is unchanged.
  final void Function(Project project) onOpen;

  /// Maximum number of project cards rendered in the grid. `null`
  /// shows everything (used by the dedicated "See all" screen).
  /// Home passes `2` so Templates / Blank canvas stay above the
  /// fold even when the user has many recents.
  final int? limit;

  /// Optional "See all ›" affordance shown in the header when the
  /// project count exceeds [limit]. `null` hides the link — i.e.
  /// when this section is itself the See-all screen.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final projects = ref.watch(projectStoreProvider);
    final lastOpened = ref.watch(lastOpenedProjectIdProvider).value;
    final count = projects.value?.length ?? 0;
    final showSeeAll = onSeeAll != null && limit != null && count > limit!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                // «پروژه‌ها» — matches the tab label; «کارهای اخیر»
                // stays the Home rail's title.
                l10n.navProjectsTab,
                style: AppTypeScale.title.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Text(
                  EditorValueFormat.of(context).digits(count),
                  style: AppTypeScale.caption.copyWith(color: tokens.textMuted),
                ),
              ],
              const Spacer(),
              if (showSeeAll)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    foregroundColor: tokens.accent,
                    textStyle: AppTypeScale.caption.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(l10n.seeAllAction),
                ),
            ],
          ),
        ),
        projects.when(
          data: (list) {
            if (list.isEmpty) {
              return _CompactEmpty(onCreate: onCreate);
            }
            final shown = (limit != null && list.length > limit!)
                ? list.sublist(0, limit!)
                : list;
            return _ProjectsGrid(
              list: shown,
              lastOpenedId: lastOpened,
              onOpen: onOpen,
            );
          },
          loading: () => const _ProjectsSkeleton(),
          error: (e, st) {
            debugLogError('recentProjectsGrid/load', e, st);
            return _ErrorBox(
              message: userMessageFor(e, fallback: l10n.couldntLoadProjects),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────── grid ───────────────────────────────────

class _ProjectsGrid extends StatelessWidget {
  const _ProjectsGrid({
    required this.list,
    required this.lastOpenedId,
    required this.onOpen,
  });

  final List<Project> list;
  final String? lastOpenedId;
  final void Function(Project) onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 540 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: list.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (ctx, i) {
            final p = list[i];
            return ProjectCard(
              key: ValueKey(p.id),
              project: p,
              isLastOpened: p.id == lastOpenedId,
              onOpen: () => onOpen(p),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────── card ───────────────────────────────────

/// Project tile: thumbnail + name + relative time, with a press-scale
/// micro-animation and a `⋯` menu (Open / Rename / Duplicate / Delete).
class ProjectCard extends ConsumerStatefulWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onOpen,
    this.isLastOpened = false,
  });

  final Project project;
  final VoidCallback onOpen;
  final bool isLastOpened;

  @override
  ConsumerState<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends ConsumerState<ProjectCard> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final p = widget.project;
    final relativeTime = _relativeTime(l10n, p.lastModified);
    final thumb = p.thumbnailPath;
    // Only trust a cached PNG if it exists AND was produced by the
    // current renderer. Older PNGs baked an opaque white backdrop
    // and would mis-represent any coloured/transparent canvas.
    final pngIsFresh =
        thumb != null &&
        p.thumbnailVersion >= Project.currentThumbnailVersion &&
        File(thumb).existsSync();
    // Resolved lazily; null on the first frame before the dir future
    // lands, in which case the live-render falls back to a raw decode
    // (unchanged behaviour) until it resolves.
    final importedImagesDir = ref
        .watch(importedImagesDirectoryProvider)
        .value
        ?.path;

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        // v2: flat surface card with a hairline \u2014 no elevation, no
        // tint; the preview carries the colour.
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          onLongPress: () => _showActionsSheet(context),
          onHighlightChanged: _setPressed,
          splashColor: tokens.textPrimary.withValues(alpha: 0.06),
          highlightColor: tokens.textPrimary.withValues(alpha: 0.04),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Thumb(
                        project: p,
                        usePng: pngIsFresh,
                        importedImagesDir: importedImagesDir,
                      ),
                      if (widget.isLastOpened)
                        const PositionedDirectional(
                          start: 8,
                          top: 8,
                          child: _LastOpenedBadge(),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 2, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypeScale.caption.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Single-line metadata: canvas size +
                            // relative last-modified time. Size makes
                            // a stack of "Untitled design" cards
                            // distinguishable at a glance; the dot
                            // separator keeps it compact and reads
                            // well in light/dark.
                            // Measured, not ellipsised. A card in the
                            // 2-up grid has ~150dp for this line and
                            // «۱۰۸۰ × ۱۳۵۰  ·  ۲۹ دقیقه پیش» needs far
                            // more, so SOMETHING has to go. Ellipsis
                            // picks the wrong victim either way: one
                            // `Text` cut the time mid-word, and making
                            // only the time flexible silently clipped
                            // the height off the dimension pair — half
                            // a number pair reads as a different
                            // number. So the size, which is what tells
                            // a stack of «طرح بی‌نام» cards apart, is
                            // always whole, and the time is appended
                            // only when it fits (tb8's rule for the
                            // editor's own title subtitle).
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final style = AppTypeScale.caption.copyWith(
                                  color: tokens.textMuted,
                                  fontSize: 11,
                                );
                                final size = EditorValueFormat.of(context)
                                    .dimensions(
                                      _sizeComponent(p.width),
                                      _sizeComponent(p.height),
                                    );
                                final full = '$size \u00B7 $relativeTime';
                                return Text(
                                  textFits(
                                        context,
                                        full,
                                        style: style,
                                        maxWidth: constraints.maxWidth,
                                      )
                                      ? full
                                      : size,
                                  maxLines: 1,
                                  style: style,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        tooltip: l10n.moreTooltip,
                        color: tokens.textSecondary,
                        icon: const Icon(Icons.more_horiz_rounded),
                        onPressed: () => _showActionsSheet(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActionsSheet(BuildContext context) async {
    // Capture the messenger up front so post-await usage is safe even
    // if this card unmounts before any of the action handlers run
    // (e.g. delete, or the user navigating away mid-sheet).
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final action = await showModalBottomSheet<_CardAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: Text(l10n.openAction),
              onTap: () => Navigator.pop(ctx, _CardAction.open),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: Text(l10n.renameAction),
              onTap: () => Navigator.pop(ctx, _CardAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_rounded),
              title: Text(l10n.duplicateAction),
              onTap: () => Navigator.pop(ctx, _CardAction.duplicate),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                l10n.deleteAction,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, _CardAction.delete),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _CardAction.open:
        widget.onOpen();
      case _CardAction.rename:
        await _renameFlow(messenger);
      case _CardAction.duplicate:
        final newId = await ref
            .read(projectStoreProvider.notifier)
            .duplicate(widget.project.id, _uuid.v4());
        if (newId != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.duplicatedProject(widget.project.name)),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      case _CardAction.delete:
        await _confirmDelete(messenger);
    }
  }

  Future<void> _renameFlow(ScaffoldMessengerState messenger) async {
    final controller = TextEditingController(text: widget.project.name);
    final l10n = context.l10n;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renameProjectTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.projectNameLabel),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (name == widget.project.name) return; // No-op — same name.
    await ref
        .read(projectStoreProvider.notifier)
        .rename(widget.project.id, name);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.renamedProject(name)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmDelete(ScaffoldMessengerState messenger) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteProjectTitle),
        content: Text(l10n.deleteProjectBody(widget.project.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      final name = widget.project.name;
      await ref.read(projectDeleteServiceProvider).delete(widget.project.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.deletedProject(name)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

enum _CardAction { open, rename, duplicate, delete }

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.project,
    required this.usePng,
    required this.importedImagesDir,
  });

  final Project project;

  /// Current `<docs>/imported_images` path, or null before it resolves.
  /// When present the live-render decodes through the path codec so a
  /// canonical `imported_images/<file>` reference (or a rebasable legacy
  /// absolute path) resolves to a usable absolute path for the preview;
  /// when null it falls back to a raw decode (existing behaviour).
  final String? importedImagesDir;

  /// True when the cached PNG at `project.thumbnailPath` was
  /// produced by the current renderer and exists on disk. False
  /// means we must live-render from `project.documentJson` so a
  /// stale white backdrop never reaches the user.
  final bool usePng;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // Neutral "page" colour behind the thumbnail (paper-muted in
    // light, ink-muted in dark) — lets letterboxed portrait/
    // landscape canvases breathe instead of being hard-cropped by
    // BoxFit.cover (which previously sliced text / off-centre
    // subjects out of the preview).
    final canvasBg = tokens.surfaceMuted;

    // Navigation-doc rule, same as the Home rail: an empty design
    // must never read as a blank white thumbnail — its PNG (and its
    // live render) are featureless canvas-colour rectangles.
    if (isEmptyDesignJson(project.documentJson)) {
      return ColoredBox(
        color: canvasBg,
        child: EmptyDesignPlaceholder(name: project.name),
      );
    }

    if (usePng) {
      return ColoredBox(
        color: canvasBg,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Image.file(
            File(project.thumbnailPath!),
            // contain so the entire canvas is visible — a portrait
            // 1080×1920 design is shown in full, not centre-cropped
            // into a meaningless square. The 6 px padding plus the
            // tinted background reads as "sheet on a page".
            fit: BoxFit.contain,
            cacheWidth: 480, // ~card-pixel width on hi-dpi mobile
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
    }

    // Stale PNG (old renderer) or no PNG yet — render the actual
    // document. Single source of truth: same `DocumentThumbnail`
    // widget the templates strip uses, so canvas background and
    // transparent-mode are always honoured. Decoding happens once
    // per build; documents are small JSON.
    final doc = _tryDecode(project.documentJson, importedImagesDir);
    if (doc != null) {
      return ColoredBox(
        color: canvasBg,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: RepaintBoundary(child: DocumentThumbnail(document: doc)),
          ),
        ),
      );
    }

    // Final fallback: corrupt JSON — still better than blank.
    return DecoratedBox(
      decoration: BoxDecoration(color: canvasBg),
      child: Center(
        child: Icon(Icons.image_outlined, size: 28, color: tokens.textMuted),
      ),
    );
  }

  static EditorDocument? _tryDecode(String json, String? importedImagesDir) {
    try {
      if (importedImagesDir == null) return DocumentCodec.decode(json);
      return ImportedImagePathCodec.decodeToRuntime(
        json,
        importedImagesDir: importedImagesDir,
        fileExists: (path) => File(path).existsSync(),
      );
    } catch (_) {
      return null;
    }
  }
}

class _LastOpenedBadge extends StatelessWidget {
  const _LastOpenedBadge();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        // Saffron badge; saffronOnText is the accent family's dark
        // on-colour stop and reads on the fill in both modes.
        color: tokens.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 12, color: tokens.saffronOnText),
          const SizedBox(width: 4),
          Text(
            context.l10n.lastOpenedLabel,
            style: TextStyle(
              color: tokens.saffronOnText,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── skeleton ───────────────────────────────

class _ProjectsSkeleton extends StatelessWidget {
  const _ProjectsSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 540 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: cols * 2,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (_, _) => const _SkeletonCard(),
        );
      },
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();
  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final alpha = 0.45 + (0.30 * _ctrl.value);
        final base = tokens.surfaceMuted.withValues(alpha: alpha);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ColoredBox(color: base),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 10,
                      width: 110,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 8,
                      width: 60,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────── empty / error ──────────────────────────

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tokens.brandSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.collections_outlined,
              size: 22,
              color: tokens.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.noProjectsYet,
                  style: AppTypeScale.body.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.startByCreatingOne,
                  style: AppTypeScale.caption.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onCreate,
            style: TextButton.styleFrom(
              foregroundColor: tokens.accent,
              textStyle: AppTypeScale.caption.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(l10n.createAction),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message, style: TextStyle(color: scheme.error)),
    );
  }
}

/// Drops the `.0` on whole numbers (the common case — every preset
/// size is an integer) before the value reaches the shared formatter.
///
/// The `W × H` composition itself deliberately does NOT live here any
/// more. It used to, and that private copy reproduced the exact defect
/// commit 612dd38 fixed in `EditorValueFormat.dimensions`: `×` is a
/// bidi-neutral sitting between two number runs, so under the app's
/// default RTL it resolved to the paragraph direction and painted the
/// two numbers in reverse — a 1080×1350 portrait project announced
/// itself on its own card as `1350 × 1080`. One composer, one fix.
num _sizeComponent(double v) =>
    v == v.roundToDouble() ? v.toInt() : double.parse(v.toStringAsFixed(1));

String _relativeTime(AppLocalizations l10n, DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return l10n.justNow;
  if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24 && now.day == t.day) return l10n.hoursAgo(diff.inHours);
  if (diff.inDays < 2) return l10n.yesterday;
  if (diff.inDays < 7) return l10n.daysAgo(diff.inDays);
  if (diff.inDays < 30) return l10n.weeksAgo((diff.inDays / 7).floor());
  return l10n.monthsAgo((diff.inDays / 30).floor());
}
