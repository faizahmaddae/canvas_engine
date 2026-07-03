# Editor, Engine, Core, and UX Audit

Date: 2026-05-13

Scope: code-based audit of the real editor experience and core engine quality. No app redesign or large implementation work was performed. No changes were made to `DocumentCodec`, editor engine behavior, templates, Home/Browse, or routes.

Priority rubric:

- P0: blocks real user editing.
- P1: important for MVP.
- P2: polish / nice to have.
- P3: future advanced feature.

## Executive summary

No confirmed P0 blocker was found from the code audit. The editor can create documents, add/edit text, images, stickers, shapes, paint strokes, crop photos, adjust/filter images, manipulate layers, save projects, and export PNG/JPG. The core engine architecture is much stronger than a typical early editor: document and layer models are immutable, commands are pure and undoable, serialization has explicit schema handling, live gestures avoid 60 fps document writes, and export uses the same `DocumentView` path as on-screen document rendering.

The weak points are less about missing raw capability and more about MVP trust and discoverability. Important actions are scattered across the app bar overflow, floating toolbars, contextual `More` sheets, and the layers drawer. Several advanced engine pieces already exist but are not surfaced clearly in the UI. Export is mostly sound, but saved project thumbnails have a likely background-fill parity gap for gradient documents because `ProjectSaveService` passes only a legacy solid `background` to `DocumentPngExporter.export`, not `backgroundFill: doc.background`. Pixel-output testing exists, but true visual/golden coverage and runtime/manual UX inspection are still thin.

Top audit conclusions:

- [P1] The editor is viable for MVP editing, but the first implementation phase should focus on usability, not new engine concepts.
- [P1] The engine and command layer are a solid foundation; protect them with more visual/export/round-trip tests before widening features.
- [P1] Save/export, edit text, duplicate, reorder, opacity, alignment, and multi-select features need clearer routes.
- [P1] Export/rendering parity needs one small fix pass around saved thumbnails and more automated visual verification.
- [P2] Persian/RTL support is real but heuristic; mixed-script editing and visual verification need deeper treatment.
- [P2] Many "missing" editor features are actually present but hidden, partially exposed, or not connected to a first-class workflow.

## What is working well

- The three-layer architecture is mostly respected: engine code owns data/math/render contracts, application controllers dispatch commands, and presentation widgets capture gestures and chrome.
- `EditorDocument` is immutable, stores layers in z-order, and handles project-level concerns such as canvas size, background fill/mode, project kind, and base photo id.
- `EditorLayer` has a useful shared contract: transform, visibility, lock, opacity, capabilities, common JSON, and effect stack parsing.
- `TextLayer`, `ImageLayer`, `ShapeLayer`, and `PaintLayer` preserve subclass fields through copy/transform helpers, which is critical for non-destructive editing.
- Command architecture is strong. Commands are pure, invert against the pre-apply document, and history supports merging and byte-budget eviction.
- Gesture architecture is unusually mature. `InteractionController` stages live transforms, commits one command on release, rebases pointer-count transitions, supports group transform sessions, and avoids document churn during drag.
- Snap/alignment math is engine-only and testable. `SnapEngine`, `GroupEngine`, and `AlignmentEngine` are pure data-in/data-out modules.
- Text editing has broad style support: font family, size, weight, italic, underline, letter spacing, line height, alignment, color, shadow, outline, background, padding/radius, and resize modes.
- Image editing is more complete than a basic MVP: source replacement, masks, crop, border, shadow, adjustments, effects, and filter previews are present.
- Shape editing supports a useful primitive catalog, solid/gradient fills, stroke, corner radius, shadow, and resize behavior.
- Crop flow is technically careful: image crop reshapes the layer, photo projects can resize the canvas, and the crop command avoids stretching after commit.
- `DocumentCodec` has explicit schema versions, v1/v2/v3 handling, forward-compatible unknown effect support, and corpus byte-identity tests.
- `DocumentView` is the right single source for document pixels: background plus visible layers, no chrome, no viewport transform.
- Export flow is mostly coherent: PNG/JPG share rasterization, PNG is tagged as sRGB, output pixels are capped, JPG encoding is offloaded to an isolate, and the preview reuses the exact bytes to be saved/shared.
- Autosave avoids expensive thumbnail rendering and marks stale thumbnails so Home can live-render when needed.
- The test suite is broad for engine math, serialization, command behavior, export basics, gestures, templates, and several widget flows.

## Major UX problems

Top 10 UX problems:

1. [P1] Save/export are not primary enough. They live behind overflow and a modal/preview flow, while a real editor user expects a clear persistent path to save/share.
2. [P1] Text content editing is hidden compared with direct canvas expectations. Text can be edited through a flow/sheet, but selected text does not behave like a directly editable WYSIWYG text box.
3. [P1] The selected-layer gesture model blocks viewport pan/zoom until the user deselects. This is powerful for object transforms, but beginners can feel trapped when they want to inspect another canvas area.
4. [P1] Core layer actions are scattered. Duplicate, delete, reorder, lock, opacity, and visibility appear across floating quick actions, `More`, app bar buttons, and the layers drawer.
5. [P1] Multi-select is powerful but under-discoverable. Long-press and group transform behavior exist, but there is no obvious beginner-facing affordance for selecting multiple objects.
6. [P1] Alignment/distribution has engine and application support but no visible production UI entry point found in the editor presentation layer.
7. [P1] Hit testing is bbox-based for rotated/irregular content. Overlapping objects can be cycled, but precise shape/path/image-mask selection is not there yet.
8. [P2] Only three resize corner handles are visible because top-right is the rotate handle. This may be learnable, but it is asymmetric compared with common editors that separate rotate from four-corner resize.
9. [P2] The bottom dock is dense. Tool coverage is impressive, but first-time users may not know which mode owns the operation they want.
10. [P2] Opacity and some layer metadata actions are hidden in secondary surfaces. The layers drawer exposes opacity, but the main selected-layer flow does not make it feel like a first-class control.

Additional UX observations:

- [P1] New users may not understand the difference between image adjustment, filters, and effects because these are separate slots with overlapping mental models.
- [P1] Crop is technically solid but should be manually validated on device for discoverability, especially entry/exit, cancel/done, and base-photo behavior.
- [P2] The editor has many good tooltips/semantic labels, but not every custom control is proven by accessibility tests.
- [P2] The app relies on hidden/pro gestures such as multi-finger undo/redo and long-press multi-select; those are helpful shortcuts, not substitutes for visible controls.

## Major engine/core risks

Top 10 engine/core risks:

1. [P1] Saved project thumbnail parity risk: `ProjectSaveService` calls `DocumentPngExporter.export` with only `background: DocumentThumbnail.backgroundFor(doc)`. Gradient backgrounds can flatten to a representative solid color instead of rendering `doc.background` unless `backgroundFill` is passed.
2. [P1] Pixel-output regression risk: export and document rendering are central, but tests mostly check dimensions, non-empty bytes, and focused pixel behavior rather than comprehensive visual parity.
3. [P1] Image source failure handling is weak. `ImageSource.fromJson` validates shape, but file existence, URL reachability, asset loading failures, and graceful placeholders are not guaranteed by the layer model.
4. [P1] Hit testing does not use real paths/masks. Selection uses rotated/AABB style geometry, while shapes and masks already have path helpers that could support more accurate selection.
5. [P1] Effects and image adjustments are mature enough to need stronger render contract tests. The effect docs define sRGB behavior, but wide-gamut/HDR/linear-light changes would be risky without golden-like baselines.
6. [P1] UI feature exposure lags engine capability. Alignment/distribution, layer naming, and some layer controls have model/controller support but are not consistently visible.
7. [P1] Runtime memory pressure remains a real risk on low-end devices. The engine caps export pixels and caches, but large images plus effects plus JPG conversion still deserve profiling on target Android hardware.
8. [P2] `DocumentView` has a safe modern `backgroundFill` path, but its legacy white `background` default makes caller omissions easy. New render callers must be audited to always pass the document fill.
9. [P2] Group resize intentionally uses uniform scale for correctness with rotated children. This is mathematically sound, but users may expect free group resize; the UX needs to communicate the constraint.
10. [P2] Engine constants are centralized, but some application/presentation thresholds and timings should be periodically audited so new magic numbers do not leak outside `EngineConstants`.

Additional technical risks:

- [P1] There was no runtime/manual inspection in this audit pass, so code correctness has not been matched against actual device feel.
- [P1] `ProjectStore` uses a single SharedPreferences JSON list. This is acceptable for MVP scale, but it becomes fragile for many large projects, corruption recovery, and partial writes.
- [P2] Autosave skips thumbnail rendering by design and marks stale thumbnails, which is good, but users can still see live-render vs cached-PNG differences if the manual thumbnail path drifts.
- [P2] Locked/protected base-photo rules appear well covered, but all new layer actions must continue to route through shared guards to avoid bypassing protection.

## Missing editor features

This section separates truly missing features from features that are present but hidden or partial.

Top 10 missing, hidden, or partial features:

1. [P1] Direct WYSIWYG text editing on canvas is missing. Text content editing exists, but it is sheet/flow-driven rather than direct in-place editing.
2. [P1] Visible alignment and distribution controls are missing from production UI, despite `AlignmentEngine` and `AlignmentController` existing.
3. [P1] A unified selected-layer action panel is missing. Users need one obvious place for duplicate, delete, reorder, lock, opacity, rename, align, and layer info.
4. [P1] Layer rename UI and command path are missing or not surfaced, even though layers carry an optional `name` field.
5. [P1] Precise path/mask hit testing is missing. Shape outline paths and image masks exist, but selection does not use them as the primary hit target.
6. [P1] Image failure placeholders/relink workflow are missing. Broken file/network/asset sources should be visible and recoverable.
7. [P2] Full layer opacity is present in the model and layers drawer but is not broadly surfaced as a contextual editing tool.
8. [P2] General layer masks/clipping groups are missing as a user-facing feature. Image masks exist; cross-layer masks are a future design-tool capability.
9. [P2] Blend modes are missing as a user-facing layer property. This is important for design/photo compositing but can wait until MVP basics are clearer.
10. [P3] Advanced pro features are missing: group/ungroup as persistent document entities, editable vector paths, boolean shape operations, adjustment layers, reusable styles, asset library, keyboard shortcuts, and collaborative/history timelines.

Feature status highlights:

- Present: text styles, image crop, image adjustments, image filters, image effects, shape styles, paint strokes, layer visibility/lock/delete/reorder, export preview, autosave, recent project thumbnails.
- Present but hidden/fragmented: duplicate, reorder, opacity, text content edit, multi-select, advanced image effects, crop entry, save/export.
- Engine/application present but UI not found: alignment/distribution.
- Model field present but workflow not found: layer naming.
- Future advanced: blend modes, general masks, persistent groups, adjustment layers, vector path editing.

## Persian/RTL gaps

What is working:

- Persian locale and RTL app flows have tests in app/settings/onboarding/home areas.
- Text content uses Arabic-script detection and `textDirectionForContent` to choose RTL/LTR for rendered text.
- Persian defaults are considered in font choice, including tests that prefer Vazir for Persian content.
- Persian export verification exists and writes representative PNGs for human inspection.

Gaps and issues:

1. [P1] Persian/RTL export verification is not fully automated visually. The current representative test proves valid PNG output and dimensions, but comments acknowledge that glyph joining and bidi flow still need human eyeballing.
2. [P1] Mixed-script direction uses a dominance heuristic, not a first-strong Unicode bidi algorithm. Mixed Persian/English strings can flip direction based on counts rather than author intent.
3. [P1] Text editing UX for Persian needs manual device validation: keyboard behavior, cursor movement, selection handles, multiline entry, numbers, punctuation, and line wrapping.
4. [P2] There is no obvious per-text-layer direction override in the audited UI. Users may need to force RTL/LTR when heuristics are wrong.
5. [P2] Persian typography controls should be validated beyond font family: line height, letter spacing, outline, shadow, background padding, and text resize modes can all expose shaping/wrapping edge cases.
6. [P2] Ambient app RTL and document text direction are separate concerns. The export host forces ambient LTR and relies on each `TextLayer` self-directing; this is reasonable but should stay covered by regression tests.
7. [P2] Persian template quality appears heavily tested at metadata/catalog level, but editor editing flows for Persian user-created text need more widget/device coverage.
8. [P3] Advanced RTL typography features are not in scope yet: kashida, OpenType feature control, language-specific numeral shaping, per-span direction, and rich-text runs.

## Export/rendering accuracy

What is working:

- `DocumentView` excludes editor chrome and renders visible layers in document order.
- PNG and JPG share the same off-screen `DocumentView` rasterization path.
- `ExportController` correctly passes `doc.background` as `backgroundFill` for normal export.
- PNG export honors transparent canvas mode and tags output as sRGB.
- JPG export flattens to an opaque image and encodes off-thread.
- Export preview uses the exact bytes that Save/Share will commit.
- Output sizes are capped to avoid giant `toImage` allocations.

Accuracy issues and risks:

1. [P1] Saved project thumbnails can drift from editor/export for gradients because `ProjectSaveService` does not pass `backgroundFill: doc.background` to `DocumentPngExporter.export`.
2. [P1] There is no full visual parity test that compares editor `DocumentView`, saved thumbnail, PNG export, JPG export, and Home live thumbnail for the same gradient/transparent/effects document.
3. [P1] Pixel tests exist, but no durable golden workflow is in place for common editor compositions. The current stance avoids platform-fragile goldens, but a small deterministic visual smoke suite is still needed.
4. [P1] External image loading failures can affect export output without a clear recovery path.
5. [P2] PNG output is tagged sRGB, but effects operate in sRGB Flutter color space. This is acceptable now; future wide-gamut/HDR support must be a coordinated engine/export change.
6. [P2] JPG composite behavior around transparent documents should be explicitly documented in the user-facing export UI so users understand flattening.
7. [P2] Target-size export letterboxes with a solid background. That is correct for contain-fit presets, but user expectations for transparent PNG preset exports should be tested.

## Performance concerns

1. [P1] Export remains the highest-risk performance path. Even with pixel caps, off-screen `toImage`, raw RGBA conversion, PNG/JPG encoding, and effects can create high transient memory pressure.
2. [P1] Large source images are rendered through Flutter image widgets with cache sizing, but the end-to-end behavior on mid/low Android devices needs profiling.
3. [P1] Effects, adjustments, shadows, blur, masks, and paint layers can stack. Cache budgets exist, but real-world memory/latency traces are needed before increasing feature complexity.
4. [P1] `ProjectStore` stores all projects as one JSON list in SharedPreferences. This is simple and testable, but many projects or large document JSON payloads could make Home reads/writes slow.
5. [P2] Live gesture architecture avoids committed document churn, which is excellent. Continue protecting this pattern when adding new tools.
6. [P2] Autosave debouncing and stale-thumbnail marking are good. Manual save still renders a thumbnail on the UI path and should stay fast for large documents.
7. [P2] The editor surface has many overlays and selectors. Existing `select` usage helps, but more runtime profiling is needed around heavy documents with group selection and open panels.
8. [P3] Future video/animation/design-tool features will need a stronger render cache and possibly a non-widget export compositor.

## Test coverage gaps

What is covered well:

- Engine serialization, schema fixtures, unknown effects, command merge, history memory budget, layer copy contracts, snap/spacing/alignment/group/interaction math.
- Editor application flows for text, image, crop, canvas background, project kind, base-photo protection, autosave, viewport store, entry flows.
- Widget flows for gestures, selection handles, overlap selection, multi-select, export background, PNG/JPG basics, export preview, Persian export smoke verification.
- Template metadata/catalog/system quality and Home/template RTL behavior.

Gaps and issues:

1. [P1] No test currently locks the saved-project thumbnail gradient path that likely regressed/risks drift in `ProjectSaveService`.
2. [P1] No broad visual parity suite covers `DocumentView` vs export vs thumbnail for gradients, transparent backgrounds, text, masks, effects, and hidden layers together.
3. [P1] No automated test proves Persian glyph joining/bidi visual correctness; existing comments explicitly leave final verification to humans.
4. [P1] No tests found for graceful broken image rendering/relink behavior.
5. [P1] Alignment/distribution engine and controller are tested, but no production UI test exists because no UI entry was found.
6. [P1] Hit testing tests cover overlap/cycling, but not precise path/mask hit areas.
7. [P2] Accessibility tests are partial. Some semantic labels/tooltips are tested, but the whole editor tool surface is not covered.
8. [P2] Runtime/manual UX testing on device is missing from this audit. Gesture feel, dock density, crop flow, export flow, and Persian keyboard behavior need direct inspection.
9. [P2] Performance tests are absent for large documents, effect stacks, high-resolution export, and many saved projects.
10. [P2] Golden tests are intentionally avoided in some effect tests due to platform fragility, but the project still needs a smaller deterministic pixel/visual regression strategy.

Suggested focused tests before/with implementation:

- [P1] Project save thumbnail preserves linear/radial gradient backgrounds by passing `backgroundFill`.
- [P1] One mixed document visual parity test: gradient background, text, masked image, shape, hidden layer, effect stack, transparent mode toggle.
- [P1] Broken file/network/asset image layer renders a clear placeholder and exports deterministically.
- [P1] Persian mixed-script text render smoke test with known strings and fonts.
- [P1] Production UI test for alignment/distribution once controls are surfaced.
- [P2] Accessibility/semantics scan for every main dock slot, floating toolbar action, and layers drawer action.
- [P2] Large export stress test around the device pixel cap and target-size clamp logic.

## Priority roadmap

Phase 1: Editor usability fixes

- [P1] Promote Save/Export to a clearer primary action path while preserving the existing export preview architecture.
- [P1] Make selected-layer actions coherent: one predictable surface for edit, duplicate, delete, reorder, lock, opacity, and layer info.
- [P1] Surface text content editing more directly for selected text layers.
- [P1] Add visible multi-select affordances and clearer group-selection feedback.
- [P1] Improve selected-layer vs viewport gesture discoverability so users can pan/zoom without feeling stuck.

Phase 2: Layer controls and toolbar completeness

- [P1] Surface alignment/distribution controls using the existing `AlignmentController`.
- [P1] Add or expose layer rename if names are intended to be user-facing.
- [P1] Bring opacity into the contextual selected-layer workflow, not only the layers drawer.
- [P2] Consolidate duplicate/reorder/lock/delete so the layers drawer and floating actions feel consistent.
- [P2] Consider separate rotate affordance vs four resize handles after device testing.

Phase 3: Text editing and Persian improvements

- [P1] Improve text editing discoverability and reduce modal friction for common edit-content flows.
- [P1] Add stronger Persian/RTL tests for mixed content, multiline wrapping, numerals, punctuation, and export.
- [P2] Consider explicit per-layer text direction override.
- [P2] Validate Persian typography controls with shipped fonts on device.
- [P3] Plan rich text and advanced typography only after the simpler text editing loop is solid.

Phase 4: Export/save reliability

- [P1] Fix saved thumbnail parity by ensuring project thumbnail export passes `backgroundFill: doc.background`.
- [P1] Add parity tests for gradient, transparent, and effects-heavy documents across editor/export/thumbnail.
- [P1] Add broken image placeholder/relink behavior and tests.
- [P1] Profile export memory/time on target Android devices.
- [P2] Document JPG flattening and target-size letterbox behavior in product copy.

Phase 5: Advanced design features

- [P2] Add blend modes only after layer controls are unified.
- [P2] Add general masks/clipping after selection and hit-testing precision improve.
- [P3] Add persistent groups, group/ungroup, reusable styles, and adjustment layers as deliberate engine/API phases.
- [P3] Add vector path editing and boolean operations when the editor shifts toward design-tool depth.
- [P3] Revisit export architecture if future video/animation/HDR requirements exceed widget-tree rasterization.

## Batch 4 follow-up: export/save reliability

Implemented after this audit:

- Saved-thumbnail parity now has stronger regression coverage for solid, gradient, and transparent canvas backgrounds through the same `DocumentView` / `DocumentThumbnail` path used by editor preview and export.
- Broken image sources now render a deterministic “Image unavailable” placeholder in the document render path, so missing asset/file/network images remain visible and PNG/JPG export does not crash or silently drop the layer.
- Export smoke coverage was broadened for hidden layers, shape layers, text layers, file-backed image layers, image filter pixels, transparent PNG alpha, JPG flattening, fixed-target size reduction guards, and autosave stale-thumbnail behavior.

Still deferred:

- A full relink workflow for missing images.
- Platform-stable golden baselines for complex effects-heavy documents.
- Device profiling for very large source images plus high-resolution export on low-end Android hardware.

## Batch 5 follow-up: image recovery and crop UX

Implemented after Batch 4:

- Broken image layers are now recoverable from visible editor surfaces. Selected image layers expose `Replace image`, and known-missing file sources expose `Relink image` with the existing unavailable-image context.
- Image replacement now uses one shared picker/persist/command flow across the image toolbar and selected-layer actions sheet, so replacing a photo preserves layer position, size, rotation, opacity, order, masks, filters, effects, border, and shadow.
- Replacement intentionally resets `cropRect` to the full image because a fractional crop from the old source usually points at the wrong region of the new source. Undo restores the previous source and crop together.
- Crop mode entry points now read as `Crop image`; the full-screen crop surface keeps obvious Cancel / Done controls and offers a Restore image action for returning the crop draft to the full image.
- Crop preview handles unavailable image sources without throwing, so broken layers remain recoverable instead of turning crop mode into a dead end.

Still deferred:

- A richer relink browser that can search previous import folders or project-relative media locations.
- Platform-stable golden baselines for complex effects-heavy documents.
- Device profiling for very large source images plus high-resolution export on low-end Android hardware.

## Batch 6 follow-up: performance profiling and export stress tests

Implemented after Batch 5:

- Export pixel-cap coverage now includes a deterministic very-large-canvas guard with an explicit max-pixel cap, proving oversized pixel-ratio requests reduce to a finite aspect-preserving scalar.
- Fixed target-size export clamping is now covered by a pure helper with deterministic max-pixel tests, so oversized PNG/JPG preset requests can be validated without allocating a huge raster in tests.
- Widget export stress coverage now mounts synthetic mixed documents with many shapes, text layers, hidden layers, opacity, gradient backgrounds, image masks, filters, adjustment effects, and vignette overlays, then verifies PNG bytes and output dimensions through the real `DocumentView` capture path.
- JPG stress coverage now encodes a higher-resolution captured document image and decodes it back to verify dimensions, keeping the encode path exercised without relying on device-sized fixtures.
- Transparent PNG stress coverage verifies uncovered pixels remain transparent while visible image/effect content still renders.
- Large image preview coverage now asserts oversized image layers use the bounded resize provider hint, protecting the existing decode-cache guard from accidental removal.
- A manual profiling checklist was added at `docs/performance-profiling-checklist.md` for editor entry, pan/zoom, drag/resize, crop mode, PNG/JPG export timing, large-image behavior, heavy-document behavior, memory observations, and pass/fail notes.

Still deferred:

- Real Android profile/release timing for low-end and mid-range devices.
- Memory traces for repeated export, crop, and large-image import sessions.
- Platform-stable golden baselines for complex effects-heavy documents.
- A non-widget export compositor or persistent render cache; no clear bug justified that kind of redesign in this batch.

## Batch 7 follow-up: AppBar simplification and context toolbar cleanup

Implemented after Batch 6:

- The editor AppBar is now stable across empty, text-selected, image-selected, shape-selected, and multi-selected states. It keeps document-level actions only: Save, Export, Layers, and the document More menu, plus the platform back affordance when the route can pop.
- Layer-specific actions were removed from the AppBar. Delete, selected-layer tuning, and centre-selected shortcuts no longer appear as top-level AppBar buttons when selection changes.
- Image and shape contextual bottom toolbars now expose Opacity and More. Image still exposes Replace/Relink and Crop from the toolbar; shape still exposes Style/Border/Shadow/Replace.
- Multi-select now has its own bottom contextual strip for Align, Opacity, and More. The alignment sheet remains the place where distribute actions appear for three-or-more layer selections.
- Text More now includes Align, Opacity, and Rename in addition to the existing edit/format/direction/structural actions.
- Direct image duplicate/delete quick actions were removed; image structural actions now route through contextual More so dangerous actions require clearer intent.
- Widget coverage now pins minimal AppBar behavior with no selection, text selection, image selection, group selection, and Persian RTL layout.

Still deferred:

- A deeper unification pass for paint/sticker overflow actions, which still use the older generic quick-action surfaces where no dedicated context toolbar exists.
- Manual device review of the new toolbar ordering on very small Android phones and in long Persian labels.