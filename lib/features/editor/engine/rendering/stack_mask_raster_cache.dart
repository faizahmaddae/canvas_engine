import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/layer_mask.dart';

/// Process-wide cache of stack-mask alpha rasters.
///
/// `ImageShader` needs its `ui.Image` synchronously inside
/// `shaderCallback`, so the raster must exist *before* paint. This
/// cache is the bridge: [lookup] answers synchronously from completed
/// rasters, and [request] kicks off an asynchronous rasterize
/// (`ui.decodeImageFromPixels`) whose completion notifies the caller
/// so it can rebuild. Until the raster resolves the caller renders
/// the un-effected base only — a one-frame delay of the adjustment is
/// invisible; a one-frame flash of the *unmasked* effect is not
/// (docs/effects-a3-scoped-plan-2026-07.md §7.3).
///
/// The alpha source is [LayerMask.sampleAlpha] evaluated at every
/// pixel centre — the engine's own alpha definition (linear outward
/// feather ramp, `inverted` flag) is the literal ground truth of what
/// renders. A `MaskFilter.blur` approximation was rejected in the A3
/// spike: its Gaussian profile deviates from `sampleAlpha`'s linear
/// ramp, so hit-tests and rendered pixels would disagree inside the
/// feather band (§7.1).
///
/// Keying: `(mask, width, height)` with [LayerMask] value equality.
/// Rasters are layer-local logical px — the feather is layer-local by
/// contract, so a resize changes the key and re-rasterizes.
/// DPR-scaling the raster is a quality follow-up, not a correctness
/// requirement (§7.3).
class StackMaskRasterCache {
  StackMaskRasterCache._();

  static final StackMaskRasterCache instance = StackMaskRasterCache._();

  /// Completed rasters in LRU order (oldest first). Values are owned
  /// by the cache: evicted images are disposed here and must not be
  /// retained by callers across frames — re-[lookup] every build.
  final LinkedHashMap<_RasterKey, ui.Image> _ready =
      LinkedHashMap<_RasterKey, ui.Image>();

  /// In-flight rasterizations and the rebuild callbacks awaiting them.
  final Map<_RasterKey, List<void Function()>> _pending =
      <_RasterKey, List<void Function()>>{};

  int _bytes = 0;

  /// Soft byte budget, tuneable in tests. 32 MB ≈ six full-canvas
  /// 1080² alpha rasters (w·h·4 bytes each); per-layer masks are
  /// usually far smaller, so in practice this holds dozens. Sibling
  /// of the docs/effects.md §10 budgets: this cache is the first real
  /// consumer of that eviction design (the effect-picture cache
  /// itself is still unimplemented).
  int byteBudget = 32 * 1024 * 1024;

  /// Synchronous lookup. Touches the entry for LRU on hit.
  ui.Image? lookup(LayerMask mask, int width, int height) {
    final key = _RasterKey(mask, width, height);
    final img = _ready.remove(key);
    if (img == null) return null;
    _ready[key] = img; // re-insert = most recently used
    return img;
  }

  /// Ensure a raster for `(mask, width, height)` exists or is being
  /// built. [onReady] fires (once) after the raster lands in the
  /// cache; callers typically `setState` to re-run [lookup]. If the
  /// raster is already available this is a no-op — call [lookup]
  /// first.
  void request(LayerMask mask, int width, int height, void Function() onReady) {
    if (width <= 0 || height <= 0) return;
    final key = _RasterKey(mask, width, height);
    if (_ready.containsKey(key)) {
      onReady();
      return;
    }
    final waiters = _pending[key];
    if (waiters != null) {
      waiters.add(onReady);
      return;
    }
    _pending[key] = <void Function()>[onReady];
    _rasterize(key);
  }

  void _rasterize(_RasterKey key) {
    // One w×h sampleAlpha pass per (mask, size) pair. Runs on the UI
    // isolate: sampleAlpha is pure math, PathMask needs ui.Path, and
    // typical layer-local sizes are a few hundred px per side. If
    // profiling ever shows jank on very large layers, chunking this
    // loop across frames is the follow-up — not an isolate (ui.Path
    // is not portable).
    final w = key.width, h = key.height;
    final bytes = Uint8List(w * h * 4);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final a = (key.mask.sampleAlpha(ui.Offset(x + 0.5, y + 0.5)) * 255)
            .round();
        bytes[i] = 255;
        bytes[i + 1] = 255;
        bytes[i + 2] = 255;
        bytes[i + 3] = a;
        i += 4;
      }
    }
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888, (img) {
      _insert(key, img);
      final waiters = _pending.remove(key);
      if (waiters == null) return;
      for (final cb in waiters) {
        cb();
      }
    });
  }

  void _insert(_RasterKey key, ui.Image img) {
    _ready[key] = img;
    _bytes += _sizeOf(key);
    // Evict LRU until under budget — but never the entry just added,
    // even if it alone exceeds the budget (mirrors HistoryStack's
    // newest-entry rule).
    while (_bytes > byteBudget && _ready.length > 1) {
      final oldest = _ready.keys.first;
      final evicted = _ready.remove(oldest)!;
      _bytes -= _sizeOf(oldest);
      evicted.dispose();
    }
  }

  static int _sizeOf(_RasterKey key) => key.width * key.height * 4;

  /// Test hook: drop every raster and cancel bookkeeping. Pending
  /// decodes complete into an empty cache harmlessly.
  void clearForTest() {
    for (final img in _ready.values) {
      img.dispose();
    }
    _ready.clear();
    _bytes = 0;
  }
}

class _RasterKey {
  const _RasterKey(this.mask, this.width, this.height);

  final LayerMask mask;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _RasterKey &&
      other.mask == mask &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(mask, width, height);
}
