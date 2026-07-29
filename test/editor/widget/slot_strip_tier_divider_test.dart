/// Widget-level coverage for [SlotStrip] tier-divider rendering.
///
/// Slots carry a [SlotTier]; the strip must insert a hairline
/// divider whenever consecutive slots belong to different tiers.
/// Single-tier strips render no dividers at all.
library;

import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/image/presentation/image_mode_toolbar.dart';
import 'package:canvas_engine/features/editor/toolbar/domain/toolbar_slot.dart';
import 'package:canvas_engine/features/editor/toolbar/presentation/slot_strip.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ToolbarSlot _slot(String id, IconData icon, SlotTier tier) =>
    ToolbarSlot(id: id, icon: icon, label: id, tier: tier, onTap: () {});

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 800, height: 80, child: child)),
);

/// Finder for the divider's 1-dp wide × 30-dp tall hairline (the
/// chrome-separation pass widened the divider so it reads as an
/// intentional group boundary). The divider widget itself is private
/// so we identify it via its visible `Container` geometry — stable
/// enough for a regression check without coupling to the internal
/// class name.
Finder _hairlineFinder() => find.byWidgetPredicate((w) {
  if (w is! Container) return false;
  final c = w.constraints;
  if (c == null) return false;
  return c.maxWidth == 1 && c.maxHeight == 30;
});

void main() {
  group('SlotStrip tier dividers', () {
    testWidgets('no divider when every slot is in the same tier', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SlotStrip(
            slots: [
              _slot('a', Icons.looks_one_rounded, SlotTier.tier1),
              _slot('b', Icons.looks_two_rounded, SlotTier.tier1),
              _slot('c', Icons.looks_3_rounded, SlotTier.tier1),
            ],
          ),
        ),
      );
      expect(_hairlineFinder(), findsNothing);
    });

    testWidgets('single divider between tier1 and tier2', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SlotStrip(
            slots: [
              _slot('a', Icons.looks_one_rounded, SlotTier.tier1),
              _slot('b', Icons.looks_two_rounded, SlotTier.tier1),
              _slot('c', Icons.looks_3_rounded, SlotTier.tier2),
            ],
          ),
        ),
      );
      expect(_hairlineFinder(), findsOneWidget);
    });

    testWidgets('two dividers across three tiers (tier1→tier2→tier3)', (
      tester,
    ) async {
      // This mirrors the main editor toolbar layout (Add ·
      // Photo edits · Document) and is the regression check for
      // the editor strip's grouped grammar.
      await tester.pumpWidget(
        _wrap(
          SlotStrip(
            slots: [
              _slot('a', Icons.looks_one_rounded, SlotTier.tier1),
              _slot('b', Icons.looks_two_rounded, SlotTier.tier1),
              _slot('c', Icons.looks_3_rounded, SlotTier.tier2),
              _slot('d', Icons.looks_4_rounded, SlotTier.tier2),
              _slot('e', Icons.looks_5_rounded, SlotTier.tier3),
            ],
          ),
        ),
      );
      expect(_hairlineFinder(), findsNWidgets(2));
    });

    testWidgets('divider position respects slot order, not tier value', (
      tester,
    ) async {
      // tier3 → tier1 transition still inserts a divider (renderer
      // is data-driven, not order-of-tier based).
      await tester.pumpWidget(
        _wrap(
          SlotStrip(
            slots: [
              _slot('a', Icons.looks_one_rounded, SlotTier.tier3),
              _slot('b', Icons.looks_two_rounded, SlotTier.tier1),
            ],
          ),
        ),
      );
      expect(_hairlineFinder(), findsOneWidget);
    });
  });

  // The synthetic cases above prove the RENDERER is data-driven. They
  // could not catch a wrong tier ANNOTATION, and one shipped: Crop
  // kept `tier: SlotTier.tier2` from when it sat seventh in the image
  // strip, so after it moved to second the strip drew a hairline on
  // both sides of it — three group boundaries where the grammar has
  // one, before the trailing shape/effects/selective group.
  group('the real image strip has exactly one group boundary', () {
    testWidgets('ImageModeToolbar renders one hairline', (tester) async {
      tester.view.physicalSize = const Size(1400, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                height: 100,
                child: ImageModeToolbar(
                  layer: ImageLayer(
                    id: 'img',
                    transform: const LayerTransform(
                      position: Offset.zero,
                      size: Size(400, 300),
                    ),
                    source: const ImageSource.asset('a.png'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        _hairlineFinder(),
        findsOneWidget,
        reason: 'tier is group membership, not decoration',
      );
    });
  });
}
