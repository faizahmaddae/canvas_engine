// Main-toolbar GROUP ORDER follows the project kind, and nothing else.
//
// Eight slots need ~560dp of a 402dp content width, so whichever group
// comes last is behind a scroll whose only affordance is a 24dp fade.
// Leading with the add-content group put Crop and Look past that fold
// for users who arrived through «ویرایش عکس» — the one flow that exists
// to reach them. So a photo project leads with the photo group.
//
// The order keys off `projectKind`, deliberately NOT "does any image
// layer exist". Two reasons, both pinned below:
//   * a design project with one decorative image is still an
//     add-content workflow;
//   * layer contents change with every edit, and chrome layout is not
//     part of the undo model — a toolbar that reshuffles when you undo
//     an image add destroys spatial memory.

import 'package:canvas_engine/app/theme/app_icons.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/presentation/editor_screen.dart';
import 'package:canvas_engine/features/editor/presentation/widgets/dock_tool_tile.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ImageLayer _img(String id) => ImageLayer(
  id: id,
  transform: LayerTransform(position: Offset.zero, size: const Size(400, 300)),
  source: const ImageSource.asset('a.png'),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpEditor(
    WidgetTester tester, {
    required void Function(ProviderContainer c) seed,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    seed(c);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const EditorScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException(); // asset-backed ImageLayer can't decode here
    return c;
  }

  /// Icons of the built dock tiles, in build order. A lazy ListView
  /// only realises tiles near the resting edge, so this is a prefix.
  List<IconData> tileIcons(WidgetTester tester) => tester
      .widgetList<DockToolTile>(find.byType(DockToolTile))
      .map((t) => t.icon)
      .toList();

  testWidgets('a photo project leads with the photo group', (tester) async {
    await pumpEditor(
      tester,
      seed: (c) {
        final ctrl = c.read(documentControllerProvider.notifier);
        ctrl.newDocument(width: 400, height: 300, kind: ProjectKind.photo);
        ctrl.execute(
          CompositeCommand([
            AddLayerCommand(_img('photo')),
            SetBasePhotoCommand('photo'),
          ], labelOverride: 'Import photo'),
        );
        ctrl.clearHistory();
      },
    );

    final icons = tileIcons(tester);
    expect(icons.first, AppIcons.cropTool);
    // Both must be REALISED before comparing positions — `indexOf`
    // returns -1 for a tile the lazy ListView has not built, which
    // would quietly turn this into a comparison of two sentinels.
    expect(icons, contains(AppIcons.lookTool));
    expect(icons, contains(AppIcons.photoTool));
    expect(
      icons.indexOf(AppIcons.lookTool),
      lessThan(icons.indexOf(AppIcons.photoTool)),
      reason: 'the photo verbs must precede the add-content verbs',
    );
  });

  testWidgets('a design project keeps Add first and renders NO photo '
      'group at all (§10.1)', (tester) async {
    await pumpEditor(
      tester,
      seed: (c) {
        c
            .read(documentControllerProvider.notifier)
            .newDocument(width: 1080, height: 1080);
      },
    );

    final icons = tileIcons(tester);
    expect(icons.first, AppIcons.photoTool);
    // Crop and Look are P scope. A design project has no such role,
    // so the tiles are ABSENT — not dimmed, which is the state §10.3
    // reserves for an admissible scope whose target is missing.
    expect(icons, isNot(contains(AppIcons.cropTool)));
    expect(icons, isNot(contains(AppIcons.lookTool)));
    expect(icons, contains(AppIcons.canvasSize));
  });

  testWidgets('a design project with an image still leads with Add, and '
      'still has no photo group', (tester) async {
    // The case that made "any image layer" the wrong key: the user
    // started blank and dropped in one decorative image. Still an
    // add-content workflow — and under §10.1 the image does not
    // conjure a role, so Crop/Look stay absent. Reaching them means
    // selecting the image, which swaps in the image mode strip.
    await pumpEditor(
      tester,
      seed: (c) {
        final ctrl = c.read(documentControllerProvider.notifier);
        ctrl.newDocument(width: 1080, height: 1080);
        ctrl.execute(AddLayerCommand(_img('decor')));
        ctrl.clearHistory();
      },
    );

    final icons = tileIcons(tester);
    expect(icons.first, AppIcons.photoTool);
    expect(icons, isNot(contains(AppIcons.cropTool)));
  });

  testWidgets('adding then undoing an image never moves a tile', (
    tester,
  ) async {
    final c = await pumpEditor(
      tester,
      seed: (x) {
        x
            .read(documentControllerProvider.notifier)
            .newDocument(width: 1080, height: 1080);
      },
    );
    final before = tileIcons(tester);

    c
        .read(documentControllerProvider.notifier)
        .execute(AddLayerCommand(_img('decor')));
    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException();
    expect(
      tileIcons(tester),
      before,
      reason: 'an edit must not reorder chrome',
    );

    c.read(documentControllerProvider.notifier).undo();
    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException();
    expect(tileIcons(tester), before, reason: 'undo must not reorder chrome');
  });
}
