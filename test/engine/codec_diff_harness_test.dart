// One harness for the codec fixed-point property (roadmap 5.4).
//
// `DocumentCodec` must be a fixed point of its own round trip:
//
//     encode(decode(encode(doc))) == encode(doc)
//
// i.e. whatever the writer emits, the reader must give back something
// the writer emits identically. Anything else means a field is lost,
// gained, reordered, or reformatted on save — the class of bug that
// silently eats a user's gradient / crop / mask the second time they
// open a project.
//
// The existing corpus gates (`test/engine/fixtures/**`) assert byte
// identity against COMMITTED files: they catch "the wire format
// changed" but only for the handful of shapes those five-plus-four
// files happen to contain. This harness is the complement — it holds
// no bytes on disk, and instead drives the property over a table of
// in-memory documents chosen to hit every layer type and every
// optional field, plus a wire-key coverage gate that fails when a
// newly-serialised field has no document exercising it.
//
// Failures report a key-path diff, e.g.
//
//     layers[2].transform.fx: missing vs true
//
// never "strings differ" — a byte compare on a 40 KB JSON is useless
// for triage.
//
// Pure engine test: no Material, no providers.
import 'dart:convert';
import 'dart:io';

import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_mask.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/effects/editor_effect.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/document_diff.dart';

// ---------------------------------------------------------------------------
// The harness
// ---------------------------------------------------------------------------

/// Prove `encode(decode(encode(doc))) == encode(doc)`, reporting a
/// key-path diff on failure. Returns the encoding so callers can feed
/// it to the coverage gate.
String expectCodecFixedPoint(
  EditorDocument doc, {
  required String label,
  bool expectValueEqualDecode = true,
}) {
  final encoded = DocumentCodec.encode(doc);
  final decoded = DocumentCodec.decode(encoded);
  final reEncoded = DocumentCodec.encode(decoded);
  expect(
    reEncoded,
    encoded,
    reason:
        '$label is not a fixed point of encode/decode.\n'
        '${describeEncodedDiff(encoded, reEncoded)}',
  );
  // A second lap. A codec that is stable on the first round trip but
  // not the second (e.g. a field that flips between two equivalent
  // encodings) would otherwise slip through.
  expect(
    DocumentCodec.encode(DocumentCodec.decode(reEncoded)),
    encoded,
    reason:
        '$label drifts on the SECOND round trip.\n'
        '${describeEncodedDiff(encoded, DocumentCodec.encode(DocumentCodec.decode(reEncoded)))}',
  );
  // The decoded document must also be value-equal to the original, or
  // the encoding is hiding a lossy field behind an omit-when-default
  // rule.
  if (expectValueEqualDecode) {
    expect(
      decoded,
      doc,
      reason:
          '$label: encodings match but the decoded document is not equal '
          'to the original — a field survives the wire but not the model',
    );
  }
  return encoded;
}

/// Every key that appears anywhere in [encoded], as a flat set. Used
/// by the coverage gate; nesting is irrelevant there because the
/// question is only "did any document in the corpus emit this key?".
Set<String> _keysIn(String encoded) {
  final out = <String>{};
  void walk(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        out.add('${entry.key}');
        walk(entry.value);
      }
    } else if (node is List) {
      for (final item in node) {
        walk(item);
      }
    }
  }

  walk(jsonDecode(encoded));
  return out;
}

/// Every wire key the serialization sources can emit, scraped off
/// disk so a newly-serialised field cannot ship without a document in
/// this corpus exercising it.
///
/// The scrape looks for map-literal keys (`'foo':`). `fromJson` reads
/// use the `json['foo']` subscript form and so are not matched, which
/// is what keeps this specific enough to be useful.
Set<String> declaredWireKeys() {
  const sources = <String>[
    'lib/features/editor/engine/core/editor_layer.dart',
    'lib/features/editor/engine/core/layer_transform.dart',
    'lib/features/editor/engine/core/background_fill.dart',
    'lib/features/editor/engine/core/layer_mask.dart',
    'lib/features/editor/engine/effects/editor_effect.dart',
    'lib/features/editor/engine/effects/color_adjustment_effects.dart',
    'lib/features/editor/engine/effects/vignette_effect.dart',
    'lib/features/editor/engine/modules/text/text_layer.dart',
    'lib/features/editor/engine/modules/text/text_style_spec.dart',
    'lib/features/editor/engine/modules/shape/shape_layer.dart',
    'lib/features/editor/engine/modules/image/image_layer.dart',
    'lib/features/editor/engine/modules/image/image_source.dart',
    'lib/features/editor/engine/modules/paint/paint_layer.dart',
    'lib/features/editor/engine/serialization/document_codec.dart',
  ];
  final pattern = RegExp(r"'([A-Za-z][A-Za-z0-9]*)':");
  final keys = <String>{};
  for (final path in sources) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'codec source missing: $path');
    for (final match in pattern.allMatches(file.readAsStringSync())) {
      keys.add(match.group(1)!);
    }
  }
  // Keys written through a named constant rather than a literal, so
  // the scrape cannot see them: `LayerMask._shapeKey` and
  // `BackgroundFill._typeKey` ('type', already covered by the layer
  // discriminator).
  keys.add('shape');
  // Not wire keys: `DocumentCodec._layerFactories` is a Dart map whose
  // keys are the layer TYPE VALUES, not JSON field names. They are
  // covered instead by the layer-type gate below.
  keys.removeAll(const <String>{'text', 'shape', 'image', 'paint'});
  // `shape` is a real mask key (re-added above after the removal that
  // targets the factory entry of the same spelling).
  keys.add('shape');
  return keys;
}

// ---------------------------------------------------------------------------
// The corpus
// ---------------------------------------------------------------------------

const _t = LayerTransform(position: Offset(40, 60), size: Size(420, 160));

EditorDocument _emptyDefaults() => EditorDocument(layers: const []);

EditorDocument _solidBackground() => EditorDocument(
  layers: const [],
  background: const SolidBackground(color: Color(0xFF112233)),
);

EditorDocument _linearGradientWithStops() => EditorDocument(
  layers: const [],
  background: const LinearGradientBackground(
    startColor: Color(0xFFFF0080),
    endColor: Color(0xFF7928CA),
    angleDegrees: 42.5,
    stops: <double>[0.15, 0.85],
  ),
);

EditorDocument _radialGradient() => EditorDocument(
  layers: const [],
  background: const RadialGradientBackground(
    centerColor: Color(0xFFFFF3D6),
    edgeColor: Color(0xFF2A1B0B),
    focalPoint: Alignment(-0.3, 0.6),
    radius: 1.4,
  ),
);

/// Document-level optional fields: transparent mode, photo kind, and
/// a live base-photo pointer (which the decoder drops unless the id
/// resolves, so this also covers that branch).
EditorDocument _documentFlags() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-base',
      transform: _t,
      source: const ImageSource.asset('assets/sample.jpg'),
    ),
  ],
  width: 2048,
  height: 1152,
  backgroundMode: CanvasBackgroundMode.transparent,
  basePhotoLayerId: 'img-base',
  projectKind: ProjectKind.photo,
);

EditorDocument _textMinimal() => EditorDocument(
  layers: const [
    TextLayer(
      id: 'txt-min',
      transform: _t,
      content: 'hello',
      style: TextStyleSpec(),
    ),
  ],
);

/// Every optional key `TextLayer` + `TextStyleSpec` can emit: the
/// three conditional style blocks (shadow / outline / background),
/// the sticker kind, a forced direction, and every base-layer flag.
EditorDocument _textEveryField() => EditorDocument(
  layers: const [
    TextLayer(
      id: 'txt-full',
      transform: LayerTransform(
        position: Offset(12.5, 33.25),
        size: Size(400.75, 120.5),
        rotation: 0.7853981633974483,
        flipH: true,
        flipV: true,
      ),
      content: 'نوروزتان پیروز\nline two',
      style: TextStyleSpec(
        fontFamily: 'Vazir_Regular',
        fontSize: 72.5,
        color: Color(0xFF1F1B16),
        fontWeight: FontWeight.w300,
        italic: true,
        underline: true,
        letterSpacing: 1.25,
        lineHeight: 1.45,
        alignment: TextAlign.justify,
        shadowColor: Color(0x66000000),
        shadowBlur: 8.5,
        shadowOffset: Offset(2.5, 3.5),
        outlineColor: Color(0xFFFFFFFF),
        outlineWidth: 3.5,
        backgroundColor: Color(0x22FF0000),
        // 0..1 percent — see the migration note on
        // `TextStyleSpec.backgroundRadius`. Values > 1 are read as
        // legacy pixels and rescaled, which is a deliberate one-way
        // lift asserted separately below.
        backgroundRadius: 0.55,
        backgroundPaddingX: 10.5,
        backgroundPaddingY: 6.5,
      ),
      resizeMode: TextResizeMode.resizeBox,
      kind: TextLayerKind.emojiSticker,
      textDirectionMode: TextDirectionMode.rtl,
      name: 'عنوان',
      visible: false,
      locked: true,
      opacity: 0.42,
    ),
  ],
);

EditorDocument _shapeMinimal() => EditorDocument(
  layers: const [
    ShapeLayer(id: 'shp-min', transform: _t, kind: ShapeKind.rectangle),
  ],
);

EditorDocument _shapeEveryField() => EditorDocument(
  layers: const [
    ShapeLayer(
      id: 'shp-full',
      transform: _t,
      kind: ShapeKind.speechBubble,
      fillColor: Color(0xFFC0872A),
      fill: LinearGradientBackground(
        startColor: Color(0xFFF5B942),
        endColor: Color(0xFFE2703A),
        angleDegrees: 315,
      ),
      fillOpacity: 0.35,
      strokeColor: Color(0xFF1F1B16),
      strokeWidth: 4.5,
      cornerRadius: 24.5,
      shadowColor: Color(0xFF102030),
      shadowBlur: 18.5,
      shadowOffset: Offset(-3.5, 8.5),
      shadowOpacity: 0.45,
      resizeMode: ShapeResizeMode.scale,
      name: 'band',
      visible: false,
      locked: true,
      opacity: 0.6,
    ),
  ],
);

/// The `{'type': 'solid', 'color': …}` branch of `ShapeLayer._encodeFill`
/// — an explicitly-chosen solid descriptor, distinct from the legacy
/// bare `fillColor`.
EditorDocument _shapeExplicitSolidFill() => EditorDocument(
  layers: const [
    ShapeLayer(
      id: 'shp-solid-fill',
      transform: _t,
      kind: ShapeKind.oval,
      fill: SolidBackground(color: Color(0xFF3355FF)),
    ),
  ],
);

/// The radial branch of the shape fill descriptor, which delegates to
/// `RadialGradientBackground.toJson` (focalX / focalY / radius).
EditorDocument _shapeRadialFill() => EditorDocument(
  layers: const [
    ShapeLayer(
      id: 'shp-radial-fill',
      transform: _t,
      kind: ShapeKind.star,
      fill: RadialGradientBackground(
        centerColor: Color(0xFFFFFFFF),
        edgeColor: Color(0xFF000000),
        focalPoint: Alignment(0.25, -0.75),
        radius: 0.8,
      ),
    ),
  ],
);

EditorDocument _imageMinimal() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-min',
      transform: _t,
      source: const ImageSource.asset('assets/sample.jpg'),
    ),
  ],
);

EditorDocument _imageEveryField() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-full',
      transform: _t,
      source: const ImageSource.file('/var/mobile/Documents/photo.heic'),
      fit: BoxFit.fitWidth,
      mask: ImageMask.squircle,
      borderColor: const Color(0xFFFFFFFF),
      borderWidth: 6.5,
      shadowColor: const Color(0xFF000000),
      shadowBlur: 16.5,
      shadowOffset: const Offset(0.5, 6.5),
      shadowOpacity: 0.4,
      cropRect: const Rect.fromLTRB(0.1, 0.15, 0.85, 0.95),
      filterPreset: ImageFilterPreset.dramatic,
      name: 'hero',
      visible: false,
      locked: true,
      opacity: 0.85,
    ),
  ],
);

/// The third `ImageSource` variant. Asset and file are covered above;
/// without this the `url` key never appears in the corpus.
EditorDocument _imageNetworkSource() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-net',
      transform: _t,
      source: const ImageSource.network('https://example.test/a.png'),
      mask: ImageMask.heart,
      fit: BoxFit.scaleDown,
    ),
  ],
);

EditorDocument _paintMinimal() => EditorDocument(
  layers: [
    PaintLayer(
      id: 'pnt-min',
      transform: _t,
      kind: PaintKind.freestyle,
      normalizedPoints: const [
        Offset(0, 0.5),
        Offset(0.25, 0),
        Offset(0.5, 0.75),
        Offset(1, 0.5),
      ],
    ),
  ],
);

/// Polygon: the only kind that persists `sides`, plus the optional
/// `fillColor` and the non-default resize mode.
EditorDocument _paintPolygon() => EditorDocument(
  layers: [
    PaintLayer(
      id: 'pnt-poly',
      transform: _t,
      kind: PaintKind.polygon,
      normalizedPoints: const [Offset.zero, Offset(1, 1)],
      strokeColor: const Color(0xFFC0872A),
      strokeWidth: 14.5,
      fillColor: const Color(0x33FF3B30),
      sides: 7,
      resizeMode: PaintResizeMode.scale,
      name: 'stroke',
      opacity: 0.5,
    ),
  ],
);

/// Blur: the only kind that persists `blurSigma`.
EditorDocument _paintBlur() => EditorDocument(
  layers: [
    PaintLayer(
      id: 'pnt-blur',
      transform: _t,
      kind: PaintKind.blur,
      normalizedPoints: const [Offset.zero, Offset(1, 1)],
      blurSigma: 21.5,
    ),
  ],
);

/// Every concrete `EditorEffect` in one stack, including the
/// custom-paint one (vignette) with a non-default colour and feather.
EditorDocument _everyEffectType() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-effects',
      transform: _t,
      source: const ImageSource.asset('assets/sample.jpg'),
      effects: EffectStack(
        List<EditorEffect>.unmodifiable(const <EditorEffect>[
          BrightnessEffect(amount: 18.5),
          ContrastEffect(amount: 1.15),
          SaturationEffect(amount: 0.75),
          ExposureEffect(amount: -0.3),
          WarmthEffect(amount: 0.6),
          VignetteEffect(
            intensity: 0.65,
            feather: 0.35,
            color: Color(0xFF102030),
          ),
        ]),
      ),
    ),
  ],
);

/// The `enabled: false` key plus all three per-effect mask shapes.
EditorDocument _effectMasks() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-effect-masks',
      transform: _t,
      source: const ImageSource.asset('assets/sample.jpg'),
      effects: EffectStack(
        List<EditorEffect>.unmodifiable(const <EditorEffect>[
          BrightnessEffect(
            amount: 12,
            enabled: false,
            mask: RectMask(
              rect: Rect.fromLTWH(0, 0, 960, 360),
              feather: 32,
              inverted: true,
            ),
          ),
          ContrastEffect(
            amount: 1.2,
            mask: EllipseMask(
              bounds: Rect.fromLTWH(20, 20, 900, 640),
              feather: 12,
            ),
          ),
          SaturationEffect(amount: 1.4, mask: _pathMask),
        ]),
      ),
    ),
  ],
);

/// Path mask exercising all three segment kinds, the even-odd fill
/// rule, `inverted`, and a non-default feather.
const _pathMask = PathMask(
  contours: <PathContour>[
    PathContour(
      start: Offset(0, 0),
      segments: <PathSegment>[
        LineSegment(end: Offset(100, 0)),
        QuadSegment(control: Offset(150, 50), end: Offset(100, 100)),
        CubicSegment(
          control1: Offset(60, 120),
          control2: Offset(20, 120),
          end: Offset(0, 0),
        ),
      ],
    ),
    PathContour(
      start: Offset(200, 200),
      segments: <PathSegment>[
        LineSegment(end: Offset(260, 200)),
        LineSegment(end: Offset(230, 260)),
      ],
    ),
  ],
  fillType: PathFillType.evenOdd,
  inverted: true,
  feather: 6.5,
);

/// A stack mask with no effects — the shape whose version stamping
/// regressed once (v3 fixture 02) and whose `stackMask`-without-
/// `effects` wire form only this document produces.
EditorDocument _stackMaskOnly() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-stackmask',
      transform: _t,
      source: const ImageSource.asset('assets/sample.jpg'),
      effects: const EffectStack(<EditorEffect>[], stackMask: _pathMask),
    ),
  ],
);

/// Effects on NON-image layers. `EffectStack` lives on every layer
/// even though only `ImageLayer` renders it, so the codec has to
/// carry it for text / shape / paint too.
EditorDocument _effectsOnEveryLayerType() => EditorDocument(
  layers: [
    const TextLayer(
      id: 'txt-fx',
      transform: _t,
      content: 'fx',
      style: TextStyleSpec(),
      effects: EffectStack(<EditorEffect>[ContrastEffect(amount: 1.1)]),
    ),
    const ShapeLayer(
      id: 'shp-fx',
      transform: _t,
      kind: ShapeKind.diamond,
      effects: EffectStack(
        <EditorEffect>[],
        stackMask: EllipseMask(bounds: Rect.fromLTWH(0, 0, 10, 10)),
      ),
    ),
    PaintLayer(
      id: 'pnt-fx',
      transform: _t,
      kind: PaintKind.arrow,
      normalizedPoints: const [Offset.zero, Offset(1, 1)],
      effects: const EffectStack(<EditorEffect>[WarmthEffect(amount: 0.2)]),
    ),
  ],
);

/// Flip flags (`fx` / `fy`) on their own — omit-default fields that
/// no other document in this corpus except the text one sets, and the
/// most recently added transform keys.
EditorDocument _flippedTransforms() => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img-flip-h',
      transform: const LayerTransform(
        position: Offset(40, 40),
        size: Size(480, 640),
        rotation: 0.35,
        flipH: true,
      ),
      source: const ImageSource.asset('assets/sample.jpg'),
    ),
    const ShapeLayer(
      id: 'shp-flip-v',
      transform: LayerTransform(
        position: Offset(0, 0),
        size: Size(100, 100),
        flipV: true,
      ),
      kind: ShapeKind.arrowUp,
    ),
  ],
);

/// One document with everything at once — the composition case. A
/// codec can be a fixed point on each shape in isolation and still
/// drop a field when they combine (e.g. two layers sharing a key
/// name, or a gradient background alongside a gradient fill).
EditorDocument _kitchenSink() => EditorDocument(
  layers: [
    ..._textEveryField().layers,
    ..._shapeEveryField().layers,
    ..._imageEveryField().layers,
    ..._paintPolygon().layers,
    ..._everyEffectType().layers,
    ..._effectMasks().layers,
    ..._stackMaskOnly().layers,
  ],
  width: 1080,
  height: 1350,
  background: const LinearGradientBackground(
    startColor: Color(0xFFF5B942),
    endColor: Color(0xFFE2703A),
    angleDegrees: 90,
    stops: <double>[0.1, 0.9],
  ),
  backgroundMode: CanvasBackgroundMode.transparent,
  basePhotoLayerId: 'img-full',
  projectKind: ProjectKind.photo,
);

final Map<String, EditorDocument Function()>
corpus = <String, EditorDocument Function()>{
  'empty document at every default': _emptyDefaults,
  'solid background': _solidBackground,
  'linear gradient background with explicit stops': _linearGradientWithStops,
  'radial gradient background': _radialGradient,
  'document flags (size, transparent, photo kind, base photo)': _documentFlags,
  'text layer at defaults': _textMinimal,
  'text layer with every optional field': _textEveryField,
  'shape layer at defaults': _shapeMinimal,
  'shape layer with every optional field': _shapeEveryField,
  'shape layer with an explicit solid fill descriptor': _shapeExplicitSolidFill,
  'shape layer with a radial fill descriptor': _shapeRadialFill,
  'image layer at defaults': _imageMinimal,
  'image layer with every optional field': _imageEveryField,
  'image layer with a network source': _imageNetworkSource,
  'paint layer at defaults (freestyle)': _paintMinimal,
  'paint layer polygon (sides + fill + scale resize)': _paintPolygon,
  'paint layer blur (blurSigma)': _paintBlur,
  'every effect type on one stack': _everyEffectType,
  'per-effect masks of all three shapes + a disabled entry': _effectMasks,
  'stack mask with an empty effect list': _stackMaskOnly,
  'effects on text / shape / paint layers': _effectsOnEveryLayerType,
  'flipped transforms': _flippedTransforms,
  'kitchen sink': _kitchenSink,
};

/// Documents that can only be *read* into existence. `UnknownEffect`
/// has a private constructor by design (it is the forward-compat
/// carrier for effect types a future build writes), so the only way
/// to hold one is to decode it.
const Map<String, String> rawSeeded = <String, String>{
  'unknown effect forward-compat carrier': '''
{
  "version": 3,
  "width": 1080.0,
  "height": 1080.0,
  "layers": [
    {
      "type": "image",
      "id": "img-1",
      "transform": {"x": 0.0, "y": 0.0, "w": 100.0, "h": 100.0, "r": 0.0},
      "source": {"asset": "assets/sample.jpg"},
      "fit": "cover",
      "mask": "original",
      "effects": [
        {"type": "brightness", "amount": 10.0},
        {"type": "duotone", "shadowColor": 255, "highlightColor": 16777215},
        {"type": "contrast", "amount": 1.1}
      ]
    }
  ]
}
''',
};

void main() {
  group('codec fixed point', () {
    for (final entry in corpus.entries) {
      test(entry.key, () {
        expectCodecFixedPoint(entry.value(), label: entry.key);
      });
    }

    for (final entry in rawSeeded.entries) {
      test('${entry.key} (seeded from raw JSON)', () {
        final seeded = DocumentCodec.decode(entry.value);
        // `UnknownEffect` carries a raw JSON map, so it used to fall
        // back to identity equality: a document holding a
        // forward-compat effect was never equal to a re-decoded copy
        // of itself, and every command's no-op guard churned. The
        // wire contract always held; the model-level one does now too
        // (tb5 8/9), so this is a plain fixed-point assertion.
        expectCodecFixedPoint(seeded, label: entry.key);
        expect(
          DocumentCodec.decode(entry.value),
          seeded,
          reason: 'an unreadable effect must still compare by value',
        );
      });
    }

    test('the frozen v2 legacy fixture is a fixed point once lifted', () {
      // The legacy `adjustments: {...}` shape can no longer be written,
      // so this file is NOT byte-stable — but the *lifted* document
      // must be. This is the "open an old project, save it, open it
      // again" path.
      const path =
          'test/engine/fixtures/v2/05_image_with_crop_and_adjustments.json';
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'fixture missing: $path');
      expectCodecFixedPoint(
        DocumentCodec.decode(file.readAsStringSync()),
        label: path,
      );
    });
  });

  group('deliberate one-way lifts (NOT fixed points, by design)', () {
    // Read-side migrations convert a legacy value into the current
    // domain, so `encode(decode(x)) != x` for the legacy input on
    // purpose. Asserted explicitly here rather than left as a hole in
    // the corpus, and asserted to converge after ONE lift — a
    // migration that kept re-scaling on every save would silently
    // shrink the user's value with each open.
    test(
      'backgroundRadius lifts legacy pixels into the 0..1 percent space',
      () {
        const legacyPx = 20.0;
        final legacy = EditorDocument(
          layers: const [
            TextLayer(
              id: 'txt-legacy-radius',
              transform: _t,
              content: 'chip',
              style: TextStyleSpec(
                backgroundColor: Color(0x22FF0000),
                backgroundRadius: legacyPx,
              ),
            ),
          ],
        );
        final lifted = DocumentCodec.decode(DocumentCodec.encode(legacy));
        final style = (lifted.layers.single as TextLayer).style;
        expect(style.backgroundRadius, closeTo(legacyPx / 40.0, 1e-9));
        // Idempotent from here on: the lifted document IS a fixed point.
        expectCodecFixedPoint(
          lifted,
          label: 'lifted backgroundRadius document',
        );
      },
    );
  });

  group('corpus coverage', () {
    late Set<String> emitted;
    late Set<String> typeValues;

    setUpAll(() {
      emitted = <String>{};
      typeValues = <String>{};
      void absorb(String encoded) {
        emitted.addAll(_keysIn(encoded));
        // Discriminator VALUES (layer `type`, effect `type`, mask
        // `shape`, background/fill `type`) are not keys, so collect
        // them separately.
        void walk(Object? node) {
          if (node is Map) {
            for (final entry in node.entries) {
              final key = '${entry.key}';
              final value = entry.value;
              if ((key == 'type' || key == 'shape') && value is String) {
                typeValues.add(value);
              }
              walk(value);
            }
          } else if (node is List) {
            for (final item in node) {
              walk(item);
            }
          }
        }

        walk(jsonDecode(encoded));
      }

      for (final build in corpus.values) {
        absorb(DocumentCodec.encode(build()));
      }
      for (final raw in rawSeeded.values) {
        absorb(DocumentCodec.encode(DocumentCodec.decode(raw)));
      }
    });

    test('the wire-key scrape still finds keys', () {
      // The gate below is only as strong as the scrape. If a source
      // moves or the regex stops matching, `declaredWireKeys()` would
      // quietly shrink toward empty and the coverage test would pass
      // vacuously. Floor it.
      expect(declaredWireKeys().length, greaterThanOrEqualTo(55));
    });

    test('every declared wire key is exercised by some document', () {
      final missing = declaredWireKeys().difference(emitted).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'these serialised keys are never emitted by the codec-diff '
            'corpus — add a document that sets them rather than deleting '
            'this gate',
      );
    });

    test('every registered layer type is exercised', () {
      // Mirrors DocumentCodec._layerFactories. Kept as a literal
      // because the registry is private; the fixed-point tests above
      // would all still pass if a type silently stopped round-tripping,
      // so this is the gate that notices a type is uncovered.
      for (final type in const <String>['text', 'shape', 'image', 'paint']) {
        expect(
          typeValues,
          contains(type),
          reason: 'no document in the corpus contains a "$type" layer',
        );
      }
    });

    test('every effect type is exercised', () {
      for (final type in const <String>[
        'brightness',
        'contrast',
        'saturation',
        'exposure',
        'warmth',
        'vignette',
        // The forward-compat carrier, via the raw-seeded document.
        'duotone',
      ]) {
        expect(
          typeValues,
          contains(type),
          reason: 'no document in the corpus contains a "$type" effect',
        );
      }
    });

    test('every mask shape and every fill variant is exercised', () {
      for (final shape in const <String>['rect', 'ellipse', 'path']) {
        expect(
          typeValues,
          contains(shape),
          reason: 'no document in the corpus contains a "$shape" mask',
        );
      }
      for (final fill in const <String>['solid', 'linear', 'radial']) {
        expect(
          typeValues,
          contains(fill),
          reason: 'no document in the corpus contains a "$fill" fill',
        );
      }
    });

    test('every schema version the writer can stamp is produced', () {
      final versions = <int>{};
      for (final build in corpus.values) {
        final json =
            jsonDecode(DocumentCodec.encode(build())) as Map<String, dynamic>;
        versions.add(json['version'] as int);
      }
      for (
        var v = DocumentCodec.minSupportedSchemaVersion;
        v <= DocumentCodec.schemaVersion;
        v++
      ) {
        expect(
          versions,
          contains(v),
          reason: 'no document in the corpus stamps schema v$v',
        );
      }
    });
  });

  group('the diff itself is readable', () {
    test('reports a key path, not "strings differ"', () {
      // Guards the harness's own value: if `describeEncodedDiff` ever
      // degrades to an opaque message, every future codec failure
      // becomes untriageable.
      final a = DocumentCodec.encode(_imageMinimal());
      final b = DocumentCodec.encode(_flippedTransforms());
      final diff = describeEncodedDiff(a, b);
      expect(diff, contains('layers[0].'));
      expect(diff, contains(' vs '));
    });

    test('names the exact field when one flip flag differs', () {
      final withFlip = EditorDocument(
        layers: [
          ImageLayer(
            id: 'img-min',
            transform: const LayerTransform(
              position: Offset(40, 60),
              size: Size(420, 160),
              flipH: true,
            ),
            source: const ImageSource.asset('assets/sample.jpg'),
          ),
        ],
      );
      final diff = describeEncodedDiff(
        DocumentCodec.encode(_imageMinimal()),
        DocumentCodec.encode(withFlip),
      );
      expect(diff, contains('layers[0].transform.fx: missing vs true'));
    });

    test('is empty for identical documents', () {
      expect(describeDocumentDiff(_kitchenSink(), _kitchenSink()), isEmpty);
    });
  });
}
