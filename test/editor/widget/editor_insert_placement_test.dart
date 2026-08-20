// Insert-while-zoomed placement contract (ux-audit P2-12).
//
// Historically every insert flow dropped the new layer at the
// DOCUMENT centre, and every insertion test ran at the default
// fitted viewport — where the document centre happens to be exactly
// what the user is looking at, so the defect was invisible. Zoomed
// into a corner, an insert landed off-screen: the layer was added
// and selected but the canvas looked unchanged, inviting duplicate
// taps.
//
// The rule under test: a new layer is centred on the CENTRE OF THE
// VISIBLE VIEWPORT (canvas space), clamped so it lands fully inside
// the document whenever it fits — no camera movement, the layer
// appears where the user is looking. Shape, sticker and the text
// composer all share `ViewportController.insertPositionFor`; the
// pure clamp cases are pinned in test/application/viewport_test.dart,
// this file pins the end-to-end flows through the real dock UI.
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/viewport_controller.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const docWidth = 400.0;
  const docHeight = 300.0;
  const docCentre = Offset(docWidth / 2, docHeight / 2);

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: docWidth, height: docHeight);
    return container;
  }

  Future<void> pumpEditor(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Reproduce the audit framing: zoom in, then pan so the visible
  /// viewport centres on [target] (canvas space) and the document
  /// centre is off-screen. Returns the visible rect the insert should
  /// aim at. Drives the controller through its programmatic gesture
  /// seams (panBy/zoomBy) — the sanctioned test path per the
  /// controller's own docs.
  Rect frameViewportAt(ProviderContainer container, Offset target) {
    final vp = container.read(viewportControllerProvider.notifier);
    expect(
      vp.visibleCanvasRect,
      isNotNull,
      reason: 'EditorCanvas must have fitted the viewport on first layout',
    );
    vp.zoomBy(3.0, Offset.zero);
    final scale = container.read(viewportControllerProvider).scale;
    vp.panBy((vp.visibleCanvasRect!.center - target) * scale);
    final visible = vp.visibleCanvasRect!;
    expect(
      visible.contains(docCentre),
      isFalse,
      reason:
          'the framing must push the document centre off-screen, or the '
          'test cannot distinguish the new rule from the old one',
    );
    return visible;
  }

  /// The three-part placement promise: the layer is centred on the
  /// point the user was looking at, which is therefore visible, and
  /// the layer sits fully inside the document.
  void expectPlacedAt(Rect layerRect, Rect visible) {
    expect(
      layerRect.center.dx,
      moreOrLessEquals(visible.center.dx, epsilon: 0.001),
    );
    expect(
      layerRect.center.dy,
      moreOrLessEquals(visible.center.dy, epsilon: 0.001),
    );
    expect(visible.contains(layerRect.center), isTrue);
    expect(layerRect.left, greaterThanOrEqualTo(0));
    expect(layerRect.top, greaterThanOrEqualTo(0));
    expect(layerRect.right, lessThanOrEqualTo(docWidth));
    expect(layerRect.bottom, lessThanOrEqualTo(docHeight));
  }

  Rect rectOf(ProviderContainer container, bool Function(Object) match) {
    final layer = container
        .read(documentControllerProvider)
        .layers
        .singleWhere(match);
    return layer.transform.position & layer.transform.size;
  }

  testWidgets('shape inserted while zoomed into a corner lands at the '
      'visible-viewport centre, inside the document', (tester) async {
    final container = makeContainer();
    await pumpEditor(tester, container);
    final visible = frameViewportAt(container, const Offset(300, 220));

    await tester.tap(find.text('Shape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rectangle'));
    await tester.pumpAndSettle();

    expectPlacedAt(rectOf(container, (l) => l is ShapeLayer), visible);
  });

  testWidgets('sticker inserted while zoomed into a corner lands at the '
      'visible-viewport centre, inside the document', (tester) async {
    final container = makeContainer();
    await pumpEditor(tester, container);
    final visible = frameViewportAt(container, const Offset(300, 220));

    await tester.tap(find.text('Sticker'));
    await tester.pumpAndSettle();
    // Fresh mock prefs → no recents → the picker opens on Smileys.
    await tester.tap(find.text('😀', findRichText: true).first);
    await tester.pumpAndSettle();

    expectPlacedAt(
      rectOf(container, (l) => l is TextLayer && l.isSticker),
      visible,
    );
  });

  testWidgets('text committed through the composer while zoomed into a '
      'corner lands at the visible-viewport centre, inside the document', (
    tester,
  ) async {
    final container = makeContainer();
    await pumpEditor(tester, container);
    final visible = frameViewportAt(container, const Offset(300, 220));

    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('add-text-input')), 'Hi');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-text-confirm')));
    await tester.pumpAndSettle();

    expectPlacedAt(
      rectOf(container, (l) => l is TextLayer && !l.isSticker),
      visible,
    );
  });

  testWidgets('pasteboard framing: a visible centre outside the document '
      'clamps the insert to the nearest fully-inside placement', (
    tester,
  ) async {
    final container = makeContainer();
    await pumpEditor(tester, container);
    // Aim the viewport past the document's bottom-right corner: the
    // visible centre sits on the pasteboard, so the shape must snap
    // to the nearest in-document position instead of landing outside.
    // (The pan clamp keeps a 48-px sliver of canvas on-screen, so the
    // exact centre lands wherever the clamp allows — the test only
    // relies on it being beyond the document's corner.)
    final visible = frameViewportAt(container, const Offset(500, 400));
    expect(visible.center.dx, greaterThan(docWidth));
    expect(visible.center.dy, greaterThan(docHeight));

    await tester.tap(find.text('Shape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rectangle'));
    await tester.pumpAndSettle();

    final rect = rectOf(container, (l) => l is ShapeLayer);
    // Snapped flush into the corner nearest the framing.
    expect(rect.right, moreOrLessEquals(docWidth, epsilon: 0.001));
    expect(rect.bottom, moreOrLessEquals(docHeight, epsilon: 0.001));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('at the default fitted viewport an insert keeps the '
      'historical document-centre geometry', (tester) async {
    final container = makeContainer();
    await pumpEditor(tester, container);
    // No zoom/pan: the fitted pane centre IS the document centre.
    final vp = container.read(viewportControllerProvider.notifier);
    expect(
      vp.visibleCanvasRect!.center.dx,
      moreOrLessEquals(200, epsilon: 0.001),
    );
    expect(
      vp.visibleCanvasRect!.center.dy,
      moreOrLessEquals(150, epsilon: 0.001),
    );

    await tester.tap(find.text('Shape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rectangle'));
    await tester.pumpAndSettle();

    final rect = rectOf(container, (l) => l is ShapeLayer);
    expect(rect.center.dx, moreOrLessEquals(docCentre.dx, epsilon: 0.001));
    expect(rect.center.dy, moreOrLessEquals(docCentre.dy, epsilon: 0.001));
  });
}
