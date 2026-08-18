// The paint dock is a consumer of the contract §2 preview channel, not
// of the commit. While a selected stroke is being restyled, the strip's
// value labels and swatch, the Size hero + precision thumb, and the
// Polygon/Fill visuals must show the STAGED value — the same layer the
// canvas is drawing. Only the document stays frozen until release.
//
// `paintStyleViewProvider` used to read `documentControllerProvider`
// alone, so every one of those consumers sat at the pre-gesture value
// for the whole drag. The widget cases below mount a REACTIVE host
// (`Consumer` → `ref.watch(paintStyleViewProvider)`) the way
// `PaintModeInlineExpansion` does: a test that reads the view once and
// hands a snapshot down cannot observe this class of staleness at all,
// because the snapshot never changes.

import 'package:canvas_engine/app/theme/app_icons.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/live_overlay_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/canvas_sizing.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/paint/paint_layer.dart';
import 'package:canvas_engine/features/editor/paint/application/paint_tool_controller.dart';
import 'package:canvas_engine/features/editor/paint/presentation/bodies/paint_size_entry.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/paint/presentation/paint_size_body.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PaintLayer strokeLayer(PaintKind kind) => PaintLayer(
    id: 'p1',
    transform: const LayerTransform(
      position: Offset(40, 40),
      size: Size(200, 100),
    ),
    kind: kind,
    normalizedPoints: const [Offset(0, 0.5), Offset(1, 0.5)],
    strokeColor: const Color(0xFF00AA55),
    strokeWidth: 6,
    blurSigma: 24,
  );

  ProviderContainer harness({
    bool selected = true,
    PaintKind kind = PaintKind.line,
  }) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final documents = c.read(documentControllerProvider.notifier);
    documents.newDocument(width: 800, height: 800);
    documents.execute(AddLayerCommand(strokeLayer(kind)));
    if (selected) c.read(selectionControllerProvider.notifier).select('p1');
    return c;
  }

  PaintStyleView view(ProviderContainer c) => c.read(paintStyleViewProvider);

  PaintToolController writer(ProviderContainer c) =>
      c.read(paintToolControllerProvider.notifier);

  PaintLayer committed(ProviderContainer c) =>
      c.read(documentControllerProvider).layerById('p1') as PaintLayer;

  PaintLayer staged(ProviderContainer c) =>
      c.read(liveOverlayProvider).replacements['p1'] as PaintLayer;

  int version(ProviderContainer c) => c.read(documentCommitVersionProvider);

  group('the style view reflects the staged layer, not the committed one', () {
    test('stroke width', () {
      final c = harness();
      final before = version(c);

      writer(c).previewStrokeWidth(31);

      expect(view(c).strokeWidth, 31);
      expect(committed(c).strokeWidth, 6);
      expect(version(c), before);
    });

    test('stroke colour', () {
      final c = harness();
      final before = version(c);

      writer(c).previewStrokeColor(const Color(0xFF123456));

      expect(view(c).strokeColor, const Color(0xFF123456));
      expect(committed(c).strokeColor, const Color(0xFF00AA55));
      expect(version(c), before);
    });

    test('stroke opacity', () {
      final c = harness();
      final before = version(c);

      writer(c).previewStrokeOpacity(40);

      expect(view(c).strokeColor.a, closeTo(0.4, 0.001));
      expect(committed(c).strokeColor.a, 1);
      expect(version(c), before);
    });

    test('fill colour', () {
      final c = harness(kind: PaintKind.rectangle);
      final before = version(c);

      writer(c).previewFillColor(const Color(0xFF654321));

      expect(view(c).fillColor, const Color(0xFF654321));
      expect(committed(c).fillColor, isNull);
      expect(version(c), before);
    });

    test('blur radius, converted back to reference pixels', () {
      final c = harness(kind: PaintKind.blur);
      final before = version(c);

      writer(c).previewBlurRadius(30);

      expect(view(c).blurRadius, closeTo(30, 0.0001));
      expect(committed(c).blurSigma, 24);
      expect(version(c), before);
    });

    test('the reference factor still comes from the canvas', () {
      final c = harness(kind: PaintKind.blur);
      final doc = c.read(documentControllerProvider);
      final factor = CanvasSizing.scaleFactor(doc);

      expect(view(c).blurRadius, closeTo(24 / factor, 0.0001));
    });

    test('a preview on ANOTHER layer leaves the view alone', () {
      final c = harness();
      c
          .read(documentControllerProvider.notifier)
          .execute(
            AddLayerCommand(
              PaintLayer(
                id: 'p2',
                transform: const LayerTransform(
                  position: Offset(300, 40),
                  size: Size(200, 100),
                ),
                kind: PaintKind.line,
                normalizedPoints: const [Offset.zero, Offset(1, 1)],
                strokeWidth: 40,
              ),
            ),
          );
      final other =
          c.read(documentControllerProvider).layerById('p2') as PaintLayer;

      c
          .read(liveOverlayProvider.notifier)
          .replaceLayer(other.copyWith(strokeWidth: 77));

      expect(view(c).strokeWidth, 6);
    });

    test('release commits once, clears the overlay and keeps the value', () {
      final c = harness();
      final before = version(c);

      writer(c).previewStrokeWidth(31);
      writer(c).commitStrokeWidth(31);

      expect(version(c), before + 1);
      expect(c.read(liveOverlayProvider).isEmpty, isTrue);
      expect(committed(c).strokeWidth, 31);
      expect(view(c).strokeWidth, 31);
      // §10 command scope: a bound restyle never re-aims at the author
      // scope's next-stroke defaults.
      expect(c.read(paintToolControllerProvider).strokeWidth, 6);
    });
  });

  // ── the widgets, through the host they actually run under ─────────

  Future<void> pumpReactiveSizeBody(
    WidgetTester tester,
    ProviderContainer c,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) =>
                  PaintSizeEntryBody(view: ref.watch(paintStyleViewProvider)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double thumb(WidgetTester tester) =>
      tester.widget<Slider>(find.byType(Slider)).value;

  double hero(WidgetTester tester) =>
      tester.widget<StrokeHero>(find.byType(StrokeHero)).width;

  testWidgets('selected stroke: hero, thumb and readout move mid-drag', (
    tester,
  ) async {
    final c = harness();
    await pumpReactiveSizeBody(tester, c);
    expect(thumb(tester), 6);
    expect(hero(tester), 6);

    final before = version(c);
    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();

    final width = staged(c).strokeWidth;
    expect(width, greaterThan(6));
    expect(
      thumb(tester),
      width,
      reason: 'the thumb is controlled by the style view; it must follow it',
    );
    expect(hero(tester), width);
    expect(find.text('${width.round()}px'), findsOneWidget);
    expect(committed(c).strokeWidth, 6, reason: 'committed frozen mid-drag');
    expect(version(c), before);

    await gesture.up();
    await tester.pump();

    expect(version(c), before + 1);
    expect(c.read(liveOverlayProvider).isEmpty, isTrue);
    expect(committed(c).strokeWidth, width);
    expect(thumb(tester), width);
    expect(hero(tester), width);
    expect(
      c.read(paintToolControllerProvider).strokeWidth,
      6,
      reason: 'restyling a selected layer must not arm the next stroke',
    );
  });

  testWidgets('author mode: the same widgets track the session defaults '
      'with zero document commands', (tester) async {
    final c = harness(selected: false);
    await pumpReactiveSizeBody(tester, c);

    final before = version(c);
    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();

    final width = c.read(paintToolControllerProvider).strokeWidth;
    expect(width, greaterThan(6));
    expect(thumb(tester), width);
    expect(hero(tester), width);
    expect(c.read(liveOverlayProvider).isEmpty, isTrue);

    await gesture.up();
    await tester.pump();

    expect(
      version(c),
      before,
      reason: 'an author-scope preview writes no command at all',
    );
    expect(committed(c).strokeWidth, 6);
  });

  testWidgets('the strip value label moves during the gesture', (tester) async {
    final c = harness();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(width: 800, height: 140, child: PaintModeToolbar()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(AppIcons.strokeWeight), findsOneWidget);
    expect(find.text('6px'), findsOneWidget);

    final before = version(c);
    writer(c).previewStrokeWidth(24);
    await tester.pump();

    expect(find.text('24px'), findsOneWidget);
    expect(version(c), before);

    writer(c).commitStrokeWidth(24);
    await tester.pump();

    expect(find.text('24px'), findsOneWidget);
    expect(version(c), before + 1);
  });
}
