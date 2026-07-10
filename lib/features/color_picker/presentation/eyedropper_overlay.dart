import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/theme/app_tokens.dart';

/// Runs an eyedropper session over the canvas board identified by
/// [boundaryKey] (see `canvasBoardBoundaryKeyProvider`).
///
/// The board is snapshotted once at one pixel per logical canvas
/// unit; a full-screen overlay then lets the user drag anywhere —
/// a loupe follows the finger showing the colour under it, and
/// [onSample] streams every hovered colour so the host can apply it
/// live. Releasing over the board resolves with the sampled colour;
/// releasing (or tapping) outside the board cancels with `null`.
///
/// Sampled colours are opaque RGB — alpha policy stays with the
/// caller, matching the picker's "swatch taps preserve alpha" rule.
Future<Color?> startCanvasEyedropper(
  BuildContext context, {
  required GlobalKey boundaryKey,
  ValueChanged<Color>? onSample,
}) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary || !renderObject.attached) {
    return null;
  }
  // One snapshot per session: pixelRatio 1 on a boundary that sits
  // inside the viewport transform yields exactly doc-sized pixels,
  // so zoom level never affects sampling accuracy.
  final image = await renderObject.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) {
    image.dispose();
    return null;
  }
  if (!context.mounted) {
    image.dispose();
    return null;
  }

  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<Color?>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _EyedropperOverlay(
      boundaryKey: boundaryKey,
      pixels: bytes,
      imageWidth: image.width,
      imageHeight: image.height,
      onSample: onSample,
      onDone: (picked) {
        entry.remove();
        image.dispose();
        completer.complete(picked);
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _EyedropperOverlay extends StatefulWidget {
  const _EyedropperOverlay({
    required this.boundaryKey,
    required this.pixels,
    required this.imageWidth,
    required this.imageHeight,
    required this.onSample,
    required this.onDone,
  });

  final GlobalKey boundaryKey;
  final ByteData pixels;
  final int imageWidth;
  final int imageHeight;
  final ValueChanged<Color>? onSample;
  final ValueChanged<Color?> onDone;

  @override
  State<_EyedropperOverlay> createState() => _EyedropperOverlayState();
}

class _EyedropperOverlayState extends State<_EyedropperOverlay> {
  Offset? _pointer; // global position while the finger is down
  Color? _hover;
  bool _done = false;

  /// Maps a global (screen) position to the colour under it on the
  /// board snapshot, or `null` when outside the board. The boundary
  /// RenderBox sits inside the viewport transform, so globalToLocal
  /// walks zoom + pan for free.
  Color? _sampleAt(Offset global) {
    final renderObject = widget.boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    final local = renderObject.globalToLocal(global);
    final x = local.dx.floor();
    final y = local.dy.floor();
    if (x < 0 || y < 0 || x >= widget.imageWidth || y >= widget.imageHeight) {
      return null;
    }
    final byteOffset = (y * widget.imageWidth + x) * 4;
    final r = widget.pixels.getUint8(byteOffset);
    final g = widget.pixels.getUint8(byteOffset + 1);
    final b = widget.pixels.getUint8(byteOffset + 2);
    // Alpha is deliberately dropped — an eyedrop is a hue choice.
    return Color(0xFF000000 | (r << 16) | (g << 8) | b);
  }

  void _update(Offset global) {
    final sampled = _sampleAt(global);
    setState(() {
      _pointer = global;
      _hover = sampled;
    });
    if (sampled != null) widget.onSample?.call(sampled);
  }

  void _finish(Offset global) {
    if (_done) return;
    _done = true;
    widget.onDone(_sampleAt(global));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _update(e.position),
        onPointerMove: (e) => _update(e.position),
        onPointerUp: (e) => _finish(e.position),
        onPointerCancel: (_) {
          if (_done) return;
          _done = true;
          widget.onDone(null);
        },
        child: Stack(
          children: [
            if (_pointer != null && _hover != null)
              _Loupe(
                position: _pointer!,
                color: _hover!,
                ringColor: tokens.surface,
              ),
          ],
        ),
      ),
    );
  }
}

/// Magnifier-style ring above the finger: sampled colour inside a
/// thick surface-coloured ring with a centre dot marking the exact
/// sample point.
class _Loupe extends StatelessWidget {
  const _Loupe({
    required this.position,
    required this.color,
    required this.ringColor,
  });

  static const double _size = 56;
  static const double _fingerGap = 70;

  final Offset position;
  final Color color;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - _size / 2,
      top: position.dy - _size / 2 - _fingerGap,
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: ringColor, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _fingerGap - _size / 2 - 3),
            // Crosshair dot on the exact sample point.
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ringColor,
                border: Border.all(color: Colors.black.withValues(alpha: 0.4)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
