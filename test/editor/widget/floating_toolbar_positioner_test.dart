import 'package:canvas_engine/features/editor/engine/core/viewport_state.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/floating_toolbar_positioner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [FloatingToolbarPositioner.resolve] — the centralised
/// math behind every floating toolbar (text / paint / quick actions).
///
/// All tests are pure: identity viewport, rectangular screen, no
/// rotation unless the test specifically targets the rotated path.
void main() {
  // ─── Fixtures ───────────────────────────────────────────────────────────
  const screen = Size(400, 800);
  const safe = EdgeInsets.fromLTRB(0, 44, 0, 34); // status bar + home bar
  const dock = 80.0;
  const barW = 240.0;
  const barH = 40.0;
  const gap = 12.0;

  FloatingToolbarAnchor resolveCentered({
    Offset position = const Offset(100, 350), // around vertical centre
    Size size = const Size(200, 100),
    double rotation = 0,
    ViewportState viewport = ViewportState.identity,
    Size screenSize = screen,
    EdgeInsets padding = safe,
    double bottomReserved = dock,
    double topReserved = 0,
    bool forceHidden = false,
  }) {
    final center = position + Offset(size.width / 2, size.height / 2);
    return FloatingToolbarPositioner.resolve(
      layerPosition: position,
      layerSize: size,
      layerCenter: center,
      layerRotation: rotation,
      viewport: viewport,
      screenSize: screenSize,
      safePadding: padding,
      barWidth: barW,
      barHeight: barH,
      gap: gap,
      bottomReserved: bottomReserved,
      topReserved: topReserved,
      forceHidden: forceHidden,
    );
  }

  // ─── Vertical placement ─────────────────────────────────────────────────
  group('Vertical placement', () {
    test('layer in middle of screen → toolbar above', () {
      final a = resolveCentered();
      expect(a.placement, FloatingToolbarPlacement.above);
      // Toolbar bottom edge sits gap pixels above the layer top.
      expect(a.top, 350 - gap - barH);
    });

    test('layer near top edge → toolbar below', () {
      // Layer at y=10 leaves only 10 - 44(safe) - 8 - gap - barH < 0.
      final a = resolveCentered(position: const Offset(100, 10));
      expect(a.placement, FloatingToolbarPlacement.below);
      // Toolbar top sits gap pixels below the layer bottom.
      expect(a.top, 10 + 100 + gap);
    });

    test('layer near bottom → toolbar above', () {
      // Layer flush against bottom safe area: above must be picked.
      final a = resolveCentered(position: const Offset(100, 600));
      expect(a.placement, FloatingToolbarPlacement.above);
      expect(a.top, 600 - gap - barH);
    });

    test('layer fills the screen → hidden (no safe slot)', () {
      // Layer covers the whole vertical safe band.
      final a = resolveCentered(
        position: const Offset(0, 0),
        size: const Size(400, 800),
      );
      expect(a.placement, FloatingToolbarPlacement.hidden);
      expect(a.isHidden, isTrue);
    });
  });

  // ─── Horizontal clamping ────────────────────────────────────────────────
  group('Horizontal clamping', () {
    test('layer near left edge → bar clamped to horizontalMargin', () {
      // Centre would land left of the screen, so bar gets pushed right.
      final a = resolveCentered(position: const Offset(0, 350));
      expect(a.left, 12); // horizontalMargin default
    });

    test('layer near right edge → bar clamped right', () {
      // Centre would land right of the screen, so bar gets pushed left.
      final a = resolveCentered(position: const Offset(380, 350));
      // maxLeft = 400 - 240 - 12 = 148
      expect(a.left, 148);
    });

    test('layer centred horizontally → bar centred over layer', () {
      // Layer at x=100, w=200 → centreX = 200; bar (w=240) left = 200-120 = 80
      final a = resolveCentered();
      expect(a.left, 80);
    });

    test('safePadding.left/right respected in horizontal clamp', () {
      // Wide left inset (e.g. landscape notch).
      const padding = EdgeInsets.fromLTRB(40, 44, 40, 34);
      final a = resolveCentered(
        position: const Offset(0, 350),
        padding: padding,
      );
      expect(a.left, 12 + 40); // horizontalMargin + safePadding.left
    });
  });

  // ─── Reserved zones (panel / app bar) ───────────────────────────────────
  group('Reserved zones', () {
    test('large bottomReserved (panel open) forces above placement', () {
      // bottomReserved 400 leaves only 800 - 44 - 400 - 8 = 348 px usable.
      // Layer at 200..300 → above (200 - gap - 40) = 148, fits topSafe=52.
      final a = resolveCentered(
        position: const Offset(100, 200),
        bottomReserved: 400,
      );
      expect(a.placement, FloatingToolbarPlacement.above);
    });

    test('giant bottomReserved + layer near top → hidden', () {
      // No room above (layer at top) and below is reserved away.
      final a = resolveCentered(
        position: const Offset(100, 10),
        size: const Size(200, 200),
        bottomReserved: 600,
      );
      expect(a.placement, FloatingToolbarPlacement.hidden);
    });

    test('topReserved (app bar) added to top safe band', () {
      // Layer at y=80 — above would need topAbove = 80 - gap - 40 = 28.
      // Default topReserved=0 → topSafe=44+8=52 → fits=false → below.
      final aDefault = resolveCentered(position: const Offset(100, 80));
      expect(aDefault.placement, FloatingToolbarPlacement.below);
      // With topReserved=200 → topSafe=44+200+8=252 → still below.
      final aHigh = resolveCentered(
        position: const Offset(100, 80),
        topReserved: 200,
      );
      expect(aHigh.placement, FloatingToolbarPlacement.below);
    });
  });

  // ─── forceHidden / crop mode ────────────────────────────────────────────
  group('forceHidden', () {
    test('forceHidden short-circuits to hidden anchor', () {
      final a = resolveCentered(forceHidden: true);
      expect(a.placement, FloatingToolbarPlacement.hidden);
      expect(a.isHidden, isTrue);
    });
  });

  // ─── Viewport transform ────────────────────────────────────────────────
  group('Viewport transform', () {
    test('zoom > 1 enlarges screen-space bounds', () {
      // Small layer so a 2x zoom keeps it within the safe band: (50,150)
      // size 80x80 → screen (100,300)..(260,460). Above fits.
      final a = FloatingToolbarPositioner.resolve(
        layerPosition: const Offset(50, 150),
        layerSize: const Size(80, 80),
        layerCenter: const Offset(90, 190),
        layerRotation: 0,
        viewport: const ViewportState(scale: 2, translation: Offset.zero),
        screenSize: screen,
        safePadding: safe,
        barWidth: barW,
        barHeight: barH,
        gap: gap,
        bottomReserved: dock,
      );
      expect(a.placement, FloatingToolbarPlacement.above);
      expect(a.top, 300 - gap - barH);
    });

    test('translation shifts the bar with the layer', () {
      final a = resolveCentered(
        viewport: const ViewportState(scale: 1, translation: Offset(50, 0)),
      );
      // Layer screen left = 100 + 50 = 150, centre = 250, bar left = 130.
      expect(a.left, 130);
    });
  });

  // ─── Rotated layer ─────────────────────────────────────────────────────
  group('Rotation', () {
    test('rotated 90° layer is treated as its rotated bounding rect', () {
      // 200x100 rotated 90° around centre becomes 100x200 footprint.
      final a = resolveCentered(rotation: 1.5707963267948966); // π/2
      expect(a.placement, FloatingToolbarPlacement.above);
      // After rotation around its centre (200, 400), the rotated rect's
      // top edge is around y = 300 (centre.y - half rotated height/100).
      // We don't need exact pixels here — just that 'above' was chosen
      // and the top is < the original top (before rotation effect).
      expect(a.top, lessThan(350));
    });
  });

  // ─── Bar always inside viewport ────────────────────────────────────────
  group('Bar stays inside viewport', () {
    test('bar never starts off the left edge', () {
      for (final x in [-200.0, 0.0, 50.0, 350.0, 800.0]) {
        final a = resolveCentered(position: Offset(x, 350));
        if (!a.isHidden) {
          expect(a.left, greaterThanOrEqualTo(0));
        }
      }
    });

    test('bar never extends past the right edge', () {
      for (final x in [-200.0, 0.0, 50.0, 350.0, 800.0]) {
        final a = resolveCentered(position: Offset(x, 350));
        if (!a.isHidden) {
          expect(a.left + barW, lessThanOrEqualTo(screen.width));
        }
      }
    });

    test('bar never overlaps bottom reserved zone', () {
      for (final y in [10.0, 100.0, 300.0, 500.0, 700.0]) {
        final a = resolveCentered(position: Offset(100, y));
        if (!a.isHidden) {
          // bottom of bar
          expect(
            a.top + barH,
            lessThanOrEqualTo(screen.height - safe.bottom - dock),
          );
        }
      }
    });

    test('bar never overlaps top safe area', () {
      for (final y in [10.0, 100.0, 300.0, 500.0, 700.0]) {
        final a = resolveCentered(position: Offset(100, y));
        if (!a.isHidden) {
          expect(a.top, greaterThanOrEqualTo(safe.top));
        }
      }
    });
  });

  // ─── dockHeight helper ─────────────────────────────────────────────────
  group('dockHeight', () {
    test('compact phone (small + portrait) → 64', () {
      final h = FloatingToolbarPositioner.dockHeight(
        screen: const Size(360, 760),
        orientation: Orientation.portrait,
      );
      expect(h, 64);
    });

    test('regular phone (large + portrait) → 80', () {
      final h = FloatingToolbarPositioner.dockHeight(
        screen: const Size(412, 915),
        orientation: Orientation.portrait,
      );
      expect(h, 80);
    });

    test('any landscape → compact 64', () {
      final h = FloatingToolbarPositioner.dockHeight(
        screen: const Size(900, 412),
        orientation: Orientation.landscape,
      );
      expect(h, 64);
    });
  });
}
