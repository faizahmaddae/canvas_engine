// What a saved project looks like, wherever it is shown.
//
// The Home rail and the Projects grid had two different answers. The
// grid live-rendered the document when its cached PNG was missing or
// stale; the rail did not, and fell through to the EMPTY-DESIGN mark
// instead — so a project with a photo and a headline in it announced
// itself on Home as an empty design while the same document rendered
// correctly one tab away. Both now share [ProjectPreview].

import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:canvas_engine/features/editor/engine/rendering/document_thumbnail.dart';
import 'package:canvas_engine/features/editor/engine/serialization/document_codec.dart';
import 'package:canvas_engine/features/home/domain/project.dart';
import 'package:canvas_engine/features/home/presentation/widgets/project_thumb.dart';
import 'package:canvas_engine/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A real one-layer document, encoded by the codec itself rather
  // than hand-written — a hand-written envelope that fails to decode
  // would make these tests pass through the corrupt-JSON branch and
  // prove nothing.
  final withContent = DocumentCodec.encode(
    EditorDocument(
      width: 1080,
      height: 1350,
      layers: [
        const ShapeLayer(
          id: 's1',
          kind: ShapeKind.rectangle,
          transform: LayerTransform(
            position: Offset(100, 100),
            size: Size(400, 300),
          ),
          fillColor: Color(0xFFFF0000),
        ),
      ],
    ),
  );

  Project project({
    String? documentJson,
    String? thumbnailPath,
    int thumbnailVersion = Project.currentThumbnailVersion,
  }) {
    final now = DateTime(2026, 7, 25);
    return Project(
      id: 'p1',
      name: 'طرح من',
      width: 1080,
      height: 1350,
      createdAt: now,
      lastModified: now,
      documentJson: documentJson ?? withContent,
      thumbnailPath: thumbnailPath,
      thumbnailVersion: thumbnailVersion,
    );
  }

  Future<void> pump(WidgetTester tester, Project p) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('fa'),
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 110,
                height: 140,
                child: ProjectPreview(project: p),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a real document with no PNG live-renders, it does not claim '
      'to be empty', (tester) async {
    await pump(tester, project());
    expect(tester.takeException(), isNull);

    expect(
      find.byType(EmptyDesignPlaceholder),
      findsNothing,
      reason: 'this project has a layer in it',
    );
    expect(find.byType(DocumentThumbnail), findsOneWidget);
  });

  testWidgets('a stale PNG is ignored in favour of the document', (
    tester,
  ) async {
    // Version 0 baked an opaque white backdrop, so it would
    // mis-represent a coloured or transparent canvas.
    await pump(
      tester,
      project(thumbnailPath: '/nonexistent/thumb.png', thumbnailVersion: 0),
    );
    expect(find.byType(DocumentThumbnail), findsOneWidget);
    expect(find.byType(EmptyDesignPlaceholder), findsNothing);
  });

  testWidgets('a genuinely empty document keeps the empty-design mark', (
    tester,
  ) async {
    await pump(tester, project(documentJson: '{"layers":[]}'));
    expect(find.byType(EmptyDesignPlaceholder), findsOneWidget);
    expect(find.byType(DocumentThumbnail), findsNothing);
    expect(find.text('طرح من'), findsOneWidget);
  });

  testWidgets('undecodable JSON falls back to an icon, not a blank box', (
    tester,
  ) async {
    await pump(tester, project(documentJson: 'not json at all'));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('the rail thumb renders the same preview as the grid', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('fa'),
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ProjectThumb(project: project(), onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ProjectPreview), findsOneWidget);
    expect(find.byType(EmptyDesignPlaceholder), findsNothing);
  });
}
