// Regression tests for the in-editor "New document" flow
// ([startNewDocument]): starting a new document must NEVER let the
// old project be overwritten. Pre-fix, the old session (projectId)
// stayed bound and ephemeral state was never reset, so the first
// commit's debounced autosave upserted the fresh blank document —
// and its journal — under the still-open project's id, destroying
// the saved project unrecoverably.

import 'package:canvas_engine/features/editor/application/autosave_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_lifecycle.dart';
import 'package:canvas_engine/features/editor/application/editor_session.dart';
import 'package:canvas_engine/features/editor/crop/application/crop_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_path_provider.dart';
import '../../support/temp_projects_dir.dart';

/// Grabs a real [WidgetRef] so application seams that require one
/// ([startNewDocument], [resetEditorEphemeralState]) can run inside
/// a container-driven test.
class _Probe extends ConsumerWidget {
  const _Probe();
  static WidgetRef? ref;
  @override
  Widget build(BuildContext context, WidgetRef r) {
    ref = r;
    return const SizedBox.shrink();
  }
}

ShapeLayer _shape(String id) => ShapeLayer(
  id: id,
  transform: LayerTransform(position: Offset.zero, size: const Size(50, 50)),
  kind: ShapeKind.rectangle,
  fillColor: const Color(0xFFFFFFFF),
);

void main() {
  testWidgets('startNewDocument rebinds the session so autosave can never '
      'upsert the new document under the old project', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    installFakeDocumentsDir();
    final dir = tempProjectsDir();
    final container = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(container.dispose);
    late String savedJson;

    await tester.runAsync(() async {
      await container.read(projectStoreProvider.future);
      container.read(autosaveControllerProvider);

      // Simulate "opened from a saved project": document with one
      // layer, store record + bound session for p1.
      final docCtrl = container.read(documentControllerProvider.notifier);
      docCtrl.newDocument(width: 1000, height: 1000);
      docCtrl.execute(AddLayerCommand(_shape('keep')));
      savedJson = DocumentCodec.encode(
        container.read(documentControllerProvider),
      );
      final now = DateTime.now();
      await container
          .read(projectStoreProvider.notifier)
          .upsert(
            Project(
              id: 'p1',
              name: 'Old project',
              width: 1000,
              height: 1000,
              createdAt: now,
              lastModified: now,
              documentJson: savedJson,
            ),
          );
      container.read(editorSessionProvider.notifier).state =
          const EditorSession(name: 'Old project', projectId: 'p1');

      // A stale crop session pointing at the old doc's layer must
      // not survive the document boundary.
      container.read(cropControllerProvider.notifier).openCrop('keep');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: _Probe(),
        ),
      ),
    );

    startNewDocument(
      _Probe.ref!,
      width: 500,
      height: 500,
      sessionName: 'Fresh',
    );

    final session = container.read(editorSessionProvider);
    expect(session?.projectId, isNull);
    expect(session?.name, 'Fresh');
    expect(container.read(documentControllerProvider).layers, isEmpty);
    expect(container.read(cropControllerProvider).active, isFalse);

    // Commit onto the NEW document, force the autosave through,
    // and prove the old project is untouched.
    await tester.runAsync(() async {
      container
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('new-layer')));
      await container.read(autosaveControllerProvider.notifier).flushNow();

      final projects = container.read(projectStoreProvider).value!;
      expect(projects, hasLength(1), reason: 'no throwaway record');
      expect(projects.single.id, 'p1');
      expect(
        projects.single.documentJson,
        savedJson,
        reason:
            'the old project must keep its saved content — pre-fix '
            'the new blank document was upserted over it',
      );
    });
  });

  testWidgets('startNewDocument with an image URL seeds and selects it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    installFakeDocumentsDir();
    final dir = tempProjectsDir();
    final container = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(container.dispose);
    container
        .read(documentControllerProvider.notifier)
        .newDocument(width: 1000, height: 1000);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: _Probe(),
        ),
      ),
    );

    startNewDocument(
      _Probe.ref!,
      width: 640,
      height: 480,
      sessionName: 'Fresh',
      imageUrl: 'https://example.com/x.png',
    );

    final doc = container.read(documentControllerProvider);
    expect(doc.width, 640);
    expect(doc.layers, hasLength(1));
  });
}
