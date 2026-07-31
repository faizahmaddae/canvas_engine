// Draft-slot collision policy (roadmap tb0 0.4b): starting a NEW
// unsaved session while the single 'draft' journal slot still holds
// a kept draft must not clobber it. [HomeActions.preserveOrphanDraft]
// promotes the pending draft to a regular project record, then
// clears the slot — newest session wins the slot, no work is lost.

import 'package:canvas_engine/features/editor/application/autosave_controller.dart';
import 'package:canvas_engine/features/editor/application/edit_journal.dart';
import 'package:canvas_engine/features/editor/application/project_recovery_service.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/presentation/home_actions.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_path_provider.dart';
import '../support/temp_projects_dir.dart';

class _Probe extends ConsumerWidget {
  const _Probe();
  static BuildContext? ctx;
  static WidgetRef? ref;
  @override
  Widget build(BuildContext context, WidgetRef r) {
    ctx = context;
    ref = r;
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('preserveOrphanDraft promotes the pending draft to a project and '
      'clears the slot; empty slot is a no-op', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    installFakeDocumentsDir();
    final dir = tempProjectsDir();
    final container = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(container.dispose);

    late String draftJson;
    await tester.runAsync(() async {
      await container.read(projectStoreProvider.future);
      // A kept draft from a backed-out unsaved session.
      final doc = EditorDocument(
        layers: [
          ShapeLayer(
            id: 'orphan',
            transform: LayerTransform(
              position: Offset.zero,
              size: const Size(80, 80),
            ),
            kind: ShapeKind.rectangle,
            fillColor: const Color(0xFF112233),
          ),
        ],
        width: 720,
        height: 900,
      );
      draftJson = DocumentCodec.encode(doc);
      final journal = await EditJournal.open(AutosaveController.draftJournalId);
      await journal.flushNow(doc);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: _Probe(),
        ),
      ),
    );

    final actions = HomeActions(_Probe.ctx!, _Probe.ref!);
    await tester.runAsync(() async {
      await actions.preserveOrphanDraft();

      final projects = container.read(projectStoreProvider).value!;
      expect(projects, hasLength(1));
      expect(projects.single.documentJson, draftJson);
      expect(projects.single.width, 720);
      expect(projects.single.height, 900);
      expect(projects.single.name, 'Recovered draft');
      expect(
        await const ProjectRecoveryService().pendingDraftJson(),
        isNull,
        reason: 'promotion must clear the slot for the new session',
      );

      // Second call: slot empty → no duplicate record.
      await actions.preserveOrphanDraft();
      expect(container.read(projectStoreProvider).value, hasLength(1));
    });
  });

  // Audit P2-15: every rescue landed as «Recovered draft», so backing
  // out of three sessions produced three projects sharing one title,
  // separable only by dimensions and timestamp. Promotion now carries
  // the draft's own name; the generic label is the fallback for a
  // draft that never recorded one.
  testWidgets('promotion uses the draft\'s own name when it has one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    installFakeDocumentsDir();
    final dir = tempProjectsDir();
    final container = ProviderContainer(
      overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(projectStoreProvider.future);
      final doc = EditorDocument(
        layers: [
          ShapeLayer(
            id: 'orphan',
            transform: LayerTransform(
              position: Offset.zero,
              size: const Size(80, 80),
            ),
            kind: ShapeKind.rectangle,
            fillColor: const Color(0xFF112233),
          ),
        ],
        width: 720,
        height: 900,
      );
      final journal = await EditJournal.open(AutosaveController.draftJournalId);
      await journal.flushNow(doc);
      await journal.writeMeta(name: 'Imported image');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: _Probe(),
        ),
      ),
    );

    final actions = HomeActions(_Probe.ctx!, _Probe.ref!);
    await tester.runAsync(() async {
      await actions.preserveOrphanDraft();
      final projects = container.read(projectStoreProvider).value!;
      expect(projects.single.name, 'Imported image');
      expect(
        projects.single.name,
        isNot('Recovered draft'),
        reason: 'identically-named rescues are what this replaces',
      );
    });
  });
}
