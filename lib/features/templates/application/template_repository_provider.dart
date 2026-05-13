import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/combined_template_repository.dart';
import '../domain/template.dart';

final combinedTemplateRepositoryProvider = Provider<CombinedTemplateRepository>(
  (ref) => CombinedTemplateRepository(),
);

final combinedTemplatesProvider = FutureProvider.family<List<Template>, String>(
  (ref, titleLocale) async {
    final repository = ref.watch(combinedTemplateRepositoryProvider);
    return repository.loadTemplates(titleLocale: titleLocale);
  },
);

final effectiveTemplatesProvider = Provider.family<List<Template>, String>((
  ref,
  titleLocale,
) {
  final combinedTemplates = ref.watch(combinedTemplatesProvider(titleLocale));
  // Normal runtime is asset-only. Loading/error states intentionally expose an
  // empty list so Home, Browse, and onboarding can render their existing empty
  // states without falling back to deprecated Dart templates.
  return combinedTemplates.maybeWhen(
    data: (templates) => templates,
    orElse: () => const <Template>[],
  );
});
