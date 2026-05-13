import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/export_format.dart';
import '../../application/image_export_service.dart';
import '../../canvas/presentation/widgets/canvas_checkerboard.dart';

/// Reason the [ExportPreviewScreen] popped, surfaced to the caller.
enum ExportPreviewAction { save, share, cancel }

/// Result returned from the preview route.
///
/// `cancel` is encoded as [action] = [ExportPreviewAction.cancel] and
/// a `null` [result]. Save / Share carry their [ImageExportResult].
class ExportPreviewOutcome {
  const ExportPreviewOutcome({required this.action, this.result});
  final ExportPreviewAction action;
  final ImageExportResult? result;
}

/// Full-screen preview of the rendered export. The bytes are
/// rendered ONCE by the caller and passed in here — Save and Share
/// reuse the same buffer so what the user sees IS the file that
/// lands in the gallery / share sheet.
///
/// Architecture:
///   * The preview never re-encodes — eliminates any chance of a
///     "preview vs saved" mismatch.
///   * Save/Share go through [ImageExportService] (the same path the
///     sheet would have used), so the only behaviour difference vs
///     the no-preview flow is one extra confirmation tap.
class ExportPreviewScreen extends ConsumerStatefulWidget {
  const ExportPreviewScreen({
    super.key,
    required this.bytes,
    required this.format,
    required this.pixelWidth,
    required this.pixelHeight,
    this.jpgQuality,
  }) : assert(
         format != ExportFormat.jpg || jpgQuality != null,
         'jpgQuality is required when format is JPG',
       );

  /// Encoded bytes — the exact buffer that will be saved/shared.
  final Uint8List bytes;
  final ExportFormat format;
  final int pixelWidth;
  final int pixelHeight;

  /// JPG quality as a 0.0..1.0 fraction. Null for PNG (no quality).
  final double? jpgQuality;

  /// Push the preview as a full-screen dialog and await the user's
  /// chosen action.
  static Future<ExportPreviewOutcome?> push(
    BuildContext context, {
    required Uint8List bytes,
    required ExportFormat format,
    required int pixelWidth,
    required int pixelHeight,
    double? jpgQuality,
  }) {
    return Navigator.of(context).push<ExportPreviewOutcome>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ExportPreviewScreen(
          bytes: bytes,
          format: format,
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
          jpgQuality: jpgQuality,
        ),
      ),
    );
  }

  @override
  ConsumerState<ExportPreviewScreen> createState() =>
      _ExportPreviewScreenState();
}

class _ExportPreviewScreenState extends ConsumerState<ExportPreviewScreen> {
  bool _busy = false;

  /// Decoded pixel dimensions of [widget.bytes]. Resolved
  /// asynchronously after the first frame so the preview can
  /// (a) drive the [AspectRatio] from the *real* image rectangle
  /// rather than relying on the caller-supplied numbers matching,
  /// and (b) flag any mismatch with the caller-supplied dimensions
  /// in the size label. Falls back to the props before decode
  /// completes so the layout never "jumps".
  int? _decodedWidth;
  int? _decodedHeight;

  @override
  void initState() {
    super.initState();
    _decodeForLabel();
  }

  Future<void> _decodeForLabel() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final w = img.width;
      final h = img.height;
      img.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _decodedWidth = w;
        _decodedHeight = h;
      });
    } catch (_) {
      // Decode failure is non-fatal -- the preview falls back to
      // the caller-supplied dimensions for both layout and label.
    }
  }

  /// Width used to drive the preview's [AspectRatio]. Prefers the
  /// decoded value so the rectangle on screen is provably the same
  /// shape as the bytes that will be written to disk.
  int get _aspectWidth => _decodedWidth ?? widget.pixelWidth;
  int get _aspectHeight => _decodedHeight ?? widget.pixelHeight;

  String get _sizeLabel {
    final w = _decodedWidth ?? widget.pixelWidth;
    final h = _decodedHeight ?? widget.pixelHeight;
    return '$w × $h';
  }

  String get _byteSizeLabel => _formatBytes(widget.bytes.length);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.l10n.previewExportTitle),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: context.l10n.cancelAction,
          onPressed: _busy ? null : _onCancel,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Preview pane. The exported bytes are rendered inside
            // an [AspectRatio] sized to the *image's own* width:
            // height. This guarantees:
            //   * the on-screen rectangle has the exact same shape
            //     as the bitmap on disk -- no stretch, no squash;
            //   * the transparency checkerboard sits BEHIND the
            //     image rectangle (not the whole pane), so the
            //     image bounds are visually unambiguous and the
            //     letterbox area stays clearly "outside" the file.
            // Inside the aspect-correct box [BoxFit.fill] is safe
            // because the box ratio matches the image ratio --
            // there is no axis to distort along.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(
                  child: InteractiveViewer(
                    maxScale: 6,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _aspectHeight == 0
                            ? 1.0
                            : _aspectWidth / _aspectHeight,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                const CanvasCheckerboard(
                                  light: Color(0xFF2A2A2A),
                                  dark: Color(0xFF1F1F1F),
                                ),
                                Image.memory(
                                  widget.bytes,
                                  // Box ratio == image ratio, so
                                  // BoxFit.fill produces no
                                  // distortion and the image
                                  // exactly covers the
                                  // checkerboard.
                                  fit: BoxFit.fill,
                                  // No filtering blur on zoom-in
                                  // so the user sees the actual
                                  // pixels they'll save.
                                  filterQuality: FilterQuality.none,
                                  gaplessPlayback: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Info chips — what the user is about to commit to.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _InfoChip(icon: Icons.aspect_ratio_rounded, text: _sizeLabel),
                  _InfoChip(
                    icon: Icons.image_outlined,
                    text: widget.format.label,
                  ),
                  if (widget.format == ExportFormat.jpg &&
                      widget.jpgQuality != null)
                    _InfoChip(
                      icon: Icons.tune_rounded,
                      text: context.l10n.qualityPercent(
                        (widget.jpgQuality! * 100).round(),
                      ),
                    ),
                  _InfoChip(
                    icon: Icons.sd_storage_outlined,
                    text: _byteSizeLabel,
                  ),
                ],
              ),
            ),
            // Action bar.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _onCancel,
                      icon: const Icon(Icons.close_rounded),
                      label: Text(context.l10n.cancelAction),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _onShare,
                      icon: const Icon(Icons.ios_share_outlined),
                      label: Text(context.l10n.shareAction),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
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
                      onPressed: _busy ? null : _onSave,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(context.l10n.saveAction),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }

  void _onCancel() {
    Navigator.of(
      context,
    ).pop(const ExportPreviewOutcome(action: ExportPreviewAction.cancel));
  }

  Future<void> _onSave() async {
    setState(() => _busy = true);
    final svc = ref.read(imageExportServiceProvider);
    final result = await svc.saveToGallery(widget.bytes, format: widget.format);
    if (!mounted) return;
    Navigator.of(context).pop(
      ExportPreviewOutcome(action: ExportPreviewAction.save, result: result),
    );
  }

  Future<void> _onShare() async {
    setState(() => _busy = true);
    // Anchor the share sheet to the screen for iPad popover presentation.
    final box = context.findRenderObject();
    final origin = (box is RenderBox && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final svc = ref.read(imageExportServiceProvider);
    final result = await svc.share(
      widget.bytes,
      subject: context.l10n.designExportSubject,
      shareOrigin: origin,
      format: widget.format,
    );
    if (!mounted) return;
    Navigator.of(context).pop(
      ExportPreviewOutcome(action: ExportPreviewAction.share, result: result),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiled checkerboard so PNG transparency is visible in the preview.
/// Now provided by the shared [CanvasCheckerboard] widget — see the
/// preview pane builder above.
