import 'package:flutter/widgets.dart';

/// Application-wide memory-pressure handler.
///
/// ## Why this exists
///
/// A photo editor is the most memory-hungry app a user runs on
/// their phone. A 12 MP photo is 48 MB of decoded RGBA. With five
/// layers + thumbnails + the export raster + the system's other
/// apps, an unconfigured Flutter app routinely tips over the OS
/// memory limit on mid-range Android devices and gets killed.
///
/// Two complementary strategies, both installed by [installMemoryGuard]:
///
/// 1. **Cap the [ImageCache].** Flutter's default
///    `maximumSizeBytes` is 100 MB and `maximumSize` is 1000 — both
///    of which are far too generous for a tool that decodes its own
///    bitmaps. We cap to 64 MB / 50 entries: enough for the editor
///    thumbnail strip and a handful of imported references, small
///    enough that the cache itself can never be the reason we run
///    out of headroom.
///
/// 2. **Listen for `didHaveMemoryPressure`.** When the OS asks the
///    process to free what it can, drop every decoded bitmap and
///    every memoised colour matrix. The next render will re-decode,
///    which is fine — the alternative is being killed.
///
/// Wire from `main()` exactly once: `installMemoryGuard()` returns
/// the [WidgetsBindingObserver] so a hot-reload-friendly app can
/// install/uninstall, but in practice nothing ever uninstalls.
class MemoryGuard with WidgetsBindingObserver {
  MemoryGuard._();

  /// 64 MB. A 12 MP RGBA frame is 48 MB; 64 MB lets the cache hold
  /// roughly one full-resolution image plus its thumbnail. Anything
  /// the editor displays beyond that is going to be rasterised
  /// fresh anyway because the canvas paints the layer stack via
  /// [RepaintBoundary], not the [ImageCache].
  static const int _kImageCacheBytes = 64 * 1024 * 1024;

  /// Hard count limit. Each entry is small metadata; this exists
  /// purely to bound the time `ImageCache.evict` spends sweeping a
  /// pathological gallery import.
  static const int _kImageCacheCount = 50;

  /// Install the guard. Idempotent — calling more than once is a
  /// no-op (the second call sees the same observer already
  /// registered).
  static void install() {
    if (_installed) return;
    _installed = true;
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = _kImageCacheBytes;
    cache.maximumSize = _kImageCacheCount;
    WidgetsBinding.instance.addObserver(_singleton);
  }

  static bool _installed = false;
  static final MemoryGuard _singleton = MemoryGuard._();

  @override
  void didHaveMemoryPressure() {
    // Drop every decoded image. The editor will re-decode on the
    // next paint — slower, but recoverable. The alternative is the
    // OS killing us, which loses unsaved work that autosave hasn't
    // yet flushed.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

/// Convenience for `main()`.
void installMemoryGuard() => MemoryGuard.install();
