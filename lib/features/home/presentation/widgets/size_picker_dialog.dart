import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Picked canvas size returned by [SizePickerDialog].
class CanvasSize {
  const CanvasSize(this.width, this.height, [this.label]);
  final double width;
  final double height;
  final String? label;
}

class _Preset {
  const _Preset(this.label, this.width, this.height, this.icon);
  final String label;
  final double width;
  final double height;
  final IconData icon;
}

/// Preset groups, ordered by how often a casual user reaches for
/// them. Square first (Instagram-default), then portrait formats,
/// then landscape (YouTube + LinkedIn), then full-bleed story.
class _PresetGroup {
  const _PresetGroup(this.label, this.presets);
  final String label;
  final List<_Preset> presets;
}

const List<_PresetGroup> _presetGroups = [
  _PresetGroup('Square', [
    _Preset('Instagram Post', 1080, 1080, Icons.camera_alt_outlined),
    _Preset('Square', 1024, 1024, Icons.crop_square_rounded),
  ]),
  _PresetGroup('Portrait', [
    _Preset('Portrait 4:5', 1080, 1350, Icons.crop_portrait_rounded),
  ]),
  _PresetGroup('Landscape', [
    _Preset('YouTube Thumbnail', 1280, 720, Icons.smart_display_outlined),
    _Preset('LinkedIn Post', 1200, 628, Icons.work_outline_rounded),
  ]),
  _PresetGroup('Story', [
    _Preset('Story', 1080, 1920, Icons.smartphone_outlined),
  ]),
];

/// Modal dialog: pick a preset canvas size or enter a custom one.
///
/// Returns a [CanvasSize] via `Navigator.pop`, or `null` on cancel.
class SizePickerDialog extends StatefulWidget {
  const SizePickerDialog({super.key});

  static Future<CanvasSize?> show(BuildContext context) {
    return showDialog<CanvasSize>(
      context: context,
      builder: (_) => const SizePickerDialog(),
    );
  }

  @override
  State<SizePickerDialog> createState() => _SizePickerDialogState();
}

class _SizePickerDialogState extends State<SizePickerDialog> {
  final _widthCtrl = TextEditingController(text: '1080');
  final _heightCtrl = TextEditingController(text: '1080');
  String? _customError;

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _pickPreset(_Preset p) {
    Navigator.of(context).pop(CanvasSize(p.width, p.height, p.label));
  }

  void _confirmCustom() {
    final w = double.tryParse(_widthCtrl.text.trim());
    final h = double.tryParse(_heightCtrl.text.trim());
    if (w == null || h == null || w < 16 || h < 16 || w > 16384 || h > 16384) {
      setState(() => _customError = 'Width & height must be 16–16384.');
      return;
    }
    Navigator.of(context).pop(CanvasSize(w, h, 'Custom'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Text(
                'New design',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pick a canvas size to start with.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _presetGroups.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 4,
                    bottom: 8,
                  ),
                  child: Text(
                    _presetGroups[i].label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                for (var j = 0; j < _presetGroups[i].presets.length; j++) ...[
                  if (j > 0) const SizedBox(height: 8),
                  _PresetTile(
                    preset: _presetGroups[i].presets[j],
                    onTap: () => _pickPreset(_presetGroups[i].presets[j]),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Text(
                'CUSTOM',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DimensionField(
                      label: 'Width',
                      controller: _widthCtrl,
                      onSubmitted: (_) => _confirmCustom(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: Icon(Icons.close_rounded, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DimensionField(
                      label: 'Height',
                      controller: _heightCtrl,
                      onSubmitted: (_) => _confirmCustom(),
                    ),
                  ),
                ],
              ),
              if (_customError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _customError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _confirmCustom,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create custom'),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.onTap});
  final _Preset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary,
                      scheme.tertiary,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(preset.icon, color: scheme.onPrimary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${preset.width.toInt()} × ${preset.height.toInt()} px',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _DimensionField extends StatelessWidget {
  const _DimensionField({
    required this.label,
    required this.controller,
    required this.onSubmitted,
  });
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
