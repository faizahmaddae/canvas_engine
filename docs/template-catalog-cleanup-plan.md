# TemplateCatalog Cleanup Plan

Date: 2026-05-12

## Scope

This tracks the staged cleanup of `TemplateCatalog`. The final runtime cleanup
removes normal production fallback to legacy Dart templates without deleting
`TemplateCatalog`, changing Home, Browse, editor, canvas engine,
`DocumentCodec`, template IDs, categories, languages, routes, or metadata.

Current template state:

| Metric | Count |
| --- | ---: |
| JSON asset templates | 53 |
| Ready templates | 53 |
| Needs minor polish | 0 |
| Needs major polish | 0 |
| Should be redesigned later | 0 |
| Legacy TemplateCatalog templates | 51 |
| Legacy-only templates | 0 |
| Asset-only templates | 2 |

## Current Architecture

The normal production source of starter documents is now the JSON asset catalog:

1. JSON asset templates under `assets/templates/`, listed in
    `assets/templates/manifest.json` and loaded by `AssetTemplateRepository`.

Legacy Dart templates still exist in `TemplateCatalog.all`, defined in
`lib/features/templates/domain/template_catalog.dart`, but normal runtime
providers no longer read them.

`AssetTemplateRepository` reads the manifest, parses each `template.json`, reads
the linked `document.json`, decodes it through `DocumentCodec`, and returns
`Template` objects whose `build` callback decodes a fresh document each time.
Asset-backed templates also carry `thumbnailPath` for raster thumbnails.

`CombinedTemplateRepository` defaults to asset-only. It still accepts an
explicit `legacyTemplates` list for migration/audit tests. When explicit legacy
fixtures are supplied, it loads asset templates first, then walks that legacy
list:

- if an asset template has the same ID as a legacy template, the asset wins;
- a duplicate warning is recorded for every legacy ID replaced by an asset;
- explicit legacy templates without asset replacements remain in the result;
- asset-only templates are appended after the legacy-order pass.

Because the production provider supplies no legacy list, the production catalog
is the 53-template JSON asset manifest. Asset-load failures produce an explicit
safe empty list/empty state instead of silently showing old Dart templates.

Home, Browse, and onboarding preview screens do not read `TemplateCatalog`
directly. They read `effectiveTemplatesProvider`, which returns asset-backed
templates once available and returns an empty list during loading/error states.

## Why TemplateCatalog Still Exists

`TemplateCatalog` now exists for three reasons:

1. It preserves migration comparison coverage: tests still verify every migrated
   JSON template replaces the legacy object for the same ID.
2. It preserves legacy fallback coverage in the migration audit while that
  report still compares asset and legacy catalogs.
3. It keeps the old Dart definitions available until deletion criteria are met.

It no longer owns production catalog content and is not a normal runtime safety
net. All visible templates are available as JSON assets, and the asset catalog
is the source of truth for current thumbnail quality and metadata.

## Remaining References

### Production UI

No production UI reads `TemplateCatalog` directly. Template data paths now go
through providers:

- `lib/features/home/presentation/home_screen.dart` watches
  `effectiveTemplatesProvider`.
- `lib/features/templates/presentation/templates_browse_screen.dart` watches
  `effectiveTemplatesProvider` unless explicit test/demo templates are injected.
- `lib/features/onboarding/presentation/screens/welcome_screen.dart` watches
  `effectiveTemplatesProvider` and resolves its showcase IDs from that source.
- `lib/features/onboarding/presentation/screens/goal_screen.dart` watches
  `effectiveTemplatesProvider` and resolves goal card template IDs from that
  source.
- `lib/features/onboarding/presentation/screens/ready_screen.dart` watches
  `effectiveTemplatesProvider` and resolves selected-category preview IDs from
  that source.

### Repository And Provider Runtime Path

- `lib/features/templates/application/template_repository_provider.dart`
  creates `CombinedTemplateRepository()` with no legacy list.
- `lib/features/templates/application/template_repository_provider.dart`
  returns `const <Template>[]` from `effectiveTemplatesProvider` while asset
  templates are loading or unavailable.
- `lib/features/templates/data/combined_template_repository.dart` defaults to an
  empty legacy list and does not import `TemplateCatalog`.
- `lib/features/templates/data/combined_template_repository.dart` can still use
  an explicitly supplied `legacyTemplates` list for migration/audit tests.

### Tests

- `test/editor/templates/template_catalog_phase_a_test.dart` validates legacy
  catalog categories, languages, and dimensions.
- `test/editor/templates/template_system_audit_test.dart` compares legacy and
  asset catalogs, verifies duplicate replacement warnings, and locks the
  generated system audit report.
- `test/editor/templates/migrated_template_assets_test.dart` verifies migrated
  asset documents/thumbnails and confirms migrated JSON templates replace legacy
  objects.
- `test/onboarding/onboarding_flow_test.dart` contains a negative guard that
  asserts production template UI does not import or reference `TemplateCatalog`.

`test/editor/templates/combined_template_repository_test.dart`,
`test/home/combined_template_source_test.dart`, `test/home/templates_section_test.dart`,
`test/home/document_thumbnail_test.dart`, and
`test/widget/persian_export_verification_test.dart` now use asset-backed or
local fixture data instead of `TemplateCatalog`.

## Final Deletion Audit - Completed 2026-05-12

### Reference Classification

| Reference | Classification | Recommendation |
| --- | --- | --- |
| `lib/features/templates/domain/template_catalog.dart` | Catalog definition | Should remain until the final deletion commit. |
| `lib/features/templates/domain/template.dart` doc comment | Documentation/history only | Safe to remove in the final deletion commit. |
| `test/editor/templates/template_system_audit_test.dart` | Required for migration/audit comparison | Should remain until the generated audit report is redesigned as asset-only. |
| `docs/template-system-audit.md` | Documentation generated by migration/audit comparison | Should remain until the audit generator no longer reports legacy counts/replacements. |
| `test/editor/templates/migrated_template_assets_test.dart` | Required for migration/audit comparison | Should remain until the team retires the legacy-vs-asset replacement proof. |
| `test/editor/templates/template_catalog_phase_a_test.dart` | Legacy catalog self-test | Should remain only until the same commit that deletes `TemplateCatalog`. |
| `test/onboarding/onboarding_flow_test.dart` negative guard | Documentation/safety test | Safe to keep now; update or remove when the catalog file is deleted. |

### Delete-Now Assessment

Do not delete `TemplateCatalog` in this audit phase. The production runtime is
ready for deletion, but the migration/audit layer is still intentionally using
the legacy catalog as its comparison baseline. Deleting it now would require
redesigning the audit report and retiring migration-proof tests in the same
change, which is larger than this audit-first phase.

The catalog should stay temporarily for migration/audit tests only. It is no
longer needed for Home, Browse, onboarding, repository defaults, production
fallback, Persian export verification, or generic repository fixture coverage.

### Final Deletion Checklist

1. Rewrite `test/editor/templates/template_system_audit_test.dart` and
   `docs/template-system-audit.md` as an asset-only audit: keep manifest
   uniqueness, localized-title, metadata, document decode, thumbnail existence,
   and thumbnail aspect checks; remove legacy counts, replacement IDs,
   duplicate legacy/asset warning assertions, and real-catalog fallback checks.
2. Rewrite or remove the legacy replacement assertion in
   `test/editor/templates/migrated_template_assets_test.dart`; keep the
   asset-only metadata, document decode, thumbnail, and fresh-document checks.
3. Delete `test/editor/templates/template_catalog_phase_a_test.dart` together
   with `lib/features/templates/domain/template_catalog.dart`.
4. Remove the `TemplateCatalog` doc-comment reference from
   `lib/features/templates/domain/template.dart`.
5. Run a full `TemplateCatalog|template_catalog.dart` search across `lib/`,
   `test/`, and `docs/`; only this cleanup plan should mention the historical
   deletion after the final commit.
6. Run focused template/Home/onboarding tests, `flutter analyze`, and the full
   test suite after the deletion commit.

### Sample, Dev, And Migration Tooling

No standalone sample/dev utility or generation script currently references
`TemplateCatalog`. The remaining migration-tooling role is test-based:
`template_system_audit_test.dart` and `migrated_template_assets_test.dart` use
the catalog as a comparison baseline for migrated IDs.

### Documentation

- `docs/template-system-audit.md` is generated from `TemplateCatalog.all` and
  `assets/templates/manifest.json`.
- This cleanup plan records the post-migration role of the catalog and the
  recommended removal path.

## CombinedTemplateRepository Behavior Audit

### Asset JSON Preference

Assets are the default result. When an explicit legacy list is supplied, assets
are preferred over legacy objects when IDs collide. The repository builds an
asset map by ID, walks the explicit legacy list in order, and inserts the asset
template instead of the legacy template for any matching ID. This keeps the
migration comparison behavior while making JSON the selected implementation.

### Duplicate ID Handling

Legacy/asset duplicate IDs are intentional only in migration/audit tests that
explicitly pass legacy templates. They produce warnings such as `Duplicate
template id "..." found in asset and legacy catalogs; using the asset template.`
Tests expect one warning per migrated legacy ID in those explicit scenarios.

Duplicate IDs inside the asset manifest itself are not resolved by
`CombinedTemplateRepository`; they are treated as an audit invariant. The
system audit currently verifies there are no duplicate asset IDs in the
manifest. Now that the catalog fallback is removed from normal runtime, this
invariant stays tested near the asset repository and manifest tests.

### Legacy Fallback

For non-schema, non-document-decode asset loading failures, the repository warns
and returns the configured legacy list only when one was explicitly supplied. In
normal runtime there is no configured legacy list, so the result is empty and UI
empty states handle the condition safely.

Explicit legacy fallback no longer provides complete catalog parity:

- it can cover the 51 migrated legacy IDs;
- it cannot cover the 2 asset-only templates;
- it does not include the current polished JSON document or raster-thumbnail
  source for any migrated template.

### Error Handling

`FormatException` and `DocumentDecodeException` are rethrown. This means invalid
template metadata, unknown category/language IDs, unsupported schema versions,
or invalid `document.json` files are treated as real data errors rather than
silently falling back to legacy templates.

The provider layer returns an empty list while combined templates are loading or
unavailable. Home, Browse, and onboarding already handle empty lists safely.

### Is Fallback Still Useful?

Fallback remains useful only as an explicit test/migration hook. It is no longer
a normal runtime safety net or content-authoring path because every production
template has a JSON asset and the two asset-only templates have no legacy
equivalent.

## Risks Of Deleting TemplateCatalog Immediately

1. Migration audit tests would lose their baseline for proving that migrated
   JSON assets replaced all legacy IDs.
2. The generated `docs/template-system-audit.md` still reports legacy counts and replacement status.
3. `test/editor/templates/template_catalog_phase_a_test.dart` is still a catalog-specific self-test and should disappear with the catalog itself.
4. The legacy catalog comments and tests still document old assumptions; a hard
   delete without a staged cleanup would make failures harder to interpret.

## Recommended Strategy

Recommendation: delete later in a dedicated final deletion commit after the
migration audit is converted to asset-only.

JSON assets are now the production source of truth. The remaining work is to
replace the remaining legacy-specific audit fixtures, update generated audit
reporting, and then delete `TemplateCatalog` in a dedicated removal phase.

## Phased Cleanup Path

### Phase 1: Deprecation And Ownership Markers - Implemented 2026-05-11

- `TemplateCatalog` is documented as a deprecated legacy Dart catalog.
- Stale comments that described Dart templates as the primary production catalog
  were updated to point to JSON assets as the source of truth.
- The deprecation was implemented with comments rather than Dart `@Deprecated`
  annotations so intentional transitional references continue to analyze cleanly
  until production/test call sites move.
- `CombinedTemplateRepository` behavior remains unchanged.
- Existing IDs, categories, languages, routes, metadata, manifest entries, and
  JSON assets remain unchanged.

### Phase 2: Move Onboarding To Asset-Backed Templates - Implemented 2026-05-11

- Welcome, Goal, and Ready onboarding preview screens now resolve the same
  template IDs through `effectiveTemplatesProvider`.
- The direct production UI imports/references to `TemplateCatalog` were removed
  from onboarding.
- The same onboarding template IDs, layouts, visual intent, routes, metadata,
  manifest entries, and `CombinedTemplateRepository` behavior are preserved.
- Goal cards fall back to an existing static preview if a requested provider
  template is unavailable, so loading/fallback states do not crash.

### Phase 3: Move Legacy Access Behind Dev/Test Fixtures - Implemented 2026-05-12

- Production providers no longer expose `TemplateCatalog.all` as fallback.
- Remaining catalog access is limited to tests and migration/audit coverage.
- Home/Browse/onboarding loading and error states use asset-backed empty-state
  behavior rather than legacy Dart templates.
- Manifest uniqueness, metadata validation, document decoding, thumbnail aspect,
  and localized-title tests remain intact.

### Phase 4: Remove Runtime Fallback - Implemented 2026-05-12

- `CombinedTemplateRepository` is asset-only by default while retaining an
  explicit `legacyTemplates` constructor parameter for tests/audits.
- Duplicate legacy/asset warning expectations were removed from the default
  runtime path and kept only where legacy fixtures are explicitly supplied.
- Asset-manifest duplicate ID tests remain the primary runtime uniqueness guard.

### Phase 5: Delete Legacy Dart Templates

- Delete `TemplateCatalog` and legacy document builder code.
- Replace catalog-based tests with asset-backed fixtures where coverage is still
  valuable.
- Update `docs/template-system-audit.md` so it no longer reports legacy counts.
- Remove migration-only tests once their assertions are represented by stable
  asset-catalog tests.

## Proposed Next Implementation Step

Prepare the deletion phase, but do not delete `TemplateCatalog` yet:

1. Update `docs/template-system-audit.md` and its generator so legacy counts are
   optional or removed once migration comparison is no longer needed.
2. Retire the legacy replacement proof in `test/editor/templates/migrated_template_assets_test.dart` once the audit report no longer compares against Dart templates.
3. Delete `lib/features/templates/domain/template_catalog.dart` and `test/editor/templates/template_catalog_phase_a_test.dart` in a dedicated final removal change, then remove the `TemplateCatalog` doc comment from `lib/features/templates/domain/template.dart`.
