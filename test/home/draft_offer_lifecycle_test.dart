// The resume-draft offer's lifecycle, at the screen level.
//
// Audit P2-2: "Discard" sat beside "Resume" as a peer and deleted the
// journal on one tap — the only copy of never-saved work, unconfirmed,
// while deleting an already-SAVED project required a dialog. The
// destructive option was the cheap one.
//
// Audit P2-15: `_offerDraftResume` only ever SET the pending JSON.
// When `preserveOrphanDraft` emptied the slot for a new session, the
// card stayed up holding the promoted document in memory, so Resume
// re-opened as a fresh unsaved session work that already existed as a
// project — two copies of one drawing.
//
// These pump the real HomeScreen so the offer, its actions and the
// journal underneath are exercised together.

import 'package:canvas_engine/features/editor/application/autosave_controller.dart';
import 'package:canvas_engine/features/editor/application/edit_journal.dart';
import 'package:canvas_engine/features/editor/application/project_recovery_service.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/presentation/home_actions.dart';
import 'package:canvas_engine/features/home/presentation/home_screen.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_path_provider.dart';
import '../support/temp_projects_dir.dart';

EditorDocument _doc() => EditorDocument(
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

/// Let real (non-fake-async) IO settle. The offer resolves through a
/// post-frame callback that reads the journal off disk, and the delete
/// path awaits a file unlink before its `setState` — neither completes
/// on a bare `pump()`. Must be called inside `tester.runAsync`.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump();
  }
}

const _card = ValueKey('home-resume-draft');
const _overflow = ValueKey('resume-draft-overflow');
const _notNow = ValueKey('resume-draft-not-now');
const _delete = ValueKey('resume-draft-delete');

/// Neither of the two actions that are not Resume sits on the card any
/// more — both live behind «⋯», one deliberate tap further away than
/// the button that opens the draft.
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(_overflow));
  await tester.pumpAndSettle();
}

void main() {
  late ProviderContainer container;

  Future<void> seedDraft(WidgetTester tester, {String? name}) async {
    await tester.runAsync(() async {
      final journal = await EditJournal.open(AutosaveController.draftJournalId);
      await journal.flushNow(_doc());
      if (name != null) await journal.writeMeta(name: name);
    });
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    // The offer resolves in a post-frame callback that does real file
    // IO, which cannot run in the fake-async zone — pump inside
    // runAsync so the read actually completes.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('en'),
            home: HomeScreen(),
          ),
        ),
      );
      await _drain(tester);
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    installFakeDocumentsDir();
    container = ProviderContainer(
      overrides: [
        projectsDirectoryProvider.overrideWith(
          (ref) async => tempProjectsDir(),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  testWidgets('a pending draft puts the offer on screen', (tester) async {
    await seedDraft(tester);
    await pumpHome(tester);
    expect(find.byKey(_card), findsOneWidget);
  });

  testWidgets('the offer names the draft it is offering', (tester) async {
    await seedDraft(tester, name: 'پوستر نوروز');
    await pumpHome(tester);
    expect(
      find.text('پوستر نوروز'),
      findsOneWidget,
      reason: 'the card should answer "resume WHAT?", not just "resume"',
    );
  });

  testWidgets('"Not now" hides the offer and KEEPS the draft', (tester) async {
    await seedDraft(tester);
    await pumpHome(tester);

    await _openMenu(tester);
    await tester.tap(find.byKey(_notNow));
    await tester.pumpAndSettle();

    expect(find.byKey(_card), findsNothing);
    await tester.runAsync(() async {
      expect(
        await const ProjectRecoveryService().pendingDraftJson(),
        isNotNull,
        reason: 'dismissing the offer is not deleting the work',
      );
    });
  });

  testWidgets('"Delete draft" asks first, and cancelling keeps everything', (
    tester,
  ) async {
    await seedDraft(tester);
    await pumpHome(tester);

    await _openMenu(tester);
    await tester.tap(find.byKey(_delete));
    await tester.pumpAndSettle();
    expect(find.text('Delete this draft?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byKey(_card), findsOneWidget);
    await tester.runAsync(() async {
      expect(
        await const ProjectRecoveryService().pendingDraftJson(),
        isNotNull,
      );
    });
  });

  testWidgets('"Delete draft", confirmed, is the one path that destroys it', (
    tester,
  ) async {
    await seedDraft(tester);
    await pumpHome(tester);

    await _openMenu(tester);
    await tester.tap(find.byKey(_delete));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await _drain(tester);
    });
    await tester.pumpAndSettle();

    expect(find.byKey(_card), findsNothing);
    await tester.runAsync(() async {
      expect(await const ProjectRecoveryService().pendingDraftJson(), isNull);
    });
  });

  testWidgets('the offer disappears once the slot is empty — it must not '
      'keep offering work that is already a project', (tester) async {
    await seedDraft(tester);
    await pumpHome(tester);
    expect(find.byKey(_card), findsOneWidget);

    // Whatever emptied the slot (here: promotion by a new session).
    await tester.runAsync(() async {
      final journal = await EditJournal.open(AutosaveController.draftJournalId);
      await journal.clear();
    });

    // Re-check, the way an editor round-trip does via the tick.
    await tester.runAsync(() async {
      container.read(draftOfferTickProvider.notifier).bump();
      await _drain(tester);
    });

    expect(
      find.byKey(_card),
      findsNothing,
      reason: 'a stale offer is how one drawing became two copies',
    );
  });
}
