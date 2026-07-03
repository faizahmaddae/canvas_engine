// Crash-recovery read path (ProjectRecoveryService) and the draft
// journal slot (AutosaveController.draftJournalId).
//
// Contract under test:
//   1. A journal that differs from the persisted save is offered;
//      a byte-identical journal is redundant and self-clears.
//   2. Never-saved sessions journal under the reserved 'draft' slot.
//   3. A deliberate exit (flushNow(sessionEnding: true)) clears the
//      draft; an app-pause flush (default) keeps it — that is the
//      process-death case the slot exists to recover.

import 'dart:io';

import 'package:canvas_engine/features/editor/application/autosave_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/edit_journal.dart';
import 'package:canvas_engine/features/editor/application/editor_session.dart';
import 'package:canvas_engine/features/editor/application/project_recovery_service.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_path_provider.dart';
import '../../support/temp_projects_dir.dart';

ShapeLayer _shape(String id) => ShapeLayer(
  id: id,
  transform: LayerTransform(position: Offset.zero, size: const Size(50, 50)),
  kind: ShapeKind.rectangle,
  fillColor: const Color(0xFFFFFFFF),
);

File _journalFile(Directory docs, String id) =>
    File('${docs.path}${Platform.pathSeparator}journal'
        '${Platform.pathSeparator}$id.json');

Future<ProviderContainer> _editorContainer() async {
  SharedPreferences.setMockInitialValues(const {});
  final projectsDir = tempProjectsDir();
  final c = ProviderContainer(overrides: [
    projectsDirectoryProvider.overrideWith((ref) async => projectsDir),
  ]);
  addTearDown(c.dispose);
  await c.read(projectStoreProvider.future);
  c.read(autosaveControllerProvider);
  c.read(documentControllerProvider.notifier)
      .newDocument(width: 1000, height: 1000);
  return c;
}

/// Journal writes are debounced (750 ms) real timers — wait them out.
Future<void> _settleJournal() =>
    Future<void>.delayed(EditJournal.writeDebounce + const Duration(milliseconds: 150));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProjectRecoveryService', () {
    const service = ProjectRecoveryService();

    test('offers journal JSON that differs from the persisted save',
        () async {
      installFakeDocumentsDir();
      final c = await _editorContainer();
      c.read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('crashed-layer')));
      final crashedJson =
          c.read(documentControllerProvider.notifier).exportJson();
      final journal = await EditJournal.open('p1');
      await journal.flushNow(c.read(documentControllerProvider));

      final pending = await service.pendingJsonForProject(
        projectId: 'p1',
        persistedJson: '{"version":1,"width":1,"height":1,"layers":[]}',
      );
      expect(pending, crashedJson,
          reason: 'a journal newer than the save must be offered');
    });

    test('byte-identical journal is redundant and self-clears', () async {
      final docs = installFakeDocumentsDir();
      final c = await _editorContainer();
      final json = c.read(documentControllerProvider.notifier).exportJson();
      final journal = await EditJournal.open('p2');
      await journal.flushNow(c.read(documentControllerProvider));
      expect(_journalFile(docs, 'p2').existsSync(), isTrue);

      final pending = await service.pendingJsonForProject(
        projectId: 'p2',
        persistedJson: json,
      );
      expect(pending, isNull,
          reason: 'autosave landed before the crash — nothing to offer');
      expect(_journalFile(docs, 'p2').existsSync(), isFalse,
          reason: 'redundant journal must not re-prompt on every open');
    });

    test('no journal → no offer; clearForProject is idempotent', () async {
      installFakeDocumentsDir();
      expect(
        await service.pendingJsonForProject(
          projectId: 'ghost',
          persistedJson: '{}',
        ),
        isNull,
      );
      await service.clearForProject('ghost'); // must not throw
    });

    test('draft slot round-trips through pendingDraftJson/clearDraft',
        () async {
      final docs = installFakeDocumentsDir();
      final c = await _editorContainer();
      c.read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('draft-layer')));
      final journal =
          await EditJournal.open(AutosaveController.draftJournalId);
      await journal.flushNow(c.read(documentControllerProvider));

      final draft = await service.pendingDraftJson();
      expect(draft, contains('draft-layer'));

      await service.clearDraft();
      expect(
        _journalFile(docs, AutosaveController.draftJournalId).existsSync(),
        isFalse,
      );
      expect(await service.pendingDraftJson(), isNull);
    });
  });

  group('draft journal slot (autosave wiring)', () {
    test('unsaved session journals to draft; pause keeps it, exit clears',
        () async {
      final docs = installFakeDocumentsDir();
      final c = await _editorContainer();
      c.read(editorSessionProvider.notifier).state =
          const EditorSession(name: 'Untitled');

      c.read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('a')));
      await _settleJournal();
      final draftFile =
          _journalFile(docs, AutosaveController.draftJournalId);
      expect(draftFile.existsSync(), isTrue,
          reason: 'never-saved docs must journal under the draft slot');

      // App-pause style flush: journal must SURVIVE (the OS may kill
      // the process next — that is the recovery case).
      await c.read(autosaveControllerProvider.notifier).flushNow();
      expect(draftFile.existsSync(), isTrue,
          reason: 'a pause flush is not a discard gesture');

      // Deliberate exit: leaving an unsaved doc is the product's
      // discard gesture — the draft must not haunt the next launch.
      await c
          .read(autosaveControllerProvider.notifier)
          .flushNow(sessionEnding: true);
      expect(draftFile.existsSync(), isFalse);
    });

    test('saved sessions journal under their own project id', () async {
      final docs = installFakeDocumentsDir();
      final c = await _editorContainer();
      c.read(editorSessionProvider.notifier).state =
          const EditorSession(name: 'Saved', projectId: 'proj-9');

      c.read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('a')));
      await _settleJournal();

      expect(_journalFile(docs, 'proj-9').existsSync(), isTrue);
      expect(
        _journalFile(docs, AutosaveController.draftJournalId).existsSync(),
        isFalse,
      );
    });
  });
}
