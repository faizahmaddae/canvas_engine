import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layer_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a thumbnail in a minimal [MaterialApp] so [Theme.of] resolves
/// and the box decoration can read `colorScheme`/`dividerColor`.
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );

const _t = LayerTransform(
  position: Offset.zero,
  size: Size(100, 100),
);

void main() {
  group('LayerThumbnail – ShapeLayer', () {
    for (final kind in ShapeKind.values) {
      testWidgets('renders ${kind.name} without throwing',
          (tester) async {
        final layer = ShapeLayer(
          id: 's-${kind.name}',
          transform: _t,
          kind: kind,
          fillColor: const Color(0xFFFF0000),
          strokeColor: const Color(0xFF000000),
          strokeWidth: 2,
          cornerRadius: 8,
        );
        await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
        expect(tester.takeException(), isNull);
        expect(find.byType(LayerThumbnail), findsOneWidget);
        // Shapes paint via CustomPaint, not Image/Text/Icon.
        expect(find.byType(CustomPaint), findsWidgets);
      });
    }

    testWidgets('honours fillOpacity without crashing', (tester) async {
      final layer = ShapeLayer(
        id: 's',
        transform: _t,
        kind: ShapeKind.circle,
        fillColor: const Color(0xFF00FF00),
        fillOpacity: 0.4,
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('respects custom thumbnail size', (tester) async {
      final layer = ShapeLayer(
        id: 's',
        transform: _t,
        kind: ShapeKind.rectangle,
      );
      await tester.pumpWidget(
        _host(LayerThumbnail(layer: layer, size: 64)),
      );
      final box = tester.getSize(find.byType(LayerThumbnail));
      expect(box.width, 64);
      expect(box.height, 64);
    });
  });

  group('LayerThumbnail – ImageLayer', () {
    testWidgets('builds for asset source without throwing',
        (tester) async {
      final layer = ImageLayer(
        id: 'img-asset',
        transform: _t,
        source: const ImageSource.asset('assets/missing.png'),
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      // Asset failure is caught by errorBuilder; widget tree must
      // remain stable.
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('builds for network source without throwing',
        (tester) async {
      final layer = ImageLayer(
        id: 'img-net',
        transform: _t,
        source: const ImageSource.network('https://example.com/x.png'),
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('honours non-default crop without throwing',
        (tester) async {
      final layer = ImageLayer(
        id: 'img-crop',
        transform: _t,
        source: const ImageSource.asset('assets/missing.png'),
        cropRect: const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('honours non-default mask via ClipPath',
        (tester) async {
      final layer = ImageLayer(
        id: 'img-mask',
        transform: _t,
        source: const ImageSource.asset('assets/missing.png'),
        mask: ImageMask.circle,
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      expect(tester.takeException(), isNull);
      // Custom mask is applied as ClipPath in addition to the
      // default ClipRRect frame.
      expect(find.byType(ClipPath), findsOneWidget);
    });
  });

  group('LayerThumbnail – TextLayer', () {
    testWidgets('renders short text verbatim', (tester) async {
      final layer = TextLayer(
        id: 't-short',
        transform: _t,
        content: 'Hello',
        style: const TextStyleSpec(),
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('truncates long text with ellipsis', (tester) async {
      final layer = TextLayer(
        id: 't-long',
        transform: _t,
        content: 'This is a very long text content that should be cut',
        style: const TextStyleSpec(),
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      expect(tester.takeException(), isNull);
      // First 14 chars + ellipsis sentinel.
      expect(find.textContaining('…'), findsOneWidget);
      // Original full string must NOT appear verbatim.
      expect(
        find.text('This is a very long text content that should be cut'),
        findsNothing,
      );
    });

    testWidgets('falls back to icon for empty content', (tester) async {
      final layer = TextLayer(
        id: 't-empty',
        transform: _t,
        content: '   ',
        style: const TextStyleSpec(),
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      expect(find.byIcon(Icons.text_fields), findsOneWidget);
    });

    testWidgets('emoji sticker renders glyph at large size',
        (tester) async {
      final layer = TextLayer(
        id: 't-sticker',
        transform: _t,
        content: '🎉',
        style: const TextStyleSpec(),
        kind: TextLayerKind.emojiSticker,
      );
      await tester.pumpWidget(
        _host(LayerThumbnail(layer: layer, size: 40)),
      );
      expect(find.text('🎉'), findsOneWidget);
      // Sticker glyph uses ~70% of the thumb (40 * 0.7 = 28).
      final txt = tester.widget<Text>(find.text('🎉'));
      expect(txt.style?.fontSize, closeTo(28, 0.001));
    });

    testWidgets('normal text uses layer colour and family',
        (tester) async {
      final layer = TextLayer(
        id: 't-style',
        transform: _t,
        content: 'Hi',
        style: const TextStyleSpec(
          fontFamily: 'Vazir',
          color: Color(0xFFAA00BB),
        ),
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      final txt = tester.widget<Text>(find.text('Hi'));
      expect(txt.style?.fontFamily, 'Vazir');
      expect(txt.style?.color, const Color(0xFFAA00BB));
    });
  });

  group('LayerThumbnail – frame', () {
    testWidgets('default size is 40x40', (tester) async {
      final layer = ShapeLayer(
        id: 's',
        transform: _t,
        kind: ShapeKind.rectangle,
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      final box = tester.getSize(find.byType(LayerThumbnail));
      expect(box.width, 40);
      expect(box.height, 40);
    });

    testWidgets('always wraps content in a rounded clip',
        (tester) async {
      final layer = ShapeLayer(
        id: 's',
        transform: _t,
        kind: ShapeKind.rectangle,
      );
      await tester.pumpWidget(_host(LayerThumbnail(layer: layer)));
      expect(find.byType(ClipRRect), findsWidgets);
    });
  });
}
