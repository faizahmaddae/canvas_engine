import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../l10n/l10n.dart';
import '../../application/export_format.dart';
import '../../application/export_intent.dart';
import '../../application/export_session.dart';
import '../../application/image_export_service.dart';
import '../../canvas/presentation/widgets/canvas_checkerboard.dart';
import '../../../../core/utils/editor_value_format.dart';

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
///   * The caller's [ExportIntent] *is* the primary action: the user
///     already decided in the sheet, so the confirmation button
///     repeats that decision rather than asking again. The other
///     intent stays one tap away as a secondary button — changing
///     your mind must not cost a trip back to the sheet.
class ExportPreviewScreen extends ConsumerStatefulWidget {
  const ExportPreviewScreen({
    super.key,
    required this.bytes,
    required this.format,
    required this.pixelWidth,
    required this.pixelHeight,
    this.jpgQuality,
    this.intent = ExportIntent.save,
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

  /// The exit the user picked in the sheet. Drives the primary
  /// button's label, icon and action. Defaults to [ExportIntent.save]
  /// — the historical primary — so callers that don't express an
  /// intent get the previous layout unchanged.
  final ExportIntent intent;

  /// Push the preview as a full-screen dialog and await the user's
  /// chosen action.
  static Future<ExportPreviewOutcome?> push(
    BuildContext context, {
    required Uint8List bytes,
    required ExportFormat format,
    required int pixelWidth,
    required int pixelHeight,
    double? jpgQuality,
    ExportIntent intent = ExportIntent.save,
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
          intent: intent,
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

  /// Cached in [initState] because [dispose] needs it and `ref` is
  /// unsafe there. The notifier itself is a global provider that
  /// outlives this screen.
  late ExportSessionController _exportSession;

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
    _exportSession = ref.read(exportSessionControllerProvider.notifier);
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
    return EditorValueFormat.of(context).dimensions(w, h);
  }

  String get _byteSizeLabel => EditorValueFormat.of(
    context,
  ).mapDigits(_formatBytes(widget.bytes.length));

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    // System back is guarded while a save/share is in flight — the
    // close button already is (disabled via _busy); an unguarded
    // back silently dropped the outcome mid-operation.
    return PopScope(canPop: !_busy, child: _buildScaffold(context, tokens));
  }

  Widget _buildScaffold(BuildContext context, AppTokens tokens) {
    // This screen is a permanently-dark surface — a neutral surround is
    // the right frame for judging an exported image, whatever theme the
    // rest of the app is in. So it resolves its chrome from the DARK
    // token set regardless of the ambient brightness. Reading `tokens`
    // here would paint a light-mode `brand` (ink) button onto black.
    final onDark = AppTokens.dark;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        // `AppBarTheme.titleTextStyle` pins `color: scheme.onSurface`,
        // and a style's own colour beats `foregroundColor` — under the
        // light theme that painted near-black text on this black bar.
        titleTextStyle: Theme.of(
          context,
        ).appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
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
                crossAxisAlignment: WrapCrossAlignment.center,
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
                      // The arb string owns the percent sign (`%` /
                      // `٪`), so only the digits are formatted here —
                      // `percent()` would double the glyph.
                      text: context.l10n.qualityPercent(
                        EditorValueFormat.of(
                          context,
                        ).digits((widget.jpgQuality! * 100).round()),
                      ),
                    ),
                  _InfoChip(
                    icon: Icons.sd_storage_outlined,
                    text: _byteSizeLabel,
                  ),
                ],
              ),
            ),
            // Action bar. Order is Cancel · other intent · chosen
            // intent, so the button under the user's thumb is the one
            // they already asked for in the sheet.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('export-preview-cancel'),
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
                      key: const ValueKey('export-preview-secondary'),
                      onPressed: _busy ? null : _actionFor(_secondaryIntent),
                      icon: Icon(_iconFor(_secondaryIntent)),
                      label: Text(_labelFor(context, _secondaryIntent)),
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
                      key: const ValueKey('export-preview-primary'),
                      onPressed: _busy ? null : _actionFor(widget.intent),
                      icon: Icon(_iconFor(widget.intent)),
                      label: Text(_labelFor(context, widget.intent)),
                      style: FilledButton.styleFrom(
                        backgroundColor: onDark.brand,
                        foregroundColor: onDark.onBrand,
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

  /// The intent the user did *not* pick — offered as the secondary
  /// button so a change of mind never costs a trip back to the sheet
  /// (and a second render of the same bytes).
  ExportIntent get _secondaryIntent => switch (widget.intent) {
    ExportIntent.save => ExportIntent.share,
    ExportIntent.share => ExportIntent.save,
  };

  String _labelFor(BuildContext context, ExportIntent intent) =>
      switch (intent) {
        ExportIntent.save => context.l10n.saveAction,
        ExportIntent.share => context.l10n.shareAction,
      };

  IconData _iconFor(ExportIntent intent) => switch (intent) {
    ExportIntent.save => Icons.download_rounded,
    ExportIntent.share => Icons.ios_share_outlined,
  };

  VoidCallback _actionFor(ExportIntent intent) => switch (intent) {
    ExportIntent.save => _onSave,
    ExportIntent.share => _onShare,
  };

  void _onCancel() {
    Navigator.of(
      context,
    ).pop(const ExportPreviewOutcome(action: ExportPreviewAction.cancel));
  }

  Future<void> _onSave() async {
    setState(() => _busy = true);
    // Contract §6: the save critical section registers as a draft
    // session (see ExportSessionController). Ended on every exit
    // path below; [dispose] is the backstop.
    ref.read(exportSessionControllerProvider.notifier).begin();
    final svc = ref.read(imageExportServiceProvider);
    final result = await svc.saveToGallery(widget.bytes, format: widget.format);
    if (!mounted) return;
    if (result.outcome != ImageExportOutcome.success) {
      // Keep the preview (and the already-rendered bytes) alive so
      // the user can retry in place. Tearing the whole flow down
      // here used to cost: reopen sheet, re-pick settings,
      // re-render, re-tap — for the guaranteed first-run iOS path
      // of denying the Photos prompt.
      _showFailure(result.outcome);
      return;
    }
    ref.read(exportSessionControllerProvider.notifier).end();
    Navigator.of(context).pop(
      ExportPreviewOutcome(action: ExportPreviewAction.save, result: result),
    );
  }

  Future<void> _onShare() async {
    setState(() => _busy = true);
    // Same §6 session registration as [_onSave].
    ref.read(exportSessionControllerProvider.notifier).begin();
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
    if (result.outcome != ImageExportOutcome.success) {
      _showFailure(result.outcome);
      return;
    }
    ref.read(exportSessionControllerProvider.notifier).end();
    Navigator.of(context).pop(
      ExportPreviewOutcome(action: ExportPreviewAction.share, result: result),
    );
  }

  @override
  void dispose() {
    // Backstop for the unreachable-in-practice teardown-while-busy
    // path (PopScope guards normal pops while _busy): the registry
    // must never stay latched open after the surface that armed it
    // is gone. `end()` is idempotent. Uses the cached notifier —
    // `ref` is unsafe in dispose.
    _exportSession.end();
    super.dispose();
  }

  /// Inline failure surface: distinct copy for the permission path
  /// (actionable — the fix lives in system Settings) vs a write/share
  /// failure (retryable in place). The Save/Share buttons stay live.
  void _showFailure(ImageExportOutcome outcome) {
    ref.read(exportSessionControllerProvider.notifier).end();
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome == ImageExportOutcome.permissionDenied
              ? context.l10n.allowPhotoAccessSettings
              : context.l10n.somethingWentWrong,
        ),
        behavior: SnackBarBehavior.floating,
      ),
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
          // A chip carries ONE fact — a dimension pair, a byte count.
          // Letting it wrap split "1080 × 1350" across two lines, and
          // half of a number pair reads as a different number. If the
          // chip genuinely cannot fit, the `Wrap` gives it a run of its
          // own rather than breaking the value in half.
          Text(
            text,
            maxLines: 1,
            softWrap: false,
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
