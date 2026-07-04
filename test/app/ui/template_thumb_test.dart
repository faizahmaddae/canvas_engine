import 'package:canvas_engine/app/theme/app_theme.dart';
import 'package:canvas_engine/app/theme/app_tokens.dart';
import 'package:canvas_engine/app/ui/template_thumb.dart';
import 'package:canvas_engine/features/editor/engine/core/editor_document.dart';
import 'package:canvas_engine/features/templates/domain/template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Template _template({required String id, required TemplateCategory category}) {
  return Template(
    id: id,
    name: id,
    category: category,
    language: TemplateLanguage.english,
    build: () => EditorDocument(
      width: 200,
      height: 200,
      layers: const [],
      backgroundColor: const Color(0xFFF5EFE6),
    ),
  );
}

void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('renders the template name', (tester) async {
    final template = _template(
      id: 't1',
      category: TemplateCategory.promotionalPoster,
    );
    await tester.pumpWidget(host(TemplateThumb(template: template)));
    expect(find.text('t1'), findsOneWidget);
  });

  testWidgets('promotionalPoster fills with brand', (tester) async {
    final template = _template(
      id: 't1',
      category: TemplateCategory.promotionalPoster,
    );
    await tester.pumpWidget(host(TemplateThumb(template: template)));
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, AppTokens.light.brand);
  });

  testWidgets('instagramStory fills with rose', (tester) async {
    final template = _template(
      id: 't2',
      category: TemplateCategory.instagramStory,
    );
    await tester.pumpWidget(host(TemplateThumb(template: template)));
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, AppTokens.light.rose);
  });

  testWidgets('quote fills with saffron', (tester) async {
    final template = _template(id: 't3', category: TemplateCategory.quote);
    await tester.pumpWidget(host(TemplateThumb(template: template)));
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, AppTokens.light.saffron);
  });

  testWidgets('youtubeThumbnail fills with teal', (tester) async {
    final template = _template(
      id: 't4',
      category: TemplateCategory.youtubeThumbnail,
    );
    await tester.pumpWidget(host(TemplateThumb(template: template)));
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, AppTokens.light.teal);
  });

  testWidgets('renders without throwing in dark mode', (tester) async {
    final template = _template(
      id: 't1',
      category: TemplateCategory.promotionalPoster,
    );
    await tester.pumpWidget(
      host(TemplateThumb(template: template), brightness: Brightness.dark),
    );
    expect(tester.takeException(), isNull);
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final decoration = box.decoration as BoxDecoration;
    // Category accents stay fixed across brightness.
    expect(decoration.color, AppTokens.dark.brand);
    expect(decoration.color, AppTokens.light.brand);
  });
}
