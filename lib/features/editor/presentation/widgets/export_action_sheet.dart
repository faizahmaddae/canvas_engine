import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/user_error.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../../settings/application/settings_controller.dart';
import '../../application/document_controller.dart';
import '../../application/export_controller.dart';
import '../../application/export_format.dart';
import '../../application/export_quality.dart';
import '../../application/export_size.dart';
import '../../application/image_export_service.dart';
import '../../ui/editor_slider_row.dart';
import 'export_preview_screen.dart';
import 'section_label.dart';

/// Modal export sheet. The user picks an [ExportQuality] preset and
/// then taps **Save Image** or **Share** — both actions reuse the same
/// selected quality, satisfying the "consistent ratio across save +
/// share" requirement.
///
/// Architecture:
///   * The engine ([DocumentPngExporter]) keeps its `pixelRatio`
///     parameter unchanged. This sheet is the only place that maps
///     a user-facing label to a numeric ratio.
///   * Bytes are rasterised lazily (only when the user commits a
///     Save/Share action), so opening the sheet costs nothing.
class ExportActionSheet extends ConsumerStatefulWidget {
  const ExportActionSheet({super.key});

  /// Open the sheet. Must be called with the *editor screen's*
  /// context so [DocumentPngExporter] can reach the active overlay.
  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const ExportActionSheet(),
    );
  }

  @override
  ConsumerState<ExportActionSheet> createState() => _ExportActionSheetState();
}

class _ExportActionSheetState extends ConsumerState<ExportActionSheet> {
  /// Default mirrors the user's saved preference from Settings; falls
  /// back to [ExportQuality.original] when settings are still loading
  /// or have never been customised.
  late ExportQuality _quality = ref
      .read(appSettingsProvider)
      .defaultExportQuality;
  ExportFormat _format = ExportFormat.png;

  /// Selected output-size preset. Defaults to [ExportSize.original]
  /// so the existing canvas-relative behaviour is unchanged on first
  /// open. When a non-original preset is active the multiplier card
  /// strip hides — preset sizes are absolute pixel targets and the
  /// 1×/2×/3× knob would just confuse the math.
  ExportSize _size = ExportSize.original;

  /// JPG compression as a 0..1 fraction. Defaults to 0.9 per spec
  /// (90% quality is the industry-standard sweet spot for JPEG).
  /// Range exposed in the UI is 0.7 → 1.0.
  double _jpgQuality = 0.95;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = ref.watch(documentControllerProvider);
    final canvasW = doc.width.round();
    final canvasH = doc.height.round();
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header — title + canvas dimensions so the user always
            // sees what "Original" means in concrete numbers.
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4, top: 4),
              child: Row(
                children: [
                  Text(
                    l10n.exportDesignTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.canvasDimensions(canvasW, canvasH),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionLabel(l10n.sizeTool),
            const SizedBox(height: 8),
            _SizePickerRow(
              value: _size,
              enabled: !_busy,
              onChanged: _onSizeChanged,
            ),
            const SizedBox(height: 14),
            if (_size == ExportSize.original) ...[
              for (final q in ExportQuality.values) ...[
                _QualityCard(
                  quality: q,
                  canvasWidth: canvasW,
                  canvasHeight: canvasH,
                  selected: _quality == q,
                  enabled: !_busy,
                  onTap: () => setState(() => _quality = q),
                ),
                if (q != ExportQuality.values.last) const SizedBox(height: 8),
              ],
            ] else
              _PresetOutputSummary(
                size: _size,
                canvasWidth: canvasW,
                canvasHeight: canvasH,
              ),
            const SizedBox(height: 18),
            // Format section. Compact segmented row keeps both the
            // current selection and the alternative visible at a
            // glance — no hidden state.
            SectionLabel(l10n.formatLabel),
            const SizedBox(height: 8),
            _FormatSegmented(
              value: _format,
              enabled: !_busy,
              onChanged: (f) => setState(() => _format = f),
            ),
            // Quality slider only appears when JPG is selected (PNG is
            // lossless, so a quality knob would be misleading).
            if (_format.supportsQuality) ...[
              const SizedBox(height: 14),
              _JpgQualitySlider(
                value: _jpgQuality,
                enabled: !_busy,
                onChanged: (v) => setState(() => _jpgQuality = v),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _openPreview(),
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(l10n.previewShareAction),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _openPreview(),
                    icon: const Icon(Icons.image_search_rounded),
                    label: Text(l10n.previewSaveAction),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }

  /// Render once with the current settings, then route the user to
  /// the [ExportPreviewScreen] where they confirm Save / Share /
  /// Cancel. The bytes are reused inside the preview — no second
  /// render — so the user sees exactly what will be saved.
  Future<void> _openPreview() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final doc = ref.read(documentControllerProvider);
    final bytes = await _renderBytes();
    if (bytes == null || !mounted) return;
    final target = _size.target;
    final pixelW = target != null
        ? target.width.round()
        : (doc.width * _quality.pixelRatio).round();
    final pixelH = target != null
        ? target.height.round()
        : (doc.height * _quality.pixelRatio).round();
    final outcome = await ExportPreviewScreen.push(
      context,
      bytes: bytes,
      format: _format,
      pixelWidth: pixelW,
      pixelHeight: pixelH,
      jpgQuality: _format == ExportFormat.jpg ? _jpgQuality : null,
    );
    if (!mounted || outcome == null) return;
    switch (outcome.action) {
      case ExportPreviewAction.cancel:
        // Stay in the sheet so the user can tweak settings without
        // reopening from scratch.
        return;
      case ExportPreviewAction.save:
        navigator.pop();
        if (outcome.result != null) {
          _showOutcome(
            messenger,
            outcome.result!,
            successMsg: context.l10n.savedToPhotoLibrary,
          );
        }
      case ExportPreviewAction.share:
        navigator.pop();
        if (outcome.result != null) {
          _showOutcome(
            messenger,
            outcome.result!,
            successMsg: context.l10n.sharedMessage,
          );
        }
    }
  }

  /// Render the document at the currently-selected size + format.
  /// `_jpgQuality` is ignored by the engine for PNG; the controller
  /// passes it through so JPG paths get the slider value.
  Future<Uint8List?> _renderBytes() async {
    setState(() => _busy = true);
    try {
      // Pre-flight: warn the user when the requested resolution
      // exceeds the engine's safety cap and will be silently
      // downscaled. This is a single floating snackbar so the export
      // still proceeds — the alternative (silent reduction) would
      // surprise users on huge canvases.
      final exporter = ref.read(exportControllerProvider);
      final doc = ref.read(documentControllerProvider);
      final willReduce = exporter.willReduceResolution(
        document: doc,
        pixelRatio: _quality.pixelRatio,
        target: _size.target,
      );
      if (willReduce && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.reducedResolutionWarning),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return await exporter.exportImage(
        context: context,
        format: _format,
        pixelRatio: _quality.pixelRatio,
        jpgQuality: _jpgQuality,
        targetSize: _size.target,
      );
    } catch (e, st) {
      debugLogError('exportSheet/_run', e, st);
      if (!mounted) return null;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userMessageFor(
              e,
              fallback: context.l10n.somethingWentWrong,
              permissionDeniedMessage: context.l10n.allowPhotoAccessSettings,
              genericMessage: context.l10n.somethingWentWrong,
            ),
          ),
        ),
      );
      return null;
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  void _showOutcome(
    ScaffoldMessengerState messenger,
    ImageExportResult result, {
    required String successMsg,
  }) {
    final String text;
    switch (result.outcome) {
      case ImageExportOutcome.success:
        text = successMsg;
      case ImageExportOutcome.permissionDenied:
        text = context.l10n.allowPhotoAccessSettings;
      case ImageExportOutcome.failed:
        text = context.l10n.somethingWentWrong;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  /// Handle a tap in the size picker. The "Custom…" entry opens a
  /// dialog instead of selecting itself directly so we never enter a
  /// state where the user has chosen "Custom" without yet supplying
  /// dimensions.
  Future<void> _onSizeChanged(ExportSize next) async {
    if (!next.isCustom) {
      setState(() => _size = next);
      return;
    }
    final picked = await _CustomSizeDialog.show(context, initial: _size.target);
    if (!mounted || picked == null) return;
    setState(() => _size = picked);
  }
}

/// One row in the quality picker: title + multiplier badge + concrete
/// output dimensions, with a checkmark when selected.
class _QualityCard extends StatelessWidget {
  const _QualityCard({
    required this.quality,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ExportQuality quality;
  final int canvasWidth;
  final int canvasHeight;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outW = (canvasWidth * quality.pixelRatio).round();
    final outH = (canvasHeight * quality.pixelRatio).round();

    final bg = selected
        ? scheme.primary.withValues(alpha: 0.10)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.4);
    final border = selected
        ? scheme.primary.withValues(alpha: 0.6)
        : scheme.outlineVariant.withValues(alpha: 0.5);

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: selected ? 1.4 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Multiplier badge — small monospaced chip so the eye
              // can scan 1× / 2× / 3× at a glance.
              Container(
                width: 40,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  quality.multiplier,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _qualityLabel(context.l10n, quality),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$outW × $outH px',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outlineVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented control for picking [ExportFormat]. Renders both options
/// inline so the user can scan the available formats without opening
/// a menu — appropriate when there are exactly two choices.
class _FormatSegmented extends StatelessWidget {
  const _FormatSegmented({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ExportFormat value;
  final bool enabled;
  final ValueChanged<ExportFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final f in ExportFormat.values)
            Expanded(child: _segmentItem(theme, scheme, f)),
        ],
      ),
    );
  }

  Widget _segmentItem(ThemeData theme, ColorScheme scheme, ExportFormat f) {
    final selected = f == value;
    return GestureDetector(
      onTap: enabled ? () => onChanged(f) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          f.label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Quality slider for JPG. Range 0.7 → 1.0 per spec; the live label
/// shows whole-percent values (`Quality: 90%`) so users see exactly
/// what they're picking.
class _JpgQualitySlider extends StatelessWidget {
  const _JpgQualitySlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (value * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: Row(
            children: [
              Text(
                context.l10n.qualityLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        // 30 discrete stops between 70% and 100% — fine enough that
        // the user feels continuous control, coarse enough that the
        // displayed label doesn't twitch on every micro-drag.
        EditorSliderRow(
          value: value,
          min: 0.7,
          max: 1.0,
          divisions: 30,
          enabled: enabled,
          showReadout: false,
          format: (v) => '${(v * 100).round()}%',
          onChanged: onChanged,
          semanticLabel: context.l10n.qualityLabel,
        ),
      ],
    );
  }
}

/// Horizontal scrollable strip of size-preset chips. Keeps mobile
/// chrome minimal — one tap to switch presets, plus a dedicated
/// "Custom…" entry that opens the dimensions dialog.
class _SizePickerRow extends StatelessWidget {
  const _SizePickerRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ExportSize value;
  final bool enabled;
  final ValueChanged<ExportSize> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: ExportSize.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final preset = ExportSize.values[i];
          // For "Custom" the chip is selected only when the active
          // value is itself a custom one (matched via isCustom flag,
          // since the typed dimensions create a fresh instance).
          final selected = preset.isCustom ? value.isCustom : preset == value;
          return _SizeChip(
            label: selected && preset.isCustom
                ? context.l10n.customSizeChip(
                    value.target?.width.round() ?? 0,
                    value.target?.height.round() ?? 0,
                  )
                : _sizeLabel(context.l10n, preset),
            selected: selected,
            enabled: enabled,
            onTap: () => onChanged(preset),
            scheme: scheme,
            theme: theme,
          );
        },
      ),
    );
  }
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.scheme,
    required this.theme,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? scheme.primary
        : scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Concise read-out shown in place of the quality cards when a fixed
/// preset is active. Tells the user the absolute pixel rectangle their
/// design will be fitted into, plus an inline note when the canvas
/// aspect differs (so the letterbox bands aren't a surprise).
class _PresetOutputSummary extends StatelessWidget {
  const _PresetOutputSummary({
    required this.size,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  final ExportSize size;
  final int canvasWidth;
  final int canvasHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = size.target!;
    final tw = target.width.round();
    final th = target.height.round();
    final canvasAspect = canvasWidth / canvasHeight;
    final targetAspect = target.width / target.height;
    // 0.5% tolerance so we don't flag effectively-equal aspects.
    final aspectMatches =
        (canvasAspect - targetAspect).abs() / canvasAspect < 0.005;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.aspect_ratio_rounded,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.outputPixels(tw, th),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  aspectMatches
                      ? context.l10n.matchesCanvasAspect
                      : context.l10n.letterboxExportHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog that collects width + height in pixels for the "Custom"
/// preset. Validates positive integers within a sane upper bound to
/// keep memory predictable; returns `null` on cancel.
class _CustomSizeDialog extends StatefulWidget {
  const _CustomSizeDialog({this.initial});

  final ui.Size? initial;

  static Future<ExportSize?> show(BuildContext context, {ui.Size? initial}) {
    return showDialog<ExportSize>(
      context: context,
      builder: (_) => _CustomSizeDialog(initial: initial),
    );
  }

  @override
  State<_CustomSizeDialog> createState() => _CustomSizeDialogState();
}

class _CustomSizeDialogState extends State<_CustomSizeDialog> {
  late final TextEditingController _w = TextEditingController(
    text: widget.initial?.width.round().toString() ?? '1080',
  );
  late final TextEditingController _h = TextEditingController(
    text: widget.initial?.height.round().toString() ?? '1080',
  );
  String? _error;

  // Hard upper bound — Skia surface allocations beyond ~8K square
  // start to fail on mid-tier devices. 8000 leaves comfortable
  // headroom for the composite step.
  static const int _maxDimension = 8000;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  void _commit() {
    final w = int.tryParse(_w.text.trim());
    final h = int.tryParse(_h.text.trim());
    if (w == null || h == null || w <= 0 || h <= 0) {
      setState(() => _error = context.l10n.enterPositiveWholeNumbers);
      return;
    }
    if (w > _maxDimension || h > _maxDimension) {
      setState(
        () => _error = context.l10n.maximumDimensionEitherSide(_maxDimension),
      );
      return;
    }
    Navigator.of(context).pop(ExportSize.customSize(w, h));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.customSizeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _w,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.widthPxLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _h,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.heightPxLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _commit(),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancelAction),
        ),
        FilledButton(
          onPressed: _commit,
          child: Text(context.l10n.useSizeAction),
        ),
      ],
    );
  }
}

String _qualityLabel(AppLocalizations l10n, ExportQuality quality) {
  return switch (quality) {
    ExportQuality.original => l10n.originalSizeQuality,
    ExportQuality.high => l10n.highQuality,
    ExportQuality.ultra => l10n.ultraQuality,
  };
}

String _sizeLabel(AppLocalizations l10n, ExportSize size) {
  if (size.isCustom) return l10n.customLabel;
  return switch (size.id) {
    'original' => l10n.originalOption,
    'square_1080' => l10n.squareLabel,
    'story_1080x1920' => l10n.storyLabel,
    'portrait_1080x1350' => l10n.portraitLabel,
    _ => size.label,
  };
}
