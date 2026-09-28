# Page cover appearance / resize — integration status

## Coordinated validation attempt — 2026-09-27

This section supersedes the earlier no-execution status below for this validation
attempt only. Locale source generation and focused CLI tests were authorized;
application builds, native fixtures, images/goldens and out-of-scope source edits
were not.

- Synced `coverAppearance` immediately before `backup` using the existing block
  splice script, then ran both normal easy_localization generators with the
  installed Dart 3.6.2 SDK. Verified exact preservation of bundled text outside
  that block and presence of every previously generated locale constant.
  Log: `build/performance/followup-cover-locale-20260927-115717-949.log`.
- Invoked all four exact cover test paths listed below using direct Dart
  flutter_tools, `--no-pub --concurrency=1 --reporter expanded`.
  **0 test bodies executed; all 4 suites failed compilation; exit 1.**
  Log: `build/performance/followup-cover-focused-20260927-115740-556.log`.
- Blocking CFE error: `lib/plugins/dashboard/presentation/dashboard_embed_find.dart:386:30`,
  `Node.context` getter unavailable. Its appflowy_editor import is restricted to
  `show AppFlowyEditor, EditorState`; the owning Find agent must resolve the
  missing API/extension visibility. This file was inspected read-only, not edited.
- Editor diagnostics independently report that same error and no errors in
  `page_cover.dart`, `page_cover_controller.dart`, `page_cover_height.dart`,
  `cover_appearance.dart` and the four cover test files. This is not proof of
  runtime correctness or a successful compile.
- No production Dart source changed in this validation attempt. No test assertion
  was weakened, no repair cycle used, no dependency/environment/user-data change,
  no application build or native fixture execution. Icon queue regressions,
  actual settings/root mounts and subsequent host/short-pane/retention regressions
  remain pending behind the compile blocker; no height/spacing measurement claimed.

## Status and execution boundary

Implemented shared defaults, settings/root wiring, page-header geometry, actual
desktop document covers and real folder-page resizing. The remaining dashboard,
collection, database and standalone-file resize opt-ins are now applied in source.
The file cover's outer fixed height/rounded clip has been replaced by
`PageCoverLayout`, so Square is no longer defeated by that outer clip.

**No terminal, process, test, build, codegen, image capture, golden update, new
dependency, live preference or user-data operation was executed.** Editor
diagnostics reported no errors on the changed Dart paths. That is not a compile,
runtime, visual, or test-pass claim. Formatting and coordinated validation remain
required: this session has no `tool_search` API to load the formatter as required.
No terminal fallback was used. The native agent exclusively owns its isolated
fixture execution; this integration pass does not run or modify that fixture.

## Actual architecture (not inline media)

- `DocumentCoverWidget` owns the view notification and legacy node attributes.
  `DocumentCover` retains upload/download/picker ownership. `DesktopCover` renders
  modern `view.cover` when present, otherwise the legacy node `cover_selection`
  and `cover_selection_type`. A modern explicit `none` wins over legacy artwork.
- `ViewCoverCodec` is the actual codec name (there is no `PageStyleCoverCodec`).
  `PageStyleCover` contains only type/value, not height or position. No generated
  model needs editing. The extra JSON decoder refuses non-object metadata.
- `WorkspacePageHeader` owns cover positioning AND the identity top inset.
  Resizing an image alone cannot resize this header. It now delegates the shared
  geometry to `PageCoverLayout`, which supplies the same height to both.
- `WorkspacePageCover` owns cover clipping and image-local controls. Its
  presentation scope applies defaults to `ViewCoverImage` without changing
  ordinary thumbnail or inline-image defaults. `FlowyNetworkImage.alignment` is
  additive and defaults to center for all old callers.
- The actual root is `ApplicationWidget` in `startup/tasks/app_widget.dart`:
  startup awaits `CoverAppearanceStore.ensureLoaded()`, and a root
  `CoverAppearanceScope` publishes only acknowledged local preference changes.
  There was no existing `AppFlowyScope` class to extend.
- `ResizableMedia` and page-icon sizing are NOT cover geometry. Icon metadata
  validation/API/pending-size tracking remain unchanged. Only its existing
  serialization primitive was extracted to `PageIconBackendService.serializeMetadata`;
  icon and cover height updates now share that queue.

## Public APIs and storage contracts

Import `package:appflowy/shared/page_cover.dart` for the integration API.

- `CoverAppearance`: `CoverCorners.rounded/square`, optional `aspectRatio`,
  `CoverImageFit.fit/crop/stretch`, `CoverPosition.top/center/bottom`.
- Defaults: rounded 16px corners, original host responsive height (ratio null),
  crop (`BoxFit.cover`), center. Fit uses contain; only Stretch uses fill.
  Ratios accept finite continuous values from 1 through 6.
- `CoverAppearanceStore`: injectable local KV resolver; `appearances`, `value`,
  `ensureLoaded`, `update(transform)`, `reset`, `isLoaded`, `isSaving`, `failure`.
  Transformations run serially against the last acknowledgement, avoiding stale
  settings-build snapshots. Missing storage/failed loads remain retryable.
  SharedPreferences false ACKs are failures; cache reload follows a refusal.
- KV key `appflowy_cover_appearance`, version-1 JSON:
  `version`, `corners`, `aspect_ratio`, `fit`, `position`.
  Missing/corrupt/future data displays safe defaults without rewriting it.
  Reset explicitly writes default local settings; it does not scan workspace views.
- `PageCoverHeight`: key `page_cover_height`; finite logical pixels 96..640,
  `decode`, `resolve`, `maximumFor`, `merge`, `applyTo`.
  Display height is additionally bounded to max(96, min(640, actual cover width)).
  Responsive display clamping does NOT rewrite a saved height. A drag release
  commits its current displayed height, including after a pane resize.
  Null removes ONLY the height field and resumes the latest defaults.
- Optional `page_cover_position` finite numeric -1..1 is read as vertical
  alignment before the default. No position write or migration is performed.
- `PageCoverLayout(width, fallbackHeight, builder, view?, editable:false,
  binding?, canResize?, isSameTarget?, onHeightChanged?, backend?)`.
  `builder(context, height, grip)` must use that height for all related geometry;
  place the supplied grip INSIDE the image box, not outside hit-test bounds.
- `WorkspacePageHeader`: additive `coverView`, `coverEditable:false`,
  `coverBinding`, `canResizeCover`, `isSameCoverTarget`,
  `onCoverHeightChanged`. Existing callers remain display-only by default.
- `WorkspacePageCover`: additive `resizeGrip`; no metadata writer of its own.
- `PageCoverBackendScope` injects `PageCoverBackendService(views: existingAdapter)`;
  the adapter is the existing `PageIconBackendService` read/update/listen boundary.
- `PageCoverInteractionGate(allowed: ValueNotifier<bool>, child: ...)` lets
  pending media work synchronously revoke resizing. False -> true in one frame
  still invalidates the old queued gesture. Document cover actions use this.

Writes re-read the view INSIDE the shared per-view queue, validate ID/layout/
lock/source and caller access before dispatch, merge only height, and accept
an empty UpdateView success ACK. Source checks include cover, collection source
(including read-only), and workspace-item metadata. Disposal, rebinding, deleted/
trashed notifications, and access-stream revocation invalidate queued work.
No automatic retry or inverse write is attempted after an uncertain failure.
This is NOT a cross-device transaction or an atomic CAS against unrelated
metadata writers that do not use the shared queue. Already-dispatched backend
writes cannot be cancelled; stale callbacks are suppressed.

The grip uses a concrete cancel-aware PanGestureRecognizer (Flutter 3.27's base
DragGestureRecognizer is sealed), declines trackpad pan/zoom, keeps pointer
moves transient, saves once on release, rolls back on cancel/Escape, supports
Up/Down (1px), Shift (10px), Home reset, and semantic increase/decrease/reset.
It has no animation or ticker. Title and image elements retain stable depth.

## Completed host integrations and limits

All four hosts import `package:appflowy/shared/page_cover.dart` and retain their
existing title, icon, decoration action and controller owners. Completion merges
only `page_cover_height` into the latest host view; it never performs a second write.

- `lib/plugins/dashboard/presentation/dashboard_page.dart`: `_view` and the real
  dashboard controller bind the header. Editable non-immersive mode only; fresh
  views must still carry dashboard metadata. Only the import and cover arguments
  changed. `dashboard_canvas.dart`, Find and text painting were not edited.
- `lib/plugins/collection/collection_page.dart`: current controller view, kind,
  source cache key AND source read-only flag bind resizing. Full cover/source
  identity is checked at activation/completion. Height bypasses the existing
  cover/icon-only completion filter. The recent `FileBrowserPageHeader` / nested
  page-scroll branches and all their keys/controllers remain unchanged.
- `lib/plugins/database/tab_bar/tab_bar_view.dart`: real `DatabasePageDecoration`
  view and access checks; `AutomaticViewCover.showsCover` remains required both
  locally and at fresh-write preflight. Explicit none still renders no cover/grip.
  Existing tab, renderer, Find, title and icon behavior is unchanged.
- `lib/plugins/workspace_file/workspace_file_identity.dart`: actual-width
  `PageCoverLayout` supplies image height/grip, without an outer fixed-radius clip.
  Real binding, repository, storage URL/content kind and full source identity are
  checked. `_saving` disables resize during title persistence. The keyed heading,
  always-visible tool row, original media action GlobalKey and renderer controls
  remain where they were. `workspace_file_view.dart` was inspected, not edited.
- Document/folder integration was already present and is retained. Document
  upload/download actions use their actual `_coverIdle` notifier through
  `PageCoverInteractionGate`; no synthetic busy callback was added.

**Copy/Share limitation:** `MediaActionButtons` has private `_pending` state and
NO public pending notifier/callback. `MediaActionService` and the file's guarded
delegate provide no such API either. Per the integration constraint, height-only
resizing may proceed during unrelated Copy/Share. The existing action owner and
its in-flight lock/source checks remain intact; no media API was expanded merely
to manufacture a resize gate. Cover-image/viewer-metadata writers still use their
own existing queues: this change does not claim atomic serialization with them.

**Workspace root limitation:** `FolderGalleryHeader` reads `UserWorkspacePB.cover`
and explicitly passes no `coverView` for the root. `WorkspaceRepository` exposes
image-cover updates, not a separate height/preferences backend, and the existing
global appearance store has a ratio rather than a height field. Root covers follow
persisted local corners/ratio/fit/position defaults, including after reopening;
per-root drag-height persistence is NOT implemented. No synthetic ViewPB, image
envelope extension, new preference schema or backend migration was invented.

Row-banner covers use their separate row-meta backend; mobile immersive covers
and ordinary inline media are outside this desktop page-view height integration.

## Files changed in this owner

Paths below are relative to `C:\AppFlowy\frontend\appflowy_flutter`:

- NEW `lib/workspace/application/settings/cover_appearance.dart`
- NEW `lib/shared/page_cover_height.dart`
- NEW `lib/shared/page_cover_controller.dart`
- NEW `lib/shared/page_cover.dart`
- NEW `lib/workspace/presentation/settings/pages/cover_appearance_setting.dart`
- `lib/shared/page_icon_controller.dart` (serialization extraction only)
- `lib/shared/workspace_design.dart`
- `lib/shared/appflowy_network_image.dart` (alignment parameter only)
- `lib/startup/tasks/app_widget.dart`
- `lib/workspace/presentation/settings/pages/settings_workspace_view.dart`
- `lib/plugins/document/presentation/editor_plugins/header/desktop_cover.dart`
- `lib/plugins/document/presentation/editor_plugins/header/document_cover_widget.dart`
- `lib/workspace/presentation/widgets/view_cover/view_cover_image.dart`
- `lib/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart`
- NEW `test/support/page_cover_test_support.dart`
- NEW tests listed below.

Also added only the `coverAppearance` source block in
`C:\AppFlowy\frontend\resources\translations\en-US.json` and this handoff.
No generated Freezed/protobuf/Rust files, assets, dependencies or reserved owner
files were edited. The existing mobile immersive-cover/row-cover paths are not
converted into page-view height writers by this desktop feature.

## Tests written (absolute paths; NOT RUN)

- `C:\AppFlowy\frontend\appflowy_flutter\test\unit_test\workspace\cover_appearance_test.dart`
- `C:\AppFlowy\frontend\appflowy_flutter\test\widget_test\page_cover_resize_test.dart`
- `C:\AppFlowy\frontend\appflowy_flutter\test\widget_test\document_cover_appearance_test.dart`
- `C:\AppFlowy\frontend\appflowy_flutter\test\widget_test\page_cover_host_integration_test.dart`
- Helper: `C:\AppFlowy\frontend\appflowy_flutter\test\support\page_cover_test_support.dart`

They cover safe parse/roundtrip, local ACK ordering and retry/reset, strict height
merge preservation, interleaved icon/cover writes, fresh-source/lock/access
preflight, cancellation/deletion/disposal, pumped real pointer sequences,
keyboard/semantics, pending-media revocation, live defaults with retained title
state/focus, multiple mounted defaults, separate thumbnails, native settings at
200% scale, and actual DesktopCover legacy/modern/explicit-none branches.

The new host suite mounts real DashboardPage, CollectionPage,
DatabasePageDecoration, WorkspaceFileIdentityRow and FolderGalleryHeader with
existing controllers and `PageCoverBackendScope`. It reuses
`page_cover_test_support.dart` and `file_controls_test_support.dart`, not a cloned
native fixture. Cases cover 780/320px panes in light/dark/paper, 32px saved icon
metadata, exact +48px pumped drag geometry, cancel/no-write and release/one-write,
empty success ACK adoption, height-only metadata preservation/reopen, live
Square/Fit/Crop/Stretch/ratio/position, title draft/controller/focus retention,
malformed height reload, explicit height/position precedence, lock/removal/disposal
preflight rejection, actual file-title saving and retained pending Copy controls,
dashboard immersive exclusion, and defaults-only workspace-root reload.

`cover_appearance_test.dart` additionally exercises the actual store's DartKeyValue
branch with a refused SharedPreferences boolean ACK, optimistic cache reload,
no false publication, successful retry/reopen/reset and key isolation. Three
redundant null assertions in that existing test were removed. No test-pass or
complete application-root/runtime coverage is claimed.

## Exact scope of the remaining-integration pass

Only these seven files were edited in this pass (the foundation list above
describes earlier work, not additional edits here):

1. `frontend/appflowy_flutter/lib/plugins/dashboard/presentation/dashboard_page.dart`
2. `frontend/appflowy_flutter/lib/plugins/collection/collection_page.dart`
3. `frontend/appflowy_flutter/lib/plugins/database/tab_bar/tab_bar_view.dart`
4. `frontend/appflowy_flutter/lib/plugins/workspace_file/workspace_file_identity.dart`
5. `frontend/appflowy_flutter/test/widget_test/page_cover_host_integration_test.dart` (new)
6. `frontend/appflowy_flutter/test/unit_test/workspace/cover_appearance_test.dart`
7. `doc/cover-appearance-integration.md`

No native plugin, shared Find/text-painting, dependencies, generated code, locale
source/bundle, image, golden, user data, startup or settings file was edited here.

## Coordinator commands — required later, not executed here

Working directory: `C:\AppFlowy\frontend\appflowy_flutter`.

1. Format the changed Dart files listed above with the editor's Dart formatter
   (including the coordinator's host edits). Do not format unrelated work.
2. Sync only the new English block:
   `pwsh -NoProfile -File tool/sync_locale_block.ps1 -Block coverAppearance -NextBlock backup`
3. Normal locale generation (never hand-edit generated output):
   `dart run easy_localization:generate -S assets/translations/`
   and `dart run easy_localization:generate -f keys -o locale_keys.g.dart -S assets/translations/ -s en-US.json`.
   Dynamic `coverLabel` fallbacks mean compilation does not depend on new generated
   constants, but shipped translations should still be synchronized.
4. Run targeted `flutter analyze` for the changed Dart paths, then:
  `flutter test test/unit_test/workspace/cover_appearance_test.dart test/widget_test/page_cover_resize_test.dart test/widget_test/document_cover_appearance_test.dart test/widget_test/page_cover_host_integration_test.dart`.
5. Regress the unchanged icon contract after queue extraction:
   `flutter test test/unit_test/shared/page_icon_size_test.dart test/unit_test/shared/page_icon_controller_test.dart test/widget_test/page_icon_test.dart test/widget_test/page_icon_cover_test.dart test/widget_test/default_icon_style_test.dart`.
  Then run host neighbors:
  `flutter test test/widget_test/compact_page_header_test.dart test/widget_test/folder_whole_page_scroll_test.dart test/widget_test/collection_header_scroll_test.dart test/widget_test/dashboard_workspace_page_test.dart test/widget_test/standalone_file_decoration_regression_test.dart test/widget_test/file_photo_workspace_identity_test.dart`.
  Never update goldens without visual review. All these commands remain pending;
  execute only when the main coordinator lifts the no-command boundary.
6. Once all owners are done, run the existing task **AF: Build and Verify Windows
   Bundles** (Release FIRST, Debug LAST). It must verify refreshed nonempty
   `build/windows/x64/runner/Release/AppFlowy.exe` and
   `build/windows/x64/runner/Debug/AppFlowy.exe`, plus AOT/kernel freshness and
   bundle integrity. No build or launch result is claimed by this handoff.