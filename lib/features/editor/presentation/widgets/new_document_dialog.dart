import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  const _PresetSize(this.label, this.width, this.height, [this.group]);
  final String label;
  final double width;
  final double height;

  /// Optional section header rendered above this preset.
  final String? group;
}

const List<_PresetSize> _presets = [
  // Square
  _PresetSize('Instagram Post (1:1)', 1080, 1080, 'Square'),
  _PresetSize('Square 2048', 2048, 2048),
  // Portrait
  _PresetSize('Portrait 4:5', 1080, 1350, 'Portrait'),
  // Landscape
  _PresetSize('YouTube Thumbnail', 1280, 720, 'Landscape'),
  _PresetSize('LinkedIn Post', 1200, 628),
  _PresetSize('Twitter Post (16:9)', 1600, 900),
  _PresetSize('Facebook Cover', 1640, 859),
  _PresetSize('HD 1080p', 1920, 1080),
  // Story
  _PresetSize('Instagram Story (9:16)', 1080, 1920, 'Story'),
  // Print
  _PresetSize('A4 Portrait (300 dpi)', 2480, 3508, 'Print'),
  _PresetSize('A4 Landscape (300 dpi)', 3508, 2480),
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
        Navigator.of(context).pop(NewDocumentChoice(
          width: _selectedPreset.width,
          height: _selectedPreset.height,
        ));
      case _Mode.blank:
        final w = double.tryParse(_widthCtrl.text.trim());
        final h = double.tryParse(_heightCtrl.text.trim());
        if (w == null || h == null || w < 16 || h < 16 || w > 16384 ||
            h > 16384) {
          setState(() => _error = 'Width and height must be 16\u201316384.');
          return;
        }
        Navigator.of(context).pop(NewDocumentChoice(width: w, height: h));
      case _Mode.image:
        final url = _urlCtrl.text.trim();
        if (url.isEmpty) {
          setState(() => _error = 'Enter an image URL.');
          return;
        }
        setState(() => _resolving = true);
        try {
          final size = await _resolveImageSize(url);
          if (!mounted) return;
          Navigator.of(context).pop(NewDocumentChoice(
            width: size.width,
            height: size.height,
            imageUrl: url,
          ));
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _resolving = false;
            _error = 'Could not load image: $e';
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
    return AlertDialog(
      title: const Text('New document'),
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
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _resolving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _resolving ? null : _create,
          child: _resolving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Widget _modeSelector(ThemeData theme) {
    return SegmentedButton<_Mode>(
      segments: const [
        ButtonSegment(
          value: _Mode.preset,
          label: Text('Preset'),
          icon: Icon(Icons.aspect_ratio),
        ),
        ButtonSegment(
          value: _Mode.blank,
          label: Text('Custom'),
          icon: Icon(Icons.crop_free),
        ),
        ButtonSegment(
          value: _Mode.image,
          label: Text('Image'),
          icon: Icon(Icons.image_outlined),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
    );
  }

  Widget _buildPresetBody(ThemeData theme) {
    final color = theme.colorScheme.primary;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _presets.length,
        itemBuilder: (ctx, i) {
          final p = _presets[i];
          final selected = identical(p, _selectedPreset);
          final tile = Material(
            color:
                selected ? color.withValues(alpha: 0.10) : Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _selectedPreset = p),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.label,
                            style: TextStyle(
                              color: selected ? color : null,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${p.width.toInt()} \u00d7 ${p.height.toInt()} px',
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
                  p.group!.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _widthCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Width (px)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _heightCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Height (px)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _urlCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Image URL',
            hintText: 'https://...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Canvas will be sized to the image\u2019s intrinsic '
          'dimensions and the image will be added as a layer.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

