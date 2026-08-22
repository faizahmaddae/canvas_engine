import 'package:flutter/material.dart';

import '../../core/constants/engine_constants.dart';
import '../../core/utils/editor_value_format.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../theme/app_spacing.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'app_modal_sheet.dart';
import 'app_primary_button.dart';

/// Picked canvas size returned by [SizePickerSheet].
class CanvasSize {
  const CanvasSize(this.width, this.height, [this.label]);
  final double width;
  final double height;
  final String? label;
}

class _Preset {
  const _Preset(this.kind, this.width, this.height);
  final _PresetKind kind;
  final double width;
  final double height;

  double get ratio => width / height;
}

enum _PresetKind {
  instagramPost,
  square,
  portrait45,
  story,
  youtubeThumbnail,
  linkedInPost,
  hd1080p,
  a4Portrait300,
  a4Landscape300,
}

/// One flat, frequency-ordered list. The old dialog spent five group
/// labels (SQUARE / PORTRAIT / …) saying what each format's shape is;
/// here the tile's ghost IS the shape, so the taxonomy row died with
/// the icon that used to stand in for it.
const List<_Preset> _presets = [
  _Preset(_PresetKind.instagramPost, 1080, 1080),
  _Preset(_PresetKind.square, 1024, 1024),
  _Preset(_PresetKind.portrait45, 1080, 1350),
  _Preset(_PresetKind.story, 1080, 1920),
  _Preset(_PresetKind.youtubeThumbnail, 1280, 720),
  _Preset(_PresetKind.linkedInPost, 1200, 628),
  _Preset(_PresetKind.hd1080p, 1920, 1080),
  _Preset(_PresetKind.a4Portrait300, 2480, 3508),
  _Preset(_PresetKind.a4Landscape300, 3508, 2480),
];

/// Seed for the custom width/height fields when the caller has no
/// existing size to offer — the same square the preset grid leads
/// with, so the form starts on the most-reached-for value.
const double _kDefaultCustomSide = 1080;

/// Canvas-size picker, as a sheet of formats you can SEE.
///
/// Successor to `SizePickerDialog`. The dialog was nine icon+text list
/// rows in five labelled groups plus a form — a screen's worth of
/// reading to pick a rectangle, floated as framework chrome in an app
/// whose every other picker is an anchored `showAppSheet`. This is the
/// same choice drawn instead of described: a three-across grid of
/// aspect-true ghost tiles (a story is visibly tall, a thumbnail
/// visibly wide) with the name and pixel pair beneath, and the custom
/// form compacted below.
///
/// Same contract as the dialog it replaces: returns a [CanvasSize] or
/// null on dismiss; presets carry their localized label; custom
/// entries validate against the ONE shared document ceiling
/// (16..[EngineConstants.maxDocumentDimension], ux-audit P2-20) and
/// parse the digits a Persian keyboard actually produces.
///
/// The copy is overridable because the same form serves two intents:
/// Home creates a NEW design, the editor's Canvas panel RESIZES an
/// existing one (pre-filled with the document's current dimensions).
class SizePickerSheet extends StatefulWidget {
  const SizePickerSheet({
    super.key,
    this.body,
    this.confirmLabel,
    this.initial,
  });

  /// Caption under the sheet title. Defaults to `l10n.pickCanvasSizeBody`.
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
    return showAppSheet<CanvasSize>(
      context,
      title: title ?? context.l10n.newDesignTitle,
      titleIcon: AppIcons.add,
      // Text entry lives at the bottom of the sheet; it has to ride
      // the keyboard, not vanish under it.
      keyboardAware: true,
      builder: (_) => SizePickerSheet(
        body: body,
        confirmLabel: confirmLabel,
        initial: initial,
      ),
    );
  }

  @override
  State<SizePickerSheet> createState() => _SizePickerSheetState();
}

class _SizePickerSheetState extends State<SizePickerSheet> {
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;
  String? _customError;

  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seeded here rather than in `initState` because the locale-aware
    // formatter needs an inherited `Localizations`. A Persian user saw
    // the preset grid in «۱۰۸۰ × ۱۳۵۰» and the two boxes underneath
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
    // the old dialog rejected input the user could see in the box.
    final w = double.tryParse(
      EditorValueFormat.toAsciiDigits(_widthCtrl.text.trim()),
    );
    final h = double.tryParse(
      EditorValueFormat.toAsciiDigits(_heightCtrl.text.trim()),
    );
    // One agreed ceiling for every document-size entry point (create,
    // in-editor resize, export custom) — see
    // [EngineConstants.maxDocumentDimension] (ux-audit P2-20).
    const maxSide = EngineConstants.maxDocumentDimension;
    if (w == null ||
        h == null ||
        w < 16 ||
        h < 16 ||
        w > maxSide ||
        h > maxSide) {
      setState(() => _customError = context.l10n.customSizeValidation);
      return;
    }
    Navigator.of(context).pop(CanvasSize(w, h, context.l10n.customTab));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    // Only the format grid scrolls; the custom form and the CTA are
    // pinned below it, always on screen. The old dialog learned this
    // the hard way (tb5 9/9): with everything in one scroller the
    // confirm button slid below the fold as the preset list grew —
    // and a button that can slide off screen is a button a test tap
    // silently misses while the sheet waits forever for its pop.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Text(
            widget.body ?? l10n.pickCanvasSizeBody,
            style: AppTypeScale.caption.copyWith(color: tokens.textSecondary),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
            ),
            child: GridView.builder(
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _presets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisExtent: 108,
              ),
              itemBuilder: (context, index) {
                final p = _presets[index];
                return _FormatTile(
                  key: ValueKey('size-preset-${p.kind.name}'),
                  preset: p,
                  onTap: () => _pickPreset(p),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.customGroup.toUpperCase(),
                style: AppTypeScale.caption.copyWith(
                  fontSize: 11,
                  color: tokens.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
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
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _customError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppPrimaryButton(
                key: const ValueKey('size-picker-create'),
                label: widget.confirmLabel ?? l10n.createCustomAction,
                onPressed: _confirmCustom,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One format, drawn: a ghost rectangle at the preset's true aspect
/// ratio over the name and pixel pair. The ghost replaces both the
/// old row icon and the old group label — shape is the taxonomy.
class _FormatTile extends StatelessWidget {
  const _FormatTile({super.key, required this.preset, required this.onTap});

  final _Preset preset;
  final VoidCallback onTap;

  /// Bounding box the ghost is fitted into.
  static const double _ghostBox = 44;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = context.l10n;
    final ratio = preset.ratio;
    final ghostW = ratio >= 1 ? _ghostBox : _ghostBox * ratio;
    final ghostH = ratio >= 1 ? _ghostBox / ratio : _ghostBox;
    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.button),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.button),
            border: Border.all(color: tokens.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                SizedBox(
                  width: _ghostBox,
                  height: _ghostBox,
                  child: Center(
                    child: Container(
                      width: ghostW,
                      height: ghostH,
                      decoration: BoxDecoration(
                        color: tokens.surfaceMuted,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: tokens.textSecondary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _presetLabel(l10n, preset.kind),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypeScale.caption.copyWith(
                    fontSize: 11,
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                // Explicit LTR subtree, not a bidi isolate: 'px'-less
                // here, but «W × H» is still two number runs around a
                // neutral, and under the app's RTL default the pair
                // paints reversed (the exact defect 612dd38 fixed).
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    EditorValueFormat.of(context).dimensionsPlain(
                      preset.width.toInt(),
                      preset.height.toInt(),
                    ),
                    maxLines: 1,
                    style: AppTypeScale.caption.copyWith(
                      fontSize: 10,
                      color: tokens.textMuted,
                    ),
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
