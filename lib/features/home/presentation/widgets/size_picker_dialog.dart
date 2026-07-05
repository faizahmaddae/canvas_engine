import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/app_primary_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';

/// Picked canvas size returned by [SizePickerDialog].
class CanvasSize {
  const CanvasSize(this.width, this.height, [this.label]);
  final double width;
  final double height;
  final String? label;
}

class _Preset {
  const _Preset(this.kind, this.width, this.height, this.icon);
  final _PresetKind kind;
  final double width;
  final double height;
  final IconData icon;
}

enum _PresetKind {
  instagramPost,
  square,
  portrait45,
  youtubeThumbnail,
  linkedInPost,
  story,
}

/// Preset groups, ordered by how often a casual user reaches for
/// them. Square first (Instagram-default), then portrait formats,
/// then landscape (YouTube + LinkedIn), then full-bleed story.
class _PresetGroup {
  const _PresetGroup(this.kind, this.presets);
  final _PresetGroupKind kind;
  final List<_Preset> presets;
}

enum _PresetGroupKind { square, portrait, landscape, story }

const List<_PresetGroup> _presetGroups = [
  _PresetGroup(_PresetGroupKind.square, [
    _Preset(_PresetKind.instagramPost, 1080, 1080, Icons.camera_alt_outlined),
    _Preset(_PresetKind.square, 1024, 1024, Icons.crop_square_rounded),
  ]),
  _PresetGroup(_PresetGroupKind.portrait, [
    _Preset(_PresetKind.portrait45, 1080, 1350, Icons.crop_portrait_rounded),
  ]),
  _PresetGroup(_PresetGroupKind.landscape, [
    _Preset(
      _PresetKind.youtubeThumbnail,
      1280,
      720,
      Icons.smart_display_outlined,
    ),
    _Preset(_PresetKind.linkedInPost, 1200, 628, Icons.work_outline_rounded),
  ]),
  _PresetGroup(_PresetGroupKind.story, [
    _Preset(_PresetKind.story, 1080, 1920, Icons.smartphone_outlined),
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
    Navigator.of(
      context,
    ).pop(CanvasSize(p.width, p.height, _presetLabel(context.l10n, p.kind)));
  }

  void _confirmCustom() {
    final w = double.tryParse(_widthCtrl.text.trim());
    final h = double.tryParse(_heightCtrl.text.trim());
    if (w == null || h == null || w < 16 || h < 16 || w > 16384 || h > 16384) {
      setState(() => _customError = context.l10n.customSizeValidation);
      return;
    }
    Navigator.of(context).pop(CanvasSize(w, h, context.l10n.customTab));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    return Dialog(
      backgroundColor: tokens.surface,
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
                  l10n.newDesignTitle,
                  style: AppTypeScale.title.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.pickCanvasSizeBody,
                  style: AppTypeScale.caption.copyWith(
                    color: tokens.textSecondary,
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
                      _presetGroupLabel(
                        l10n,
                        _presetGroups[i].kind,
                      ).toUpperCase(),
                      style: AppTypeScale.caption.copyWith(
                        fontSize: 11,
                        color: tokens.textMuted,
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
                  l10n.customGroup.toUpperCase(),
                  style: AppTypeScale.caption.copyWith(
                    fontSize: 11,
                    color: tokens.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DimensionField(
                        label: l10n.widthLabel,
                        controller: _widthCtrl,
                        onSubmitted: (_) => _confirmCustom(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: tokens.textMuted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DimensionField(
                        label: l10n.heightLabel,
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AppPrimaryButton(
                  key: const ValueKey('size-picker-create'),
                  label: l10n.createCustomAction,
                  onPressed: _confirmCustom,
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textMuted,
                    ),
                    child: Text(l10n.cancelAction),
                  ),
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
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    // Chevron points "forward" (start -> end), so it mirrors under
    // RTL — Material has no auto-mirroring chevron glyph.
    final forwardChevron = Directionality.of(context) == TextDirection.rtl
        ? Icons.chevron_left_rounded
        : Icons.chevron_right_rounded;
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tokens.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(preset.icon, color: tokens.textPrimary, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _presetLabel(l10n, preset.kind),
                        style: AppTypeScale.caption.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${preset.width.toInt()} × ${preset.height.toInt()} px',
                        style: AppTypeScale.caption.copyWith(
                          fontSize: 11,
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(forwardChevron, color: tokens.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _presetGroupLabel(AppLocalizations l10n, _PresetGroupKind kind) =>
    switch (kind) {
      _PresetGroupKind.square => l10n.squareGroup,
      _PresetGroupKind.portrait => l10n.portraitGroup,
      _PresetGroupKind.landscape => l10n.landscapeGroup,
      _PresetGroupKind.story => l10n.storyGroup,
    };

String _presetLabel(AppLocalizations l10n, _PresetKind kind) => switch (kind) {
  _PresetKind.instagramPost => l10n.instagramPostPreset,
  _PresetKind.square => l10n.squarePreset,
  _PresetKind.portrait45 => l10n.portrait45Preset,
  _PresetKind.youtubeThumbnail => l10n.youtubeThumbnailPreset,
  _PresetKind.linkedInPost => l10n.linkedInPostPreset,
  _PresetKind.story => l10n.storyPreset,
};

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
    final tokens = AppTokens.of(context);
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: onSubmitted,
      style: AppTypeScale.body.copyWith(color: tokens.textPrimary, height: 1.4),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypeScale.caption.copyWith(color: tokens.textMuted),
        isDense: true,
        filled: true,
        fillColor: tokens.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: tokens.accent),
        ),
      ),
    );
  }
}
