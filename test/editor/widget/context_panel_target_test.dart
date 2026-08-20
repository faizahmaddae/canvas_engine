// Audit P2-4: base photo + one layer selected → the opacity panel
// mounted the MULTI control over both and silently faded the photo,
// while the dock showed single-layer chrome for the other layer.
//
// The rule under test (editor_screen `_layersForContextPanel`,
// contract §10): the opacity panel targets exactly the ACTIONABLE
// selection — the same set the mode derivation counts — and falls
// back to the protected base photo only when it is the selection's
// sole member, the one state whose chrome (the Image dock with the
// «عکس پایه» badge) names the base as its target. The set the slider
// writes must equal the set the visible chrome claims; never a
// silent extra member.

import 'package:canvas_engine/features/editor/application/context_toolbar_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/selection_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_layer.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/context_tool_panel.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/layer_opacity_control.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  TextLayer text(String id) => TextLayer(
    id: id,
    transform: const LayerTransform(
      position: Offset(40, 40),
      size: Size(180, 80),
    ),
    content: 'Hello',
    style: const TextStyleSpec(fontSize: 24),
  );

  ShapeLayer shape(String id, Offset position) => ShapeLayer(
    id: id,
    transform: LayerTransform(position: position, size: const Size(80, 80)),
    kind: ShapeKind.rectangle,
  );

  /// A photo project seeded the way import does: locked base photo +
  /// `SetBasePhotoCommand` in one composite, history cleared.
  ProviderContainer photoProject({
    List<EditorLayer> extraLayers = const <EditorLayer>[],
  }) {
    final container = ProviderContainer();
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 400, height: 300, kind: ProjectKind.photo);
    ctrl.execute(
      CompositeCommand([
        AddLayerCommand(
          ImageLayer(
            id: 'photo',
            transform: const LayerTransform(
              position: Offset.zero,
              size: Size(400, 300),
            ),
            source: const ImageSource.asset('a.png'),
            locked: true,
          ),
        ),
        SetBasePhotoCommand('photo'),
      ], labelOverride: 'Import photo'),
    );
    for (final layer in extraLayers) {
      ctrl.execute(AddLayerCommand(layer));
    }
    ctrl.clearHistory();
    return container;
  }

  Future<void> pumpEditor(WidgetTester tester, ProviderContainer c) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const EditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // The test asset behind the base photo does not exist; the load
    // failure is expected and rendered via the layer's errorBuilder
    // (same discharge as editor_screen_actions_test's photo case).
    tester.takeException();
  }

  Future<void> openOpacityPanel(
    WidgetTester tester,
    ProviderContainer c,
  ) async {
    c
        .read(contextToolbarControllerProvider.notifier)
        .open(ContextToolPanel.opacity);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Drives the panel's slider through a full gesture (preview +
  /// commit), the same way `context_tool_panel_test.dart` does.
  Future<void> dragPanelSliderTo(WidgetTester tester, double value) async {
    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byType(ContextToolPanelBody),
        matching: find.byType(Slider),
      ),
    );
    slider.onChanged!(value);
    slider.onChangeEnd!(value);
    await tester.pump();
  }

  testWidgets(
    'base+text selected: opacity panel is the single-layer control over the '
    'text layer and never writes the base photo',
    (tester) async {
      final c = photoProject(extraLayers: [text('t1')]);
      addTearDown(c.dispose);
      // The audit's exact selection path: tap the photo (selects the
      // base), then long-press the text layer (enters multi mode and
      // ADDS, keeping the base and making the text layer primary).
      c.read(selectionControllerProvider.notifier).select('photo');
      c.read(selectionModeProvider.notifier).enterMulti();
      c.read(selectionControllerProvider.notifier).add('t1');

      await pumpEditor(tester, c);
      await openOpacityPanel(tester, c);

      // The dock derives SINGLE-layer chrome for this state (one
      // actionable layer), so the panel must be the single control —
      // targeting the layer the chrome claims, not the base too.
      expect(find.byType(MultiLayerOpacityControl), findsNothing);
      final control = tester.widget<LayerOpacityControl>(
        find.byType(LayerOpacityControl),
      );
      expect(control.layer.id, 't1');

      await dragPanelSliderTo(tester, 0.3);

      final doc = c.read(documentControllerProvider);
      expect(doc.layerById('t1')!.opacity, closeTo(0.3, 1e-6));
      expect(
        doc.layerById('photo')!.opacity,
        closeTo(1.0, 1e-6),
        reason:
            'the base photo was never named by the chrome and must '
            'not be a silent extra member of the slider write (P2-4)',
      );
    },
  );

  testWidgets(
    'base alone selected: opacity panel deliberately targets the base photo',
    (tester) async {
      final c = photoProject();
      addTearDown(c.dispose);
      c.read(selectionControllerProvider.notifier).select('photo');

      await pumpEditor(tester, c);
      await openOpacityPanel(tester, c);

      // DELIBERATE behaviour, pinned: with the base selected alone the
      // Image dock (with the base-photo badge) is the chrome, so the
      // base IS the named target — fading the photo toward the canvas
      // background is meaningful, reversible and non-destructive. This
      // is the tb15 fix (c2860db) for the Image dock's Opacity tile
      // rendering no panel at all; dropping the base here would
      // resurrect that dead-end.
      expect(find.byType(MultiLayerOpacityControl), findsNothing);
      final control = tester.widget<LayerOpacityControl>(
        find.byType(LayerOpacityControl),
      );
      expect(control.layer.id, 'photo');

      await dragPanelSliderTo(tester, 0.5);

      final doc = c.read(documentControllerProvider);
      expect(doc.layerById('photo')!.opacity, closeTo(0.5, 1e-6));
    },
  );

  testWidgets('base+two shapes selected: multi opacity control writes only the '
      'actionable members, base photo unchanged', (tester) async {
    final c = photoProject(
      extraLayers: [
        shape('a', const Offset(20, 20)),
        shape('b', const Offset(140, 20)),
      ],
    );
    addTearDown(c.dispose);
    c.read(selectionControllerProvider.notifier).select('photo');
    c.read(selectionModeProvider.notifier).enterMulti();
    c.read(selectionControllerProvider.notifier).add('a');
    c.read(selectionControllerProvider.notifier).add('b');

    await pumpEditor(tester, c);
    await openOpacityPanel(tester, c);

    // Two actionable members → multi chrome (chip counts 2, mode is
    // multi) → the multi control, over exactly those two.
    expect(find.byType(LayerOpacityControl), findsNothing);
    final control = tester.widget<MultiLayerOpacityControl>(
      find.byType(MultiLayerOpacityControl),
    );
    expect(
      control.layers.map((l) => l.id),
      unorderedEquals(['a', 'b']),
      reason: 'the multi control must carry the actionable set only',
    );

    await dragPanelSliderTo(tester, 0.4);

    final doc = c.read(documentControllerProvider);
    expect(doc.layerById('a')!.opacity, closeTo(0.4, 1e-6));
    expect(doc.layerById('b')!.opacity, closeTo(0.4, 1e-6));
    expect(doc.layerById('photo')!.opacity, closeTo(1.0, 1e-6));
  });
}
