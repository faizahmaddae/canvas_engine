import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../editor/engine/core/editor_document.dart';
import '../../../editor/engine/rendering/document_thumbnail.dart';
import '../../../editor/engine/serialization/document_codec.dart';
import '../../application/project_delete_service.dart';
import '../../application/project_store.dart';
import '../../domain/project.dart';

const _uuid = Uuid();

/// Horizontal-rail variant of a project tile, ~140dp square.
///
/// Pure presentation — taps delegate to [onOpen]; long-press
/// delegates to a small actions sheet (Open / Rename / Duplicate /
/// Delete) that talks to the project store.
class ProjectCard extends ConsumerStatefulWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onOpen,
    this.size = 140,
    this.isLastOpened = false,
  });

  final Project project;
  final VoidCallback onOpen;
  final double size;
  final bool isLastOpened;

  @override
  ConsumerState<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends ConsumerState<ProjectCard> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  /// Cached result of "does the PNG thumbnail file exist on disk?".
  ///
  /// We previously called `File(...).existsSync()` from `build()`,
  /// which performs a synchronous stat per card per frame on the
  /// UI thread — measurable jank when the Recent rail scrolls.
  /// Now we resolve it once via async `exists()` in [initState]
  /// and refresh whenever [Project.thumbnailPath] or
  /// [Project.thumbnailVersion] change. Until the first probe
  /// resolves the card falls back to the document-rendered preview,
  /// which is the same render path used for projects whose PNG was
  /// never written — so the user never sees a broken state.
  bool _pngExists = false;

  @override
  void initState() {
    super.initState();
    _refreshPngExists();
  }

  @override
  void didUpdateWidget(covariant ProjectCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldP = oldWidget.project;
    final newP = widget.project;
    if (oldP.thumbnailPath != newP.thumbnailPath ||
        oldP.thumbnailVersion != newP.thumbnailVersion) {
      _refreshPngExists();
    }
  }

  Future<void> _refreshPngExists() async {
    final p = widget.project;
    final path = p.thumbnailPath;
    if (path == null || p.thumbnailVersion < Project.currentThumbnailVersion) {
      if (_pngExists) setState(() => _pngExists = false);
      return;
    }
    final exists = await File(path).exists();
    if (!mounted) return;
    if (_pngExists != exists) setState(() => _pngExists = exists);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final p = widget.project;
    final relativeTime = _relativeTime(l10n, p.lastModified);
    final pngIsFresh =
        p.thumbnailPath != null &&
        p.thumbnailVersion >= Project.currentThumbnailVersion &&
        _pngExists;

    return Semantics(
      button: true,
      label: l10n.openProjectSemantics(p.name, relativeTime),
      child: SizedBox(
        width: widget.size,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: scheme.surfaceContainerHigh,
                elevation: 1,
                shadowColor: Colors.black.withValues(alpha: 0.4),
                surfaceTintColor: scheme.surfaceTint,
                borderRadius: BorderRadius.circular(AppRadii.card),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onOpen,
                  onLongPress: () => _showActionsSheet(context),
                  onHighlightChanged: _setPressed,
                  splashColor: scheme.primary.withValues(alpha: 0.10),
                  highlightColor: scheme.primary.withValues(alpha: 0.05),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: SizedBox(
                      width: widget.size,
                      height: widget.size,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _Thumb(
                            project: p,
                            usePng: pngIsFresh,
                            scheme: scheme,
                          ),
                          if (widget.isLastOpened)
                            PositionedDirectional(
                              start: 6,
                              top: 6,
                              child: _LastOpenedDot(scheme: scheme),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                relativeTime,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showActionsSheet(BuildContext context) async {
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
            const SizedBox(height: AppSpacing.sm),
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
    if (name == widget.project.name) return;
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
      await ref
          .read(projectDeleteServiceProvider)
          .delete(widget.project.id);
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
    required this.scheme,
  });

  final Project project;
  final bool usePng;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final isDark = scheme.brightness == Brightness.dark;
    final canvasBg = isDark
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : const Color(0xFFF1F2F5);

    if (usePng) {
      return ColoredBox(
        color: canvasBg,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Image.file(
            File(project.thumbnailPath!),
            fit: BoxFit.contain,
            cacheWidth: 320,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
    }
    final doc = _tryDecode(project.documentJson);
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
    return DecoratedBox(
      decoration: BoxDecoration(color: canvasBg),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 24,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  static EditorDocument? _tryDecode(String json) {
    try {
      return DocumentCodec.decode(json);
    } catch (_) {
      return null;
    }
  }
}

class _LastOpenedDot extends StatelessWidget {
  const _LastOpenedDot({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

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
