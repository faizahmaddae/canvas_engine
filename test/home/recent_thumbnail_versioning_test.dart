import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_thumbnail.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/home/application/project_store.dart';
import 'package:canvas_engine/features/home/domain/project.dart';
import 'package:canvas_engine/features/home/presentation/widgets/recent_projects_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/temp_projects_dir.dart';

/// Recent project thumbnails must reflect the actual EditorDocument
/// — including canvas background colour. Older PNGs were captured
/// with an opaque white backdrop; the Recent grid now treats those
/// as stale (`thumbnailVersion < currentThumbnailVersion`) and
/// live-renders from `documentJson` via `DocumentThumbnail` so the
/// user never sees a wrong-colour preview while the project waits
/// to be re-saved.
Project _projectWithDoc({
  required String id,
  required EditorDocument doc,
  String? thumbnailPath,
  int thumbnailVersion = 0,
}) {
  final now = DateTime.now();
  return Project(
    id: id,
    name: 'Test',
    width: doc.width,
    height: doc.height,
    createdAt: now,
    lastModified: now,
    documentJson: DocumentCodec.encode(doc),
    thumbnailPath: thumbnailPath,
    thumbnailVersion: thumbnailVersion,
  );
}

Future<void> _pumpRecent(WidgetTester tester, Project project) async {
  SharedPreferences.setMockInitialValues({});
  final dir = tempProjectsDir();
  final container = ProviderContainer(
    overrides: [projectsDirectoryProvider.overrideWith((ref) async => dir)],
  );
  addTearDown(container.dispose);
  // Real file IO — run outside the fake-async zone.
  await tester.runAsync(() async {
    await container.read(projectStoreProvider.future);
    await container.read(projectStoreProvider.notifier).upsert(project);
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecentProjectsGrid(onCreate: () {}, onOpen: (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'stale thumbnailVersion live-renders the document via DocumentThumbnail',
    (tester) async {
      const yellow = Color(0xFFFFEB3B);
      final doc = EditorDocument(
        width: 400,
        height: 400,
        layers: const [],
        backgroundColor: yellow,
      );
      final p = _projectWithDoc(
        id: 'legacy-yellow',
        doc: doc,
        thumbnailPath: '/nonexistent/old.png',
      );
      await _pumpRecent(tester, p);

      expect(find.byType(DocumentThumbnail), findsOneWidget);
      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(DocumentThumbnail),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(box.color, yellow);
    },
  );

  testWidgets('project with no thumbnail still renders via DocumentThumbnail', (
    tester,
  ) async {
    const teal = Color(0xFF008080);
    final doc = EditorDocument(
      width: 200,
      height: 300,
      layers: const [],
      backgroundColor: teal,
    );
    final p = _projectWithDoc(id: 'fresh-teal', doc: doc);
    await _pumpRecent(tester, p);

    expect(find.byType(DocumentThumbnail), findsOneWidget);
    final box = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(DocumentThumbnail),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(box.color, teal);
  });

  test('Project.toJson/fromJson round-trips thumbnailVersion', () {
    final p = Project(
      id: 'x',
      name: 'X',
      width: 100,
      height: 100,
      createdAt: DateTime(2026),
      lastModified: DateTime(2026),
      documentJson: '{}',
      thumbnailVersion: Project.currentThumbnailVersion,
    );
    final back = Project.fromJson(p.toJson());
    expect(back.thumbnailVersion, Project.currentThumbnailVersion);
  });

  test('legacy JSON without thumbnailVersion decodes as 0 (stale)', () {
    final json = <String, Object?>{
      'id': 'legacy',
      'name': 'Legacy',
      'width': 100.0,
      'height': 100.0,
      'lastModified': DateTime(2025).toIso8601String(),
      'documentJson': '{}',
      'thumbnailPath': '/some/old.png',
    };
    final p = Project.fromJson(json);
    expect(p.thumbnailVersion, 0);
    expect(p.thumbnailVersion < Project.currentThumbnailVersion, isTrue);
  });
}
