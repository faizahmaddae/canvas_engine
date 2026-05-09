// Tests for the editor's debounced autosave.
//
// Contract under test (see [AutosaveController]):
//   1. Only autosaves projects that already have a [projectId] on the
//      session — otherwise the home grid would fill with throwaway
//      "Untitled" records on the first stroke.
//   2. Debounces a burst of commits into a single write.
//   3. flushNow() bypasses the debounce timer.
//   4. Skips writing when the encoded document hasn't changed (e.g.
//      undo/redo bouncing back to a saved state).

import 'package:canvas_engine/features/editor/application/autosave_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/editor_session.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues(const {});
  final c = ProviderContainer();
  // Resolve async stores up front.
  await c.read(projectStoreProvider.future);
  // Mount the autosave controller so its listener is wired.
  c.read(autosaveControllerProvider);
  // Seed a blank document so commits succeed.
  c
      .read(documentControllerProvider.notifier)
      .newDocument(width: 1000, height: 1000);
  return c;
}

ShapeLayer _shape(String id) => ShapeLayer(
      id: id,
      transform: LayerTransform(
        position: Offset.zero,
        size: const Size(50, 50),
      ),
      kind: ShapeKind.rectangle,
      fillColor: const Color(0xFFFFFFFF),
    );

void main() {
  test('does NOT autosave when session has no projectId', () async {
    final c = await _container();
    addTearDown(c.dispose);

    // No editor session id → unsaved doc → autosave must skip.
    c.read(editorSessionProvider.notifier).state =
        const EditorSession(name: 'Untitled');

    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(_shape('a')));
    await c.read(autosaveControllerProvider.notifier).flushNow();

    expect(c.read(projectStoreProvider).value, isEmpty,
        reason: 'fresh, never-saved docs must not silently create projects');
  });

  test('autosaves an existing project after a committed edit', () async {
    final c = await _container();
    addTearDown(c.dispose);

    // Pretend the user already saved this project once.
    final original = Project(
      id: 'proj-1',
      name: 'My design',
      width: 1000,
      height: 1000,
      createdAt: DateTime.utc(2026, 1, 1),
      lastModified: DateTime.utc(2026, 1, 1),
      documentJson: c.read(documentControllerProvider.notifier).exportJson(),
    );
    await c.read(projectStoreProvider.notifier).upsert(original);
    c.read(editorSessionProvider.notifier).state =
        const EditorSession(name: 'My design', projectId: 'proj-1');

    // Commit a real edit, then force-flush past the debounce.
    c.read(documentControllerProvider.notifier).execute(AddLayerCommand(_shape('shape-a')));
    await c.read(autosaveControllerProvider.notifier).flushNow();

    final saved =
        c.read(projectStoreProvider).value!.firstWhere((p) => p.id == 'proj-1');
    expect(saved.documentJson, contains('shape-a'),
        reason: 'autosave must persist the new layer');
    expect(saved.lastModified.isAfter(original.lastModified), isTrue,
        reason: 'lastModified must advance on every autosave');
    expect(saved.createdAt, original.createdAt,
        reason: 'createdAt must be preserved across autosaves');
  });

  test('skips writing when the document is unchanged', () async {
    final c = await _container();
    addTearDown(c.dispose);

    final json = c.read(documentControllerProvider.notifier).exportJson();
    final original = Project(
      id: 'proj-2',
      name: 'No-op',
      width: 1000,
      height: 1000,
      createdAt: DateTime.utc(2026, 1, 1),
      lastModified: DateTime.utc(2026, 1, 1),
      documentJson: json,
    );
    await c.read(projectStoreProvider.notifier).upsert(original);
    c.read(editorSessionProvider.notifier).state =
        const EditorSession(name: 'No-op', projectId: 'proj-2');

    // Bump the commit version manually — simulates a command that
    // returned an identical document (e.g. selecting an already-
    // selected style). Autosave should detect the no-op and skip.
    c.read(documentCommitVersionProvider.notifier).bump();
    await c.read(autosaveControllerProvider.notifier).flushNow();

    final after =
        c.read(projectStoreProvider).value!.firstWhere((p) => p.id == 'proj-2');
    expect(after.lastModified, original.lastModified,
        reason: 'no-op edits must not bump lastModified');
  });

  test('debounces a burst of commits into a single flush', () async {
    final c = await _container();
    addTearDown(c.dispose);

    final original = Project(
      id: 'proj-3',
      name: 'Burst',
      width: 1000,
      height: 1000,
      createdAt: DateTime.utc(2026, 1, 1),
      lastModified: DateTime.utc(2026, 1, 1),
      documentJson: c.read(documentControllerProvider.notifier).exportJson(),
    );
    await c.read(projectStoreProvider.notifier).upsert(original);
    c.read(editorSessionProvider.notifier).state =
        const EditorSession(name: 'Burst', projectId: 'proj-3');

    // Fire several commits in rapid succession. None of them should
    // hit disk synchronously — only the debounced flush at the end
    // (here forced via flushNow) writes a single record.
    final docCtrl = c.read(documentControllerProvider.notifier);
    docCtrl.execute(AddLayerCommand(_shape('a')));
    docCtrl.execute(AddLayerCommand(_shape('b')));
    docCtrl.execute(AddLayerCommand(_shape('c')));

    // Pre-flush state still has the original record.
    final pre =
        c.read(projectStoreProvider).value!.firstWhere((p) => p.id == 'proj-3');
    expect(pre.documentJson, original.documentJson,
        reason: 'debounce must hold the write back until the timer fires');

    await c.read(autosaveControllerProvider.notifier).flushNow();

    final post =
        c.read(projectStoreProvider).value!.firstWhere((p) => p.id == 'proj-3');
    expect(post.documentJson, contains('"a"'));
    expect(post.documentJson, contains('"b"'));
    expect(post.documentJson, contains('"c"'));
  });
}
