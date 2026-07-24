// tb4 6/14: preset rows that name a SIZE resolve against the open
// document, not against the 1080 canvas they were tuned on. At the
// reference size every number is unchanged — these pins exist to
// prove that, and that a bigger canvas actually moves them.

import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/text/text_layer.dart';
import 'package:canvas_engine/features/editor/sticker/presentation/sticker_size_body.dart';
import 'package:canvas_engine/features/editor/ui/canvas_preset_scale.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the reference canvas leaves presets exactly as authored', () {
    final doc = EditorDocument(layers: const [], width: 1080, height: 1080);
    expect(canvasScaledPreset(120, doc), 120);
    expect(canvasScaledPreset(18, doc), 18);
  });

  test('a bigger canvas scales presets up by its shorter side', () {
    final doc = EditorDocument(layers: const [], width: 2160, height: 3000);
    expect(canvasScaledPreset(120, doc), 240);
    expect(
      canvasScaledPreset(18, doc),
      36,
      reason: 'the shorter side drives it — a tall canvas is not wider',
    );
  });

  test('a smaller canvas scales presets down', () {
    final doc = EditorDocument(layers: const [], width: 540, height: 540);
    expect(canvasScaledPreset(120, doc), 60);
  });

  testWidgets('the sticker size row commits scaled sides', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(documentControllerProvider.notifier);
    ctrl.newDocument(width: 2160, height: 2160);
    const sticker = TextLayer(
      id: 'st',
      transform: LayerTransform(
        position: Offset(100, 100),
        size: Size(400, 400),
      ),
      content: '🌟',
      style: TextStyleSpec(),
      kind: TextLayerKind.emojiSticker,
    );
    ctrl.execute(const AddLayerCommand(sticker));

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: StickerSizeBody(layer: sticker)),
          ),
        ),
      ),
    );

    // "S" is 120 on the reference canvas; this document is twice it.
    await tester.tap(find.text('S'));
    await tester.pump();
    final resized =
        container.read(documentControllerProvider).layerById('st') as TextLayer;
    expect(resized.transform.size.width, 240);
    expect(
      resized.transform.position + const Offset(120, 120),
      const Offset(300, 300),
      reason: 'resize still happens around the visual centre',
    );
  });
}
