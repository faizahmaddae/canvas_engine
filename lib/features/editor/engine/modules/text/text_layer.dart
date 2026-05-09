import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../text/domain/text_style_presets.dart' show textDirectionForContent;
import '../../core/editor_layer.dart';
import '../../core/layer_capabilities.dart';
import '../../core/layer_transform.dart';
import 'text_style_spec.dart';

export 'text_style_spec.dart';

/// How a [TextLayer] reacts when its bounding box is resized.
///
/// The Text tool exposes this as a per-layer choice ("Resize behavior"
/// in the More sheet). It is not a global app setting.
///
/// * [scaleText] — default. Corner drag uniformly scales the rendered
///   text via [FittedBox]. Aspect-locked. The bounding box is kept in
///   sync with the natural text size by `TextToolController` whenever
///   content or style changes. This is how a single "text object" feels
///   in Figma / Canva.
/// * [resizeBox] — paragraph-style text box. Font size is fixed; the
///   box width determines the wrap column and height auto-fits the
///   wrapped content. Corner drag changes the wrap width (no aspect
///   lock).
enum TextResizeMode { scaleText, resizeBox }

/// Origin / behavioural class of a [TextLayer]. The renderer treats
/// every kind identically (it's still glyphs in a box) but the
/// editor uses this flag to route selection to the right toolbar
/// and to suppress text-only affordances (font picker, inline
/// editor, color slot, …) for non-editable text such as emoji
/// stickers.
///
/// * [normal] — user-typed text. Opens the Text sub-tool toolbar
///   on selection. Editable via the unified text editor sheet.
/// * [emojiSticker] — inserted from the Sticker / emoji picker.
///   Treated as a sticker object: transform handles work, but
///   the Text toolbar / inline edit are intentionally bypassed.
enum TextLayerKind { normal, emojiSticker }

/// Concrete layer holding a string + [TextStyleSpec]. Extending [EditorLayer]
/// is the ONLY place the text module touches engine code – rendering still
/// goes through [buildContent].
class TextLayer extends EditorLayer {
  const TextLayer({
    required super.id,
    required super.transform,
    required this.content,
    required this.style,
    this.resizeMode = TextResizeMode.scaleText,
    this.kind = TextLayerKind.normal,
    super.name,
    super.visible,
    super.locked,
    super.opacity,
  }) : super(
          capabilities: resizeMode == TextResizeMode.scaleText
              ? LayerCapabilities.textScale
              : LayerCapabilities.textBox,
        );

  final String content;
  final TextStyleSpec style;
  final TextResizeMode resizeMode;
  final TextLayerKind kind;

  /// Convenience: true when this layer is an emoji sticker so
  /// callers don't have to reach for the enum value.
  bool get isSticker => kind == TextLayerKind.emojiSticker;

  @override
  String get type => 'text';

  @override
  EditorLayer withTransform(LayerTransform transform) => TextLayer(
        id: id,
        transform: transform,
        content: content,
        style: style,
        resizeMode: resizeMode,
        kind: kind,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withVisibility(bool visible) => TextLayer(
        id: id,
        transform: transform,
        content: content,
        style: style,
        resizeMode: resizeMode,
        kind: kind,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withLocked(bool locked) => TextLayer(
        id: id,
        transform: transform,
        content: content,
        style: style,
        resizeMode: resizeMode,
        kind: kind,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
      );

  @override
  EditorLayer withOpacity(double opacity) => TextLayer(
        id: id,
        transform: transform,
        content: content,
        style: style,
        resizeMode: resizeMode,
        kind: kind,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity.clamp(0.0, 1.0),
      );

  TextLayer copyWith({
    String? content,
    TextStyleSpec? style,
    TextResizeMode? resizeMode,
    TextLayerKind? kind,
    String? name,
  }) {
    return TextLayer(
      id: id,
      transform: transform,
      content: content ?? this.content,
      style: style ?? this.style,
      resizeMode: resizeMode ?? this.resizeMode,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      visible: visible,
      locked: locked,
      opacity: opacity,
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    // Pure read-only render. Editing is initiated from the floating
    // toolbar's edit pill, which opens the unified bottom-sheet text
    // editor (see `text_floating_toolbar.dart`).
    return _TextContent(layer: this);
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseJson(),
        'content': content,
        'style': style.toJson(),
        'resizeMode': resizeMode.name,
        if (kind != TextLayerKind.normal) 'kind': kind.name,
      };

  /// Decode a [TextLayer] from JSON produced by [toJson]. Unknown /
  /// missing `resizeMode` falls back to [TextResizeMode.scaleText] so
  /// older saves keep working.
  factory TextLayer.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('TextLayer.id missing or not a string');
    }
    final transformJson = json['transform'];
    if (transformJson is! Map) {
      throw const FormatException('TextLayer.transform missing');
    }
    final content = json['content'];
    if (content is! String) {
      throw const FormatException('TextLayer.content missing or not a string');
    }
    final styleJson = json['style'];
    final modeName = json['resizeMode'];
    final resizeMode = modeName is String
        ? TextResizeMode.values.firstWhere(
            (m) => m.name == modeName,
            orElse: () => TextResizeMode.scaleText,
          )
        : TextResizeMode.scaleText;
    final kindName = json['kind'];
    final kind = kindName is String
        ? TextLayerKind.values.firstWhere(
            (k) => k.name == kindName,
            orElse: () => TextLayerKind.normal,
          )
        : TextLayerKind.normal;
    return TextLayer(
      id: id,
      transform: LayerTransform.fromJson(
        Map<String, dynamic>.from(transformJson),
      ),
      content: content,
      style: styleJson is Map
          ? TextStyleSpec.fromJson(Map<String, dynamic>.from(styleJson))
          : const TextStyleSpec(),
      resizeMode: resizeMode,
      kind: kind,
      name: json['name'] as String?,
      visible: json['visible'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
    );
  }

  Alignment _align() {
    switch (style.alignment) {
      case TextAlign.left:
      case TextAlign.start:
        return Alignment.centerLeft;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.center:
      case TextAlign.justify:
        return Alignment.center;
    }
  }

  // ---------------------------------------------------------------
  // Equality.
  //
  // CRITICAL: the base [EditorLayer.==] only compares identity-level
  // fields (id, transform, capabilities, visible, locked, name). It
  // deliberately ignores subclass-specific payload because it has no
  // way to know about it. That means without this override, two
  // [TextLayer]s with different `content` / `style` compare equal —
  // which propagates up through `EditorDocument.==` (uses `listEquals`
  // on layers) and causes [Notifier] to skip the state emit, so the
  // canvas does not rebuild after a style change until some other
  // interaction forces a refresh.
  //
  // Override here so style mutations actually invalidate document
  // equality and reach the renderer in real time.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TextLayer &&
          super == other &&
          other.content == content &&
          other.style == style &&
          other.resizeMode == resizeMode &&
          other.kind == kind);

  @override
  int get hashCode =>
      Object.hash(super.hashCode, content, style, resizeMode, kind);
}

/// Read-only text layer content.
///
/// Text editing is intentionally NOT inline. The single, unified entry
/// point lives in the floating contextual toolbar's edit pill, which
/// opens a focused bottom-sheet text editor. Keeping the canvas render
/// pure read-only removes the second-tap-to-edit / double-tap-to-edit
/// duplication and avoids the focus / keyboard juggling that
/// inline-on-canvas TextField inevitably brings.
class _TextContent extends StatelessWidget {
  const _TextContent({required this.layer});
  final TextLayer layer;

  @override
  Widget build(BuildContext context) {
    // Emoji stickers go down a hardened render path that bypasses
    // [TextStyle.shadows] on color-emoji glyphs.
    //
    // Why a separate path:
    //   * Color emoji glyphs (CBDT / SBIX bitmap glyphs) interact
    //     poorly with [TextStyle.shadows] on Flutter's Impeller
    //     backend (notably on Android emulator + several real
    //     devices). The glyph atlas state can be corrupted mid-frame
    //     when a blurred shadow is uploaded for a color glyph,
    //     producing intermittent failure modes:
    //       1. The emoji renders as a solid black silhouette
    //          (the shadow fills the glyph bounds with no color
    //          composite on top).
    //       2. The emoji disappears entirely.
    //       3. A *sibling* emoji-sticker layer in the same Stack
    //          renders incorrectly because the broken atlas write
    //          leaks into the next draw call \u2014 which is exactly the
    //          \u201cedit one sticker, the other turns black/disappears\u201d
    //          bug this method exists to fix.
    //   * Sticker style presets (see [StickerStylePreset]) all rely
    //     on a shadow to imply outline / pop / glow / soft-shadow,
    //     so this is the hot path for any non-original sticker.
    //
    // The fix renders the shadow as a manually composed Stack:
    // the same emoji is drawn twice \u2014 once underneath, tinted to
    // [shadowColor] via [ColorFiltered], blurred via [ImageFiltered]
    // and translated by [shadowOffset]; once on top, untouched.
    // [TextStyle.shadows] is left null so the broken color-glyph
    // shadow path is never exercised.
    if (layer.isSticker) {
      return _buildStickerContent(context);
    }
    return _buildTextContent(context);
  }

  /// Hardened render path for [TextLayerKind.emojiSticker] \u2014 see the
  /// long comment in [build] for why this exists.
  ///
  /// IMPORTANT: this method must NEVER paint the sticker via a
  /// `Text` widget (or any other path that draws color-emoji glyphs
  /// through the live glyph atlas). Doing so re-introduces the
  /// "scale one sticker, sibling stickers vanish" bug — the active
  /// layer's repaint boundary picture is re-recorded every gesture
  /// frame, and on Impeller that re-records the color-glyph draw
  /// commands plus (when shadow is enabled) an `ImageFiltered` /
  /// `ColorFiltered(BlendMode.srcATop)` saveLayer over them. Both
  /// paths can corrupt the shared color-emoji glyph atlas mid-frame
  /// so sibling stickers' cached pictures end up referencing evicted
  /// atlas slots and paint as empty rects (still hit-testable, just
  /// invisible). The fix below pre-rasterises each unique glyph to a
  /// `ui.Image` exactly once via [_StickerGlyphRasterCache] and then
  /// only ever paints `RawImage`s — which go through the regular
  /// image atlas, not the color-glyph atlas, and so cannot trigger
  /// the cross-layer corruption.
  Widget _buildStickerContent(BuildContext context) {
    final style = layer.style;
    final transform = layer.transform;
    final image = _StickerGlyphRasterCache.instance.acquire(
      content: layer.content,
      fontFamily: style.fontFamily,
      fontWeight: style.fontWeight,
      letterSpacing: style.letterSpacing,
      lineHeight: style.lineHeight,
      textDirection: textDirectionForContent(layer.content),
    );
    if (image == null) {
      // Empty content (or rasterisation failed). Reserve the box so
      // hit-testing and selection chrome still align with the layer.
      return SizedBox.fromSize(size: transform.size);
    }
    Widget body = RawImage(
      image: image,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      // RawImage does not retain the image, so the cache stays in
      // charge of the lifetime — see [_StickerGlyphRasterCache].
    );
    if (style.shadowColor != null) {
      // Shadow pass: same rasterised glyph, tinted to shadowColor and
      // blurred. `srcATop` keeps the tint inside the silhouette of
      // the bitmap regardless of its original colour. Crucially the
      // ImageFilter / ColorFilter operate on a `RawImage`, not a
      // color-emoji `Text`, so they cannot disturb the glyph atlas.
      final shadow = Transform.translate(
        offset: style.shadowOffset,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: math.max(0.0, style.shadowBlur),
            sigmaY: math.max(0.0, style.shadowBlur),
          ),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              style.shadowColor!,
              BlendMode.srcATop,
            ),
            child: RawImage(
              image: image,
              fit: BoxFit.contain,
              alignment: Alignment.center,
            ),
          ),
        ),
      );
      body = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: shadow),
          Positioned.fill(child: body),
        ],
      );
    }
    return SizedBox.fromSize(size: transform.size, child: body);
  }

  Widget _buildTextContent(BuildContext context) {
    final style = layer.style;
    final transform = layer.transform;
    final textStyle = TextStyle(
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
      color: style.color,
      fontWeight: style.fontWeight,
      fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
      decoration: style.underline ? TextDecoration.underline : null,
      letterSpacing: style.letterSpacing,
      height: style.lineHeight,
      shadows: style.shadowColor == null
          ? null
          : [
              Shadow(
                color: style.shadowColor!,
                blurRadius: style.shadowBlur,
                offset: style.shadowOffset,
              ),
            ],
    );

    // Glyph outline ("border"). Rendered as a stroked TextStyle on
    // top of the filled text using `Stack` — Canva-style.
    // `foreground` overrides `color`, so we copy the base style and
    // swap in a stroke `Paint`. Shadows attach to the stroked layer
    // so they read as a true drop-shadow of the outlined silhouette.
    final outlineStyle = style.outlineColor == null
        ? null
        : textStyle.copyWith(
            color: null,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = style.outlineWidth
              ..color = style.outlineColor!,
          );

    // Per-layer resize behaviour:
    //  * scaleText — [FittedBox.contain] uniformly scales the
    //    rendered text to fill the bounding box. Corner drag changes
    //    the box size and the visual font scales with it (no reflow,
    //    no wrap). Box stays in sync with natural text size via
    //    `TextToolController`.
    //  * resizeBox — paragraph text box. Font size is fixed; the box
    //    width is the wrap column. Height auto-fits wrapped content;
    //    overflowing height is clipped (matching pro editors).
    //
    // Background fill (if set) is rendered via [_withBackground] so
    // both modes share one decoration path: a rounded rectangle that
    // covers the bounding box behind the text.
    switch (layer.resizeMode) {
      case TextResizeMode.scaleText:
        final text = _withOutline(
          layer.content,
          textAlign: style.alignment,
          softWrap: false,
          fillStyle: textStyle,
          strokeStyle: outlineStyle,
          textDirection: textDirectionForContent(layer.content),
        );
        return SizedBox.fromSize(
          size: transform.size,
          child: _withBackground(
            style,
            FittedBox(
              fit: BoxFit.contain,
              alignment: layer._align(),
              child: text,
            ),
          ),
        );
      case TextResizeMode.resizeBox:
        final text = _withOutline(
          layer.content,
          textAlign: style.alignment,
          softWrap: true,
          fillStyle: textStyle,
          strokeStyle: outlineStyle,
          textDirection: textDirectionForContent(layer.content),
        );
        return SizedBox.fromSize(
          size: transform.size,
          child: _withBackground(
            style,
            ClipRect(
              child: Align(
                alignment: layer._align(),
                child: text,
              ),
            ),
          ),
        );
    }
  }

  /// Wrap [child] in a rounded background fill when
  /// [TextStyleSpec.backgroundColor] is set. No-op otherwise so the
  /// hot path stays a plain widget tree.
  ///
  /// `backgroundRadius` is a percentage (0..1) applied at paint-time
  /// against the actual rendered box, so chips/badges stay properly
  /// pill-shaped at any font size. See [textBackgroundRadiusPx].
  Widget _withBackground(TextStyleSpec style, Widget child) {
    if (style.backgroundColor == null) return child;
    return TextBackgroundBox(
      color: style.backgroundColor!,
      radiusPercent: style.backgroundRadius,
      paddingX: style.backgroundPaddingX,
      paddingY: style.backgroundPaddingY,
      child: child,
    );
  }

  /// Render [content] with an optional glyph outline behind the
  /// filled glyphs. Skips the stack entirely when [strokeStyle] is
  /// null so the hot path stays a single Text widget.
  Widget _withOutline(
    String content, {
    required TextAlign textAlign,
    required bool softWrap,
    required TextStyle fillStyle,
    required TextStyle? strokeStyle,
    required TextDirection textDirection,
  }) {
    final filled = Text(
      content,
      textAlign: textAlign,
      softWrap: softWrap,
      style: fillStyle,
      textDirection: textDirection,
    );
    if (strokeStyle == null) return filled;
    return Stack(
      children: [
        Text(
          content,
          textAlign: textAlign,
          softWrap: softWrap,
          style: strokeStyle,
          textDirection: textDirection,
        ),
        filled,
      ],
    );
  }
}

/// Resolves a percent-based corner radius into actual logical
/// pixels for a given background box [size].
///
/// `percent` is clamped to `[0, 1]`. The pill maximum is
/// `min(width, height) / 2` — at `percent == 1` you always get a
/// true pill, regardless of how large the text becomes.
double textBackgroundRadiusPx(Size size, double percent) {
  final p = percent.clamp(0.0, 1.0);
  return (math.min(size.width, size.height) / 2.0) * p;
}

/// Renders a rounded background fill behind [child], where the
/// corner radius is a *percentage* of the box's shorter side rather
/// than a fixed pixel value. This keeps presets like Badge / Chip /
/// CTA visually pill-shaped at every font size — a fixed-px radius
/// would look correct on small text but undersized on large text.
///
/// Sizes itself to [child] (via [CustomPaint]'s default behaviour),
/// then paints the rounded rect at the resolved size.
class TextBackgroundBox extends StatelessWidget {
  const TextBackgroundBox({
    super.key,
    required this.color,
    required this.radiusPercent,
    required this.paddingX,
    required this.paddingY,
    required this.child,
  });

  final Color color;
  final double radiusPercent;
  final double paddingX;
  final double paddingY;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TextBackgroundPainter(
        color: color,
        radiusPercent: radiusPercent,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: paddingX,
          vertical: paddingY,
        ),
        child: child,
      ),
    );
  }
}

class _TextBackgroundPainter extends CustomPainter {
  _TextBackgroundPainter({
    required this.color,
    required this.radiusPercent,
  });

  final Color color;
  final double radiusPercent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = textBackgroundRadiusPx(size, radiusPercent);
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TextBackgroundPainter old) =>
      old.color != color || old.radiusPercent != radiusPercent;
}

/// Process-wide LRU cache of pre-rasterised emoji-sticker glyphs.
///
/// ## Why this exists
///
/// Painting color-emoji glyphs through Flutter's text pipeline (a
/// `Text` widget, a `TextPainter`, etc.) routes draw commands through
/// the engine's *color-glyph atlas*. On Impeller, that atlas can be
/// corrupted mid-frame when:
///
///   * `TextStyle.shadows` is attached to a color-emoji glyph
///     (historical first occurrence of the bug — already worked
///     around in [_TextContent._buildStickerContent]); OR
///   * the same color-emoji glyph is drawn underneath an
///     `ImageFiltered` / `ColorFiltered(BlendMode.srcATop)` saveLayer
///     (the work-around's manual shadow path); OR
///   * the layer's repaint-boundary picture is re-recorded at high
///     frequency (every gesture frame of an active scale).
///
/// The corrupted atlas writes leak into *sibling* sticker layers'
/// cached pictures: those siblings still hit-test correctly (the
/// widget tree is intact, the layer is still in the document) but
/// their glyph draw commands now reference evicted atlas slots and
/// rasterise to nothing — i.e. the sticker disappears visually while
/// remaining selectable. This is the exact symptom users see when
/// scaling one sticker makes the others vanish.
///
/// To make the bug structurally impossible we sidestep the color-
/// glyph atlas entirely at paint time: each unique glyph is rendered
/// exactly once into a `ui.Image` here, and from then on the
/// sticker layer paints that image via [RawImage]. `RawImage` goes
/// through the regular image atlas, never the color-glyph atlas, so
/// scaling, blurring or shadow-compositing one sticker can no longer
/// invalidate another sticker's draw commands.
///
/// ## Cache policy
///
/// * Keyed by every text-shaping input that affects the rasterised
///   pixels (content, font family, weight, letter spacing, line
///   height, text direction). Font *size* is not part of the key —
///   we always rasterise at [_renderFontSize] and let the layer's
///   `BoxFit.contain` scale it on screen.
/// * LRU-bounded at [_maxEntries]; evicted images are disposed.
/// * Single process-wide instance ([instance]) — emoji glyphs are
///   shared across documents, so a single cache amortises the cost
///   across the whole app lifetime.
class _StickerGlyphRasterCache {
  _StickerGlyphRasterCache._();
  static final _StickerGlyphRasterCache instance =
      _StickerGlyphRasterCache._();

  /// Rasterisation font size in logical pixels. Picked high enough
  /// that the resulting bitmap stays crisp when [BoxFit.contain]
  /// upscales it to typical sticker sizes (240–800 px), and low
  /// enough that the per-glyph memory footprint is bounded
  /// (~256\u00B2\u00D74 = 256 KB worst case).
  static const double _renderFontSize = 256;

  /// Maximum cached glyphs. A picked-emoji document rarely uses
  /// more than a handful of distinct glyphs; 64 is comfortable
  /// headroom and caps total cache memory at ~16 MB worst case.
  static const int _maxEntries = 64;

  final LinkedHashMap<String, ui.Image> _entries =
      LinkedHashMap<String, ui.Image>();

  /// Returns the cached raster for the given glyph, rasterising
  /// synchronously on first access. Returns `null` only when
  /// [content] is empty (defensive — sticker layers always have
  /// non-empty content in practice).
  ui.Image? acquire({
    required String content,
    String? fontFamily,
    FontWeight? fontWeight,
    double letterSpacing = 0,
    double lineHeight = 1.2,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    if (content.isEmpty) return null;
    final key = _makeKey(
      content,
      fontFamily,
      fontWeight,
      letterSpacing,
      lineHeight,
      textDirection,
    );
    // Bump on hit so the LRU order is preserved without a separate
    // access-order structure.
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      return hit;
    }
    final image = _rasterise(
      content: content,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      lineHeight: lineHeight,
      textDirection: textDirection,
    );
    if (image == null) return null;
    _entries[key] = image;
    while (_entries.length > _maxEntries) {
      final oldestKey = _entries.keys.first;
      final evicted = _entries.remove(oldestKey);
      evicted?.dispose();
    }
    return image;
  }

  String _makeKey(
    String content,
    String? fontFamily,
    FontWeight? fontWeight,
    double letterSpacing,
    double lineHeight,
    TextDirection textDirection,
  ) {
    return '$content\u0001$fontFamily\u0001${fontWeight?.value}'
        '\u0001$letterSpacing\u0001$lineHeight\u0001${textDirection.index}';
  }

  ui.Image? _rasterise({
    required String content,
    required String? fontFamily,
    required FontWeight? fontWeight,
    required double letterSpacing,
    required double lineHeight,
    required TextDirection textDirection,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: content,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: _renderFontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: lineHeight,
        ),
      ),
      textDirection: textDirection,
      textAlign: TextAlign.center,
    )..layout();
    final w = painter.width.ceil().clamp(1, 4096);
    final h = painter.height.ceil().clamp(1, 4096);
    if (w <= 0 || h <= 0) {
      painter.dispose();
      return null;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    painter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    painter.dispose();
    return image;
  }

  /// Test hook: drop every cached image. Not used in production
  /// code paths.
  @visibleForTesting
  void clear() {
    for (final img in _entries.values) {
      img.dispose();
    }
    _entries.clear();
  }
}
