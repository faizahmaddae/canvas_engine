import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/user_error.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/utils/editor_value_format.dart';

/// Result of [NewDocumentDialog]: the chosen logical canvas size and an
/// optional image source to drop onto the canvas (used by the
/// "From image" mode).
class NewDocumentChoice {
  const NewDocumentChoice({
    required this.width,
    required this.height,
    this.imageUrl,
  });

  final double width;
  final double height;

  /// When non-null, the caller should add an [ImageLayer] of the same size
  /// pointing at this URL right after creating the new document.
  final String? imageUrl;
}

/// A dialog that lets the user create a new document in three ways:
///   1. **Blank** \u2014 enter custom width / height.
///   2. **Preset** \u2014 pick one of the common sizes (Instagram, A4, ...).
///   3. **From image** \u2014 enter an image URL and let the editor pick up
///      the image's intrinsic dimensions as the canvas size.
///
/// The dialog returns a [NewDocumentChoice] via `Navigator.pop`. Caller is
/// responsible for invoking `DocumentController.newDocument(...)`.
class NewDocumentDialog extends StatefulWidget {
  const NewDocumentDialog({super.key});

  @override
  State<NewDocumentDialog> createState() => _NewDocumentDialogState();
}

enum _Mode { preset, blank, image }

class _PresetSize {
  const _PresetSize(this.kind, this.width, this.height, [this.group]);
  final _PresetKind kind;
  final double width;
  final double height;

  /// Optional section header rendered above this preset.
  final _PresetGroup? group;
}

enum _PresetKind {
  instagramPost,
  square2048,
  portrait45,
  youtubeThumbnail,
  linkedInPost,
  twitterPost,
  facebookCover,
  hd1080p,
  instagramStory916,
  a4Portrait300,
  a4Landscape300,
}

enum _PresetGroup { square, portrait, landscape, story, print }

const List<_PresetSize> _presets = [
  // Square
  _PresetSize(_PresetKind.instagramPost, 1080, 1080, _PresetGroup.square),
  _PresetSize(_PresetKind.square2048, 2048, 2048),
  // Portrait
  _PresetSize(_PresetKind.portrait45, 1080, 1350, _PresetGroup.portrait),
  // Landscape
  _PresetSize(_PresetKind.youtubeThumbnail, 1280, 720, _PresetGroup.landscape),
  _PresetSize(_PresetKind.linkedInPost, 1200, 628),
  _PresetSize(_PresetKind.twitterPost, 1600, 900),
  _PresetSize(_PresetKind.facebookCover, 1640, 859),
  _PresetSize(_PresetKind.hd1080p, 1920, 1080),
  // Story
  _PresetSize(_PresetKind.instagramStory916, 1080, 1920, _PresetGroup.story),
  // Print
  _PresetSize(_PresetKind.a4Portrait300, 2480, 3508, _PresetGroup.print),
  _PresetSize(_PresetKind.a4Landscape300, 3508, 2480),
];

class _NewDocumentDialogState extends State<NewDocumentDialog> {
  _Mode _mode = _Mode.preset;
  _PresetSize _selectedPreset = _presets.first;

  final _widthCtrl = TextEditingController(text: '1080');
  final _heightCtrl = TextEditingController(text: '1080');
  final _urlCtrl = TextEditingController();

  bool _resolving = false;
  String? _error;

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _error = null);
    switch (_mode) {
      case _Mode.preset:
        Navigator.of(context).pop(
          NewDocumentChoice(
            width: _selectedPreset.width,
            height: _selectedPreset.height,
          ),
        );
      case _Mode.blank:
        final w = double.tryParse(_widthCtrl.text.trim());
        final h = double.tryParse(_heightCtrl.text.trim());
        if (w == null ||
            h == null ||
            w < 16 ||
            h < 16 ||
            w > 16384 ||
            h > 16384) {
          setState(() => _error = context.l10n.customSizeValidation);
          return;
        }
        Navigator.of(context).pop(NewDocumentChoice(width: w, height: h));
      case _Mode.image:
        final url = _urlCtrl.text.trim();
        if (url.isEmpty) {
          setState(() => _error = context.l10n.enterImageUrlValidation);
          return;
        }
        setState(() => _resolving = true);
        try {
          final size = await _resolveImageSize(url);
          if (!mounted) return;
          Navigator.of(context).pop(
            NewDocumentChoice(
              width: size.width,
              height: size.height,
              imageUrl: url,
            ),
          );
        } catch (e, st) {
          debugLogError('newDocumentDialog/loadImage', e, st);
          if (!mounted) return;
          setState(() {
            _resolving = false;
            _error = userMessageFor(
              e,
              fallback: context.l10n.couldntOpenPhoto,
              genericMessage: context.l10n.somethingWentWrong,
            );
          });
        }
    }
  }

  /// Resolve the intrinsic pixel dimensions of a network image without
  /// painting it. Uses an [ImageStreamListener] which fires as soon as
  /// the codec has the first frame.
  Future<Size> _resolveImageSize(String url) {
    final completer = Completer<Size>();
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (!completer.isCompleted) completer.complete(Size(w, h));
        stream.removeListener(listener);
      },
      onError: (e, _) {
        if (!completer.isCompleted) completer.completeError(e);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.newDocumentTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _modeSelector(theme),
            const SizedBox(height: 16),
            switch (_mode) {
              _Mode.preset => _buildPresetBody(theme),
              _Mode.blank => _buildBlankBody(),
              _Mode.image => _buildImageBody(),
            },
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _resolving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: _resolving ? null : _create,
          child: _resolving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.createAction),
        ),
      ],
    );
  }

  Widget _modeSelector(ThemeData theme) {
    final l10n = context.l10n;
    return SegmentedButton<_Mode>(
      segments: [
        ButtonSegment(
          value: _Mode.preset,
          label: Text(l10n.presetTab),
          icon: const Icon(Icons.aspect_ratio),
        ),
        ButtonSegment(
          value: _Mode.blank,
          label: Text(l10n.customTab),
          icon: const Icon(Icons.crop_free),
        ),
        ButtonSegment(
          value: _Mode.image,
          label: Text(l10n.imageTab),
          icon: const Icon(Icons.image_outlined),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
    );
  }

  Widget _buildPresetBody(ThemeData theme) {
    final l10n = context.l10n;
    final tokens = AppTokens.of(context);
    final color = tokens.accent;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _presets.length,
        itemBuilder: (ctx, i) {
          final p = _presets[i];
          final selected = identical(p, _selectedPreset);
          final tile = Material(
            color: selected
                ? color.withValues(alpha: 0.10)
                : Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _selectedPreset = p),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _presetLabel(l10n, p.kind),
                            style: TextStyle(
                              color: selected ? color : null,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${EditorValueFormat.of(context).dimensions(p.width.toInt(), p.height.toInt())} px',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (selected) Icon(Icons.check, color: color),
                  ],
                ),
              ),
            ),
          );
          if (p.group == null) return tile;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 4),
                child: Text(
                  _presetGroupLabel(l10n, p.group!).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              tile,
            ],
          );
        },
      ),
    );
  }

  Widget _buildBlankBody() {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _widthCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.widthPxLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _heightCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.heightPxLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageBody() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _urlCtrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: l10n.imageUrlLabel,
            hintText: 'https://...',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.imageSizingHint, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  String _presetGroupLabel(AppLocalizations l10n, _PresetGroup group) =>
      switch (group) {
        _PresetGroup.square => l10n.squareGroup,
        _PresetGroup.portrait => l10n.portraitGroup,
        _PresetGroup.landscape => l10n.landscapeGroup,
        _PresetGroup.story => l10n.storyGroup,
        _PresetGroup.print => l10n.printGroup,
      };

  String _presetLabel(AppLocalizations l10n, _PresetKind kind) =>
      switch (kind) {
        _PresetKind.instagramPost => '${l10n.instagramPostPreset} (1:1)',
        _PresetKind.square2048 => l10n.square2048Preset,
        _PresetKind.portrait45 => l10n.portrait45Preset,
        _PresetKind.youtubeThumbnail => l10n.youtubeThumbnailPreset,
        _PresetKind.linkedInPost => l10n.linkedInPostPreset,
        _PresetKind.twitterPost => l10n.twitterPostPreset,
        _PresetKind.facebookCover => l10n.facebookCoverPreset,
        _PresetKind.hd1080p => l10n.hd1080pPreset,
        _PresetKind.instagramStory916 => l10n.instagramStory916Preset,
        _PresetKind.a4Portrait300 => l10n.a4Portrait300Preset,
        _PresetKind.a4Landscape300 => l10n.a4Landscape300Preset,
      };
}
