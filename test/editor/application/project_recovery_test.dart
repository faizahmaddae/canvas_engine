// Crash-recovery read path (ProjectRecoveryService) and the draft
// journal slot (AutosaveController.draftJournalId).
//
// Contract under test:
//   1. A journal that differs from the persisted save is offered;
//      a byte-identical journal is redundant and self-clears.
//   2. Never-saved sessions journal under the reserved 'draft' slot.
//   3. Both an app-pause flush (default) AND a deliberate exit
//      (flushNow(sessionEnding: true)) keep a draft with content —
//      back must never destroy the only copy of unsaved work. Only
//      an untouched blank document clears the slot on exit.

import 'dart:io';

import 'package:canvas_engine/features/editor/application/autosave_controller.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/edit_journal.dart';
import 'package:canvas_engine/features/editor/application/editor_session.dart';
import 'package:canvas_engine/features/editor/application/imported_image_path_codec.dart';
import 'package:canvas_engine/features/editor/application/project_recovery_service.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/image/image_layer.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
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

File _journalFile(Directory docs, String id) => File(
  '${docs.path}${Platform.pathSeparator}journal'
  '${Platform.pathSeparator}$id.json',
);

EditorDocument _imageDoc(String sourcePath) => EditorDocument(
  layers: [
    ImageLayer(
      id: 'img',
      transform: LayerTransform(
        position: Offset.zero,
        size: const Size(10, 10),
      ),
      source: ImageSource.file(sourcePath),
    ),
  ],
  width: 100,
  height: 100,
);

bool _exists(String p) => File(p).existsSync();

void _writeJournal(Directory docs, String id, String json) {
  Directory(
    '${docs.path}${Platform.pathSeparator}journal',
  ).createSync(recursive: true);
  _journalFile(docs, id).writeAsStringSync(json);
}

Future<ProviderContainer> _editorContainer() async {
  SharedPreferences.setMockInitialValues(const {});
  final projectsDir = tempProjectsDir();
  final c = ProviderContainer(
    overrides: [
      projectsDirectoryProvider.overrideWith((ref) async => projectsDir),
    ],
  );
  addTearDown(c.dispose);
  await c.read(projectStoreProvider.future);
  c.read(autosaveControllerProvider);
  c
      .read(documentControllerProvider.notifier)
      .newDocument(width: 1000, height: 1000);
  return c;
}

/// Journal writes are debounced (750 ms) real timers — wait them out.
Future<void> _settleJournal() => Future<void>.delayed(
  EditJournal.writeDebounce + const Duration(milliseconds: 150),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProjectRecoveryService', () {
    const service = ProjectRecoveryService();

    test('offers journal JSON that differs from the persisted save', () async {
      final docs = installFakeDocumentsDir();
      final c = await _editorContainer();
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('crashed-layer')));
      final crashedJson = c
          .read(documentControllerProvider.notifier)
          .exportJson();
      final journal = await EditJournal.open('p1');
      await journal.flushNow(c.read(documentControllerProvider));

      final pending = await service.pendingJsonForProject(
        projectId: 'p1',
        persistedJson: '{"version":1,"width":1,"height":1,"layers":[]}',
        importedImagesDir: '${docs.path}/imported_images',
        fileExists: (p) => File(p).existsSync(),
      );
      expect(
        pending,
        crashedJson,
        reason: 'a journal newer than the save must be offered',
      );
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
        importedImagesDir: '${docs.path}/imported_images',
        fileExists: (p) => File(p).existsSync(),
      );
      expect(
        pending,
        isNull,
        reason: 'autosave landed before the crash — nothing to offer',
      );
      expect(
        _journalFile(docs, 'p2').existsSync(),
        isFalse,
        reason: 'redundant journal must not re-prompt on every open',
      );
    });

    test('#12 journal stores canonical image paths; recovery offer hydrates '
        'to an absolute runtime path', () async {
      final docs = installFakeDocumentsDir();
      final c = await _editorContainer();
      final imgDir = await c.read(importedImagesDirectoryProvider.future);
      await imgDir.create(recursive: true);
      File('${imgDir.path}/pic.png').writeAsBytesSync(const [1, 2, 3]);

      // A crashed session holding an app-owned image (absolute runtime
      // path) journals under its project id.
      c
          .read(documentControllerProvider.notifier)
          .execute(
            AddLayerCommand(
              ImageLayer(
                id: 'photo',
                transform: LayerTransform(
                  position: Offset.zero,
                  size: const Size(100, 100),
                ),
                source: ImageSource.file('${imgDir.path}/pic.png'),
              ),
            ),
          );
      final journal = await EditJournal.open('p-img');
      await journal.flushNow(c.read(documentControllerProvider));

      // The journal on disk stores the portable canonical reference.
      final raw = _journalFile(docs, 'p-img').readAsStringSync();
      expect(raw, contains('"file": "imported_images/pic.png"'));
      expect(raw, isNot(contains(imgDir.path)));

      // The recovery offer decodes back to a usable absolute path.
      final pending = await service.pendingJsonForProject(
        projectId: 'p-img',
        persistedJson: '{"version":1,"width":1,"height":1,"layers":[]}',
        importedImagesDir: imgDir.path,
        fileExists: (p) => File(p).existsSync(),
      );
      expect(pending, isNotNull);
      final runtime = ImportedImagePathCodec.decodeToRuntime(
        pending!,
        importedImagesDir: imgDir.path,
        fileExists: (p) => File(p).existsSync(),
      );
      final source = (runtime.layers.single as ImageLayer).source;
      expect(source.filePath, '${imgDir.path}/pic.png');
    });

    test('no journal → no offer; clearForProject is idempotent', () async {
      final docs = installFakeDocumentsDir();
      expect(
        await service.pendingJsonForProject(
          projectId: 'ghost',
          persistedJson: '{}',
          importedImagesDir: '${docs.path}/imported_images',
          fileExists: (p) => File(p).existsSync(),
        ),
        isNull,
      );
      await service.clearForProject('ghost'); // must not throw
    });

    test(
      'draft slot round-trips through pendingDraftJson/clearDraft',
      () async {
        final docs = installFakeDocumentsDir();
        final c = await _editorContainer();
        c
            .read(documentControllerProvider.notifier)
            .execute(AddLayerCommand(_shape('draft-layer')));
        final journal = await EditJournal.open(
          AutosaveController.draftJournalId,
        );
        await journal.flushNow(c.read(documentControllerProvider));

        final draft = await service.pendingDraftJson();
        expect(draft, contains('draft-layer'));

        await service.clearDraft();
        expect(
          _journalFile(docs, AutosaveController.draftJournalId).existsSync(),
          isFalse,
        );
        expect(await service.pendingDraftJson(), isNull);
      },
    );
  });

  group('draft journal slot (autosave wiring)', () {
    test('unsaved session journals to draft; pause AND exit keep it when '
        'the document has content', () async {
      // DELIBERATE EXPECTATION CHANGE (roadmap tb0 0.4): this test
      // previously pinned "exit clears the draft" — walking away
      // was the discard gesture. That made an accidental back-swipe
      // after a long unsaved session an irreversible total loss.
      // Exit now KEEPS the draft (Home's resume banner recovers
      // it); only an untouched blank document still clears.
      final docs = installFakeDocumentsDir();
      final c = await _editorContainer();
      c.read(editorSessionProvider.notifier).state = const EditorSession(
        name: 'Untitled',
      );

      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('a')));
      await _settleJournal();
      final draftFile = _journalFile(docs, AutosaveController.draftJournalId);
      expect(
        draftFile.existsSync(),
        isTrue,
        reason: 'never-saved docs must journal under the draft slot',
      );

      // App-pause style flush: journal must SURVIVE (the OS may kill
      // the process next — that is the recovery case).
      await c.read(autosaveControllerProvider.notifier).flushNow();
      expect(
        draftFile.existsSync(),
        isTrue,
        reason: 'a pause flush is not a discard gesture',
      );

      // Deliberate exit with CONTENT: the journal is the only copy
      // of the work — it must survive for the resume offer.
      await c
          .read(autosaveControllerProvider.notifier)
          .flushNow(sessionEnding: true);
      expect(
        draftFile.existsSync(),
        isTrue,
        reason: 'back must never destroy a non-empty unsaved doc',
      );
    });

    test('exit flushes pending edits into the kept draft first', () async {
      // A kept-but-stale journal is not enough: edits inside the
      // 750 ms debounce window at the moment of exit must land in
      // the surviving draft.
      final docs = installFakeDocumentsDir();
      final c = await _editorContainer();
      c.read(editorSessionProvider.notifier).state = const EditorSession(
        name: 'Untitled',
      );

      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('a')));
      await _settleJournal();
      // Second edit, NOT settled — sits in the debounce window.
      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('b')));
      await c
          .read(autosaveControllerProvider.notifier)
          .flushNow(sessionEnding: true);

      final draftFile = _journalFile(docs, AutosaveController.draftJournalId);
      expect(draftFile.existsSync(), isTrue);
      expect(
        draftFile.readAsStringSync(),
        contains('"b"'),
        reason: 'the exit flush must persist the latest edits',
      );
    });

    test(
      'exit with an untouched blank document still clears the slot',
      () async {
        final docs = installFakeDocumentsDir();
        final c = await _editorContainer();
        c.read(editorSessionProvider.notifier).state = const EditorSession(
          name: 'Untitled',
        );

        // Journal something first so a file exists, then undo back to
        // empty and clear history via a fresh blank document — the
        // realistic path is simply: open editor, do nothing, leave.
        final draftFile = _journalFile(docs, AutosaveController.draftJournalId);
        await c
            .read(autosaveControllerProvider.notifier)
            .flushNow(sessionEnding: true);
        expect(
          draftFile.existsSync(),
          isFalse,
          reason: 'blank round-trips must not spawn resume offers',
        );
      },
    );

    test(
      'pause flush persists the draft immediately, before the debounce',
      () async {
        final docs = installFakeDocumentsDir();
        final c = await _editorContainer();
        c.read(editorSessionProvider.notifier).state = const EditorSession(
          name: 'Untitled',
        );

        c
            .read(documentControllerProvider.notifier)
            .execute(AddLayerCommand(_shape('unflushed')));
        // Deliberately do NOT settle: the 750 ms journal debounce has not
        // fired. This is the regression — a pause here must force the
        // journal to disk NOW, or an OS kill of the suspended process
        // would lose these edits with no journal to recover.
        final draftFile = _journalFile(docs, AutosaveController.draftJournalId);
        expect(
          draftFile.existsSync(),
          isFalse,
          reason: 'precondition: the debounce has not written yet',
        );

        await c.read(autosaveControllerProvider.notifier).flushNow();

        expect(
          draftFile.existsSync(),
          isTrue,
          reason: 'pause flush must persist the draft before the debounce',
        );
        expect(draftFile.readAsStringSync(), contains('unflushed'));
      },
    );

    test('saved sessions journal under their own project id', () async {
      final docs = installFakeDocumentsDir();
      final c = await _editorContainer();
      c.read(editorSessionProvider.notifier).state = const EditorSession(
        name: 'Saved',
        projectId: 'proj-9',
      );

      c
          .read(documentControllerProvider.notifier)
          .execute(AddLayerCommand(_shape('a')));
      await _settleJournal();

      expect(_journalFile(docs, 'proj-9').existsSync(), isTrue);
      expect(
        _journalFile(docs, AutosaveController.draftJournalId).existsSync(),
        isFalse,
      );
    });
  });

  // Migration window: a legacy project (absolute image paths) whose
  // journal was written after the fix (canonical), or vice-versa. Both
  // encodings describe the SAME document, so recovery must not raise a
  // spurious "resume?" offer — while a genuine unsaved change still does.
  group(
    'migration-window recovery: mixed legacy/canonical (same container)',
    () {
      const service = ProjectRecoveryService();

      // Two encodings of the SAME one-image document for [docs]'s current
      // imported-images directory (both under the current container).
      ({String legacy, String canonical, String dir}) reps(Directory docs) {
        final dir = '${docs.path}/imported_images';
        final doc = _imageDoc('$dir/pic.png');
        return (
          legacy: DocumentCodec.encode(doc), // absolute path
          canonical: ImportedImagePathCodec.encodeForStorage(
            doc,
            importedImagesDir: dir,
          ),
          dir: dir,
        );
      }

      test('legacy persisted + equivalent legacy journal → no offer', () async {
        final docs = installFakeDocumentsDir();
        final r = reps(docs);
        _writeJournal(docs, 'a', r.legacy);
        expect(
          await service.pendingJsonForProject(
            projectId: 'a',
            persistedJson: r.legacy,
            importedImagesDir: r.dir,
            fileExists: _exists,
          ),
          isNull,
        );
      });

      test(
        'legacy persisted + equivalent CANONICAL journal → no offer',
        () async {
          final docs = installFakeDocumentsDir();
          final r = reps(docs);
          _writeJournal(docs, 'b', r.canonical);
          expect(
            await service.pendingJsonForProject(
              projectId: 'b',
              persistedJson: r.legacy,
              importedImagesDir: r.dir,
              fileExists: _exists,
            ),
            isNull,
            reason: 'same document, mixed encodings — no spurious resume offer',
          );
        },
      );

      test(
        'canonical persisted + equivalent LEGACY journal → no offer',
        () async {
          final docs = installFakeDocumentsDir();
          final r = reps(docs);
          _writeJournal(docs, 'c', r.legacy);
          expect(
            await service.pendingJsonForProject(
              projectId: 'c',
              persistedJson: r.canonical,
              importedImagesDir: r.dir,
              fileExists: _exists,
            ),
            isNull,
          );
        },
      );

      test('a genuinely changed recovered document still offers', () async {
        final docs = installFakeDocumentsDir();
        final r = reps(docs);
        final changed = ImportedImagePathCodec.encodeForStorage(
          EditorDocument(
            layers: [
              _imageDoc('${r.dir}/pic.png').layers.single,
              _shape('added'),
            ],
            width: 100,
            height: 100,
          ),
          importedImagesDir: r.dir,
        );
        _writeJournal(docs, 'd', changed);
        expect(
          await service.pendingJsonForProject(
            projectId: 'd',
            persistedJson: r.legacy,
            importedImagesDir: r.dir,
            fileExists: _exists,
          ),
          isNotNull,
          reason: 'a real unsaved change must still be offered',
        );
      });
    },
  );

  // Cross-container relocation — application data restored into a NEW
  // container. Persisted and journal references live under DIFFERENT
  // absolute prefixes but resolve to the SAME current file; recovery must
  // compare by what resolves on the current install, not stored bytes.
  group('cross-container recovery: relocated imported images', () {
    const service = ProjectRecoveryService();

    // Stale OLD-container absolute (direct parent imported_images, never
    // physically present) + the equivalent canonical reference, for the
    // current install's imported-images directory.
    ({String oldAbsolute, String canonical, String currentDir, String oldPath})
    reps(Directory docs, Directory oldContainer) {
      final currentDir = '${docs.path}/imported_images';
      final oldPath = '${oldContainer.path}/imported_images/pic.png';
      return (
        oldAbsolute: DocumentCodec.encode(_imageDoc(oldPath)),
        canonical: DocumentCodec.encode(_imageDoc('imported_images/pic.png')),
        currentDir: currentDir,
        oldPath: oldPath,
      );
    }

    File currentFile(Directory docs) {
      final dir = Directory('${docs.path}/imported_images')
        ..createSync(recursive: true);
      return File('${dir.path}/pic.png')..writeAsBytesSync(const [1, 2, 3, 4]);
    }

    test('(a) stale old-container persisted + canonical journal, file present '
        '→ no offer', () async {
      final docs = installFakeDocumentsDir();
      final r = reps(docs, tempProjectsDir());
      currentFile(docs); // the restored file, under the current dir
      expect(_exists(r.oldPath), isFalse, reason: 'old path must be absent');
      _writeJournal(docs, 'xa', r.canonical);
      expect(
        await service.pendingJsonForProject(
          projectId: 'xa',
          persistedJson: r.oldAbsolute,
          importedImagesDir: r.currentDir,
          fileExists: _exists,
        ),
        isNull,
        reason: 'both resolve to the same current file — no spurious offer',
      );
    });

    test('(b) canonical persisted + stale old-container journal, file present '
        '→ no offer', () async {
      final docs = installFakeDocumentsDir();
      final r = reps(docs, tempProjectsDir());
      currentFile(docs);
      _writeJournal(docs, 'xb', r.oldAbsolute);
      expect(
        await service.pendingJsonForProject(
          projectId: 'xb',
          persistedJson: r.canonical,
          importedImagesDir: r.currentDir,
          fileExists: _exists,
        ),
        isNull,
      );
    });

    test(
      '(c) mixed representation with NO current candidate → not equivalent',
      () async {
        final docs = installFakeDocumentsDir();
        final r = reps(docs, tempProjectsDir());
        // Deliberately do NOT create the current file.
        _writeJournal(docs, 'xc', r.canonical);
        expect(
          await service.pendingJsonForProject(
            projectId: 'xc',
            persistedJson: r.oldAbsolute,
            importedImagesDir: r.currentDir,
            fileExists: _exists,
          ),
          isNotNull,
          reason: 'unresolved references must not be silently treated as equal',
        );
      },
    );

    test(
      '(d) external absolute with the same filename → not equivalent',
      () async {
        final docs = installFakeDocumentsDir();
        final r = reps(docs, tempProjectsDir());
        currentFile(docs); // a real current pic.png with the same basename
        final external = DocumentCodec.encode(
          _imageDoc('/Users/someone/Desktop/pic.png'),
        );
        _writeJournal(docs, 'xd', r.canonical);
        expect(
          await service.pendingJsonForProject(
            projectId: 'xd',
            persistedJson: external,
            importedImagesDir: r.currentDir,
            fileExists: _exists,
          ),
          isNotNull,
          reason: 'an external path must never be rebased by basename alone',
        );
      },
    );

    test('(e) a genuine non-path document change → still offers', () async {
      final docs = installFakeDocumentsDir();
      final r = reps(docs, tempProjectsDir());
      currentFile(docs);
      final changed = DocumentCodec.encode(
        EditorDocument(
          layers: [
            _imageDoc('imported_images/pic.png').layers.single,
            _shape('added'),
          ],
          width: 100,
          height: 100,
        ),
      );
      _writeJournal(docs, 'xe', changed);
      expect(
        await service.pendingJsonForProject(
          projectId: 'xe',
          persistedJson: r.canonical,
          importedImagesDir: r.currentDir,
          fileExists: _exists,
        ),
        isNotNull,
        reason: 'a real unsaved change must still be offered',
      );
    });
  });
}
