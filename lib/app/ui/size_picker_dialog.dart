import '../../core/utils/editor_value_format.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/ui/app_primary_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../theme/app_icons.dart';

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
  hd1080p,
  story,
  a4Portrait300,
  a4Landscape300,
}

/// Preset groups, ordered by how often a casual user reaches for
/// them. Square first (Instagram-default), then portrait formats,
/// then landscape (YouTube + LinkedIn), then full-bleed story.
class _PresetGroup {
  const _PresetGroup(this.kind, this.presets);
  final _PresetGroupKind kind;
  final List<_Preset> presets;
}

enum _PresetGroupKind { square, portrait, landscape, story, print }

const List<_PresetGroup> _presetGroups = [
  _PresetGroup(_PresetGroupKind.square, [
    _Preset(
      _PresetKind.instagramPost,
      1080,
      1080,
      AppIcons.sizePresetInstagramPost,
    ),
    _Preset(_PresetKind.square, 1024, 1024, AppIcons.squareShape),
  ]),
  _PresetGroup(_PresetGroupKind.portrait, [
    _Preset(_PresetKind.portrait45, 1080, 1350, AppIcons.aspectPortrait),
  ]),
  _PresetGroup(_PresetGroupKind.landscape, [
    _Preset(_PresetKind.youtubeThumbnail, 1280, 720, AppIcons.videoPreset),
    _Preset(_PresetKind.linkedInPost, 1200, 628, AppIcons.presetLinkedIn),
    _Preset(_PresetKind.hd1080p, 1920, 1080, AppIcons.presetHd1080p),
  ]),
  _PresetGroup(_PresetGroupKind.story, [
    _Preset(_PresetKind.story, 1080, 1920, AppIcons.storyPreset),
  ]),
  // Print sizes came from the editor's own New-document dialog, which
  // tb4 5/14 retired. They land here rather than dying with it — 300
  // dpi A4 is a real thing people make, and Custom is a poor
  // substitute for a labelled preset when the numbers are 2480×3508.
  _PresetGroup(_PresetGroupKind.print, [
    _Preset(_PresetKind.a4Portrait300, 2480, 3508, AppIcons.presetA4Portrait),
    _Preset(
      _PresetKind.a4Landscape300,
      3508,
      2480,
      AppIcons.sizePresetA4Landscape,
    ),
  ]),
];

/// Seed for the custom width/height fields when the caller has no
/// existing size to offer — the same square the preset list leads
/// with, so the form starts on the most-reached-for value.
const double _kDefaultCustomSide = 1080;

/// Modal dialog: pick a preset canvas size or enter a custom one.
///
/// Returns a [CanvasSize] via `Navigator.pop`, or `null` on cancel.
///
/// The copy is overridable because the same form serves two intents:
/// Home creates a NEW design ("New design" / "Create custom"), the
/// editor's Canvas panel RESIZES an existing one ("Custom size" /
/// "Use size", pre-filled with the document's current dimensions).
/// Only the words and the seed differ — the presets, validation and
/// return type are identical, so forking the widget would be two
/// copies of the same 16..16384 rules. Every override defaults to
/// the Home wording, which is why `show(context)` still renders the
/// original dialog byte-for-byte.
class SizePickerDialog extends StatefulWidget {
  const SizePickerDialog({
    super.key,
    this.title,
    this.body,
    this.confirmLabel,
    this.initial,
  });

  /// Headline. Defaults to `l10n.newDesignTitle`.
  final String? title;

  /// Sub-headline under [title]. Defaults to `l10n.pickCanvasSizeBody`.
  final String? body;

  /// Primary-button label. Defaults to `l10n.createCustomAction`.
  final String? confirmLabel;

  /// Pre-fills the custom width/height fields. `null` seeds both
  /// with [_kDefaultCustomSide].
  final CanvasSize? initial;

  static Future<CanvasSize?> show(
    BuildContext context, {
    String? title,
    String? body,
    String? confirmLabel,
    CanvasSize? initial,
  }) {
    return showDialog<CanvasSize>(
      context: context,
      builder: (_) => SizePickerDialog(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        initial: initial,
      ),
    );
  }

  @override
  State<SizePickerDialog> createState() => _SizePickerDialogState();
}

class _SizePickerDialogState extends State<SizePickerDialog> {
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;
  String? _customError;

  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seeded here rather than in `initState` because the locale-aware
    // formatter needs an inherited `Localizations`. A Persian user saw
    // the preset list in «۱۰۸۰ × ۱۳۵۰» and the two boxes underneath
    // prefilled with Latin `1080`.
    if (_seeded) return;
    _seeded = true;
    final initial = widget.initial;
    _widthCtrl = TextEditingController(
      text: _seedText(context, initial?.width ?? _kDefaultCustomSide),
    );
    _heightCtrl = TextEditingController(
      text: _seedText(context, initial?.height ?? _kDefaultCustomSide),
    );
  }

  // The field is digits-only, so a fractional document size (a crop
  // can leave one) seeds as its rounded whole pixel.
  static String _seedText(BuildContext context, double value) =>
      EditorValueFormat.of(context).digits(value.round());

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
    // Fold Persian/Arabic numerals to ASCII before parsing: a Persian
    // keyboard types ۸۰۰, `double.tryParse` returns null for it, and
    // the dialog rejected input the user could see in the box.
    final w = double.tryParse(
      EditorValueFormat.toAsciiDigits(_widthCtrl.text.trim()),
    );
    final h = double.tryParse(
      EditorValueFormat.toAsciiDigits(_heightCtrl.text.trim()),
    );
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
          // Header and CTA sit OUTSIDE the scroll view: with the whole
          // dialog in one scroller the confirm button slid below the
          // fold as the preset list grew, and on a small phone it was
          // already only reachable by scrolling past every preset.
          // Only the presets and the custom form scroll now, so the
          // primary action is always on screen (tb5 9/9).
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title ?? l10n.newDesignTitle,
                style: AppTypeScale.title.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.body ?? l10n.pickCanvasSizeBody,
                style: AppTypeScale.caption.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                        for (
                          var j = 0;
                          j < _presetGroups[i].presets.length;
                          j++
                        ) ...[
                          if (j > 0) const SizedBox(height: 8),
                          _PresetTile(
                            preset: _presetGroups[i].presets[j],
                            onTap: () =>
                                _pickPreset(_presetGroups[i].presets[j]),
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
                              AppIcons.close,
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppPrimaryButton(
                key: const ValueKey('size-picker-create'),
                label: widget.confirmLabel ?? l10n.createCustomAction,
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
    // `chevron_right_rounded` already carries `matchTextDirection`,
    // so Flutter mirrors it for us. Picking `chevron_left_rounded`
    // under RTL by hand mirrored it a *second* time and the drill-in
    // affordance ended up pointing back out of the row — a `>` sitting
    // on the row's left edge, aimed at the screen edge.
    const forwardChevron = AppIcons.drillIn;
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
                        // Through the shared formatter so the pair
                        // keeps its order under RTL — a bare
                        // 'W × H' renders as 'H × W' in Persian.
                        '${EditorValueFormat.of(context).dimensions(preset.width.toInt(), preset.height.toInt())} px',
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
      _PresetGroupKind.print => l10n.printGroup,
    };

String _presetLabel(AppLocalizations l10n, _PresetKind kind) => switch (kind) {
  _PresetKind.instagramPost => l10n.instagramPostPreset,
  _PresetKind.square => l10n.squarePreset,
  _PresetKind.portrait45 => l10n.portrait45Preset,
  _PresetKind.youtubeThumbnail => l10n.youtubeThumbnailPreset,
  _PresetKind.linkedInPost => l10n.linkedInPostPreset,
  _PresetKind.hd1080p => l10n.hd1080pPreset,
  _PresetKind.story => l10n.storyPreset,
  _PresetKind.a4Portrait300 => l10n.a4Portrait300Preset,
  _PresetKind.a4Landscape300 => l10n.a4Landscape300Preset,
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
      inputFormatters: [EditorValueFormat.localeDigitsOnly],
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
