# User 4 + 5: authored integration, 2026-09-27

## Execution ownership / status

Source and regression authoring only. No terminal, tests, builds, performance
commands, dependencies, code generation, images, goldens or user-data operations
were run. Editor diagnostics reported no errors on the edited production files
and six edited/new test files before the final cancellation-only adjustment.
This is **not runtime verification or a completed all-file-type acceptance pass**.
The other Find agent is the sole executor. Run the checks below after its Find
tests, without overlapping commands. Existing runnable binaries are unchanged.

### Follow-up authoring (same date; also UNRUN)

Final follow-up scope: 11 production Dart files and the three additional test
files below (26 authored cases). Editor formatting completed; targeted editor
diagnostics reported no errors. No terminal/test/build/analyze command ran.
Compilation, actual fixture execution and native Profile/Release replay are
pending with the executor. The earlier source/test files remain unrun here.

- Plain `WorkspaceFolderStage` remote branch now supplies the existing
  `FolderGalleryHeader` to `ProviderPageFlow`. A retained real
  `WorkspaceExplorerController` is seeded from the supplied ViewPB, uses the
  existing repository and a view listener, and does **not** initialize native
  children or read on frames. No synthetic title/icon/cover is constructed.
  The existing local FolderExplorer owner/preferences are unchanged.
- Source/read-only/availability/access changes invalidate identity actions;
  a changed source key/read-only binding retires the old identity controller
  so its in-flight rename continuations cannot adopt into the new binding.
  readonly mounts render the saved cover/icon without mutation controls. Source
  persistence is serialized with a fresh-extra preflight, preserving unrelated
  metadata and rejecting malformed extra. This is not an atomic cross-writer
  transaction. Provider listing/reconnect/cache ownership stays native.
- `FolderGalleryHeader.showStatistics` is the only header API addition: remote
  identity hides misleading zero native-child counts. No cover renderer,
  image loading/decoding, default-cover preferences or shared Find was changed.
- The actual external-folder toolbar uses `FileActionBand` with finite wrapping
  width. Source-changing callbacks check the live owner; pending write-access
  consent cannot rebind a replacement provider. Existing standalone file tools
  already use persistent FileActionBand controls and remain unchanged.
- Workspace photo trackpad pan now routes through the **existing native scale
  recognizer's update callback** only at the identity/Fit matrix. Accumulated
  `localPanDelta` is held until 8px and vertical dominance (2:1), and any scale
  or rotation latches back to native for that stream. No eager arena winner,
  replacement image, transform rewrite, synthetic pointer or second fling.
  Zoomed pan stays native; Fit overflow is header-only, not artificial image pan.
  The photo's artwork fit box subtracts the retired-header distance from its
  growing nested-body extent, preserving painted size/position as well as the
  matrix. The full native gesture viewport remains bounded and fills the body.
  If no body frame was initially visible (header taller than the window), the
  newly revealed body fits normally instead of retaining a zero-height image.
- SDK source showed InteractiveViewer directly applies wheel zoom without
  consulting the signal resolver. New `workspace_image_wheel_gate.dart` filters
  only plain-vertical-wheel delivery to native pointer listeners, retaining hit
  transforms/subtypes and all pan/zoom events. Modified wheel/pinch stay native.
  Photo alone opts into `stopWheelOnNativePan` in StandaloneFileScrollRegion;
  generic adapter thresholds and kinetic policy are unchanged.
- Bookmark Feed/Timeline now opt into existing BookmarkScaffold page flow:
  persistent toolbar/filter chips join their actual vertical list, with the
  same scroll shell retained through empty/populated states. Timeline remains
  lazy; Feed keeps its pre-existing eager content construction.
- Playlist now advertises page-header support. AlbumHost's optional controls
  builder places its real arrangement toolbar above provider status branches;
  its actual lazy queue explicitly borrows the page controller. Player remains
  native/independent. Empty Playlist attaches one scrolling body.

Additional requested executor paths (all under
`frontend/appflowy_flutter/test/widget_test/`, all authored but **not compiled
or run**):

1. `cloud_folder_identity_page_flow_test.dart`: actual WorkspaceFolderStage,
   FolderGalleryHeader and ProviderController with fake service/cache IO;
   saved cover/icon/identity, readonly variants, title draft, loading/error/
   retry/populated/stale transitions, wheel movement, no native-child reads.
2. `workspace_photo_page_pan_test.dart`: actual decoded 640x1600 portrait Image.file and
   InteractiveViewer; fitted wheel/vertical pan/reverse, matrix/frame/element
   retention, 4px and 40px pan-to-pinch, zoomed native pan, Ctrl-wheel, and
   wheel-to-pan cancellation. Light/Dark/Paper at text scale 2.
3. `specialized_collection_page_flow_test.dart`: actual CollectionPage and
   BookmarkHost Feed/Timeline controls, menu persistence, whole-page wheel
   geometry and empty-result retention; actual empty Playlist header/controller
   contract in all themes at text scale 2. Populated Playlist player/queue and
   native Profile/Release photo replay still need executor fixtures.

Keep the prior three new core-layout suites and three updated contracts below
in the compilation set. Editor formatting/diagnostics are not CFE or runtime
proof; no golden/visual approval, all-type acceptance or new binary is claimed.

## Implemented paths (not just the host wrapper)

- `workspace_file_view.dart`: replaced the capped independently scrolling
  identity + Expanded body with `StandaloneFilePage` (premium-marked
  NestedScrollView, natural unpinned header, bounded body). Existing future,
  renderer cache/key, file binding, identity, cover/icon actions, metadata queue,
  original-file Copy/Share service and edit/read checks remain owned as before.
- `standalone_file_page.dart`: explicitly borrowed inner-controller contract;
  implicit primary borrowing is disabled for renderer subtrees. Fixed-controller
  adapters claim vertical wheel at an input hit entry BEFORE native consumption,
  not through replayed notifications. A trackpad-only recognizer takes vertical
  streams before child scrolling; mouse/touch selection stays native. Positive
  travel retires header first; reverse drains real content first. One existing
  PremiumKineticScrollModel owns each adapter's wheel/release movement across
  both destinations. No per-frame render-tree measurements or file reads.
- `file_preview.dart`: real linked code/source-editor scroll controller and real
  text/JSON controller use the adapter; linked line-number controller, native
  EditableText/controller, selection, find implementation and save path remain.
- `notebook_view.dart`: same indexed LocalFileFindScrollController/cell list and
  kernel/editor map; adapter surrounds its actual list. Name-matched scope.
- `pdf_preview.dart` / `pdf_preview_scroll_physics.dart`: **continuous,
  unrotated PDF only** routes existing wheel/pan/kinetic displacements through
  actual `makeMatrixInSafeRange` consumption. Same PdfViewerController and
  existing kinetic owner; sidebar, Ctrl/Meta wheel, pinch and other reading modes
  bypass page consumption. Selection/raster/search/page-turn internals unchanged.
- Workspace image: plain vertical wheel and fitted vertical trackpad pan retire
  the header (follow-up above). Native pinch, modified wheel and zoomed pan
  retain the existing transformation/fit owner.
- Archive Gallery/Thumbnails: same per-mode listing controller through the
  fixed-controller adapter. Tree/List/Details/Tiles and the active/rightmost
  Columns list explicitly borrow the nested primary controller. Ancestor columns
  remain independent. Archive loading/model/write-back/extracted-entry ownership
  unchanged. Fullscreen routes are not wrapped by the workspace page coordinator.
- Cloud collection listings and album Gallery/Masonry/Timeline:
  `ProviderPageFlow` keeps the existing page header and outer controller above
  loading/error/content branches. Actual ExternalContentView and album wall
  slivers explicitly borrow its inner controller. Existing lazy grids/lists,
  provider models, retry/reconnect callbacks and caches remain. Obsolete pending
  provider bindings are generation-guarded.
- Plain external-folder provider options/stale banner now live in the actual
  listing header (not above an Expanded listing); options wrap physically right.
- Bookmark Grid/Shelf: local toolbar and filter chips moved into the vertical
  content header, tools persistent, empty states still attach a vertical scroller.
  Shelf rows retain independent horizontal controllers. The existing bookmark
  grid's eager Wrap was **not virtualized** in this change.

## Action layout

`FileActionBand` separates finite responsive publishers from natural-width
publishers before horizontal overflow. It preserves physical-right placement in
LTR/RTL, native text direction, horizontal reachability and Copy feedback space.
Code and Archive opt into finite responsive widths. Notebook uses a responsive
toolbar builder instead of the host's 620px compatibility shell. Its real inner
reveal (and Archive's) is persistent in standalone mode. Generic file actions
wrap. PDF's natural controls and the separate fullscreen-photo toolbar were not
arbitrarily widened. Album sliver and Bookmark Grid/Shelf controls are persistent;
cover/icon decoration hover remains separate. No icon/model/schema migration.

## Exact remaining limitations

- HTML/Markdown WebViews, native Office, mail WebViews and provider-file dialogs
  have no bounded consumption delegate here. A nested wrapper is **not** claimed
  to coordinate their native body scrolling. Shared Find, native transport,
  premium-scroll implementation, dashboard embeds and document sessions untouched.
- PDF page-break/facing/horizontal/rotated modes do not participate in header
  handoff; neither does touch-selection/pan (as opposed to trackpad input).
- Photo header motion currently follows direct fitted pan updates only; no new
  header-release fling is synthesized. Zoomed-photo boundary-to-header handoff,
  physical hardware cadence and Profile/Release behavior remain unverified.
- Mixed pan-to-pinch streams after a fixed-controller adapter has won cannot be
  transferred to a previously rejected recognizer; the adapter stops instead.
  Do not claim pinch handoff over those editor/list adapters.
- Native code terminal/test trays are secondary panes, not page-integrated.
- Album filmstrip has a horizontal strip and bounded media stage, not a primary
  vertical list; Places owns a map/plot. Neither gets a fake vertical borrowing
  controller. Their local toolbars/body handoff remain unintegrated. Playlist
  queue and Bookmark Feed/Timeline are covered by the follow-up above; Bookmark
  graph, other specialized stages and database decoration remain unchanged.
- PDF rotations require viewport/document-axis conversion around the actual
  safe-range matrix. Horizontal, page-break and facing modes also own different
  paging/boundary semantics. No speculative vertical handoff was added; existing
  continuous/unrotated support is the only PDF claim. Native Office, HTML/mail
  and provider-file dialogs still lack a bounded consumption delegate; no JS
  engine, platform-view transport or native C++ changes were made here.
- Header state/outer position now survives provider status branches; retention of
  every inner offset through total content replacement is not established.
- Existing fullscreen photo/PDF/archive close controls stay outside any newly
  retiring workspace header. Their existing route-current guards are unchanged;
  keyboard/close behavior has not been rerun in this author-only pass.

## Executor checklist

New files under `frontend/appflowy_flutter/test/widget_test/`:

1. `whole_file_page_scroll_test.dart`: real code TextField/linked controller,
   wheel and trackpad header/residual/reverse assertions in all three themes;
   actual PdfViewer and PdfViewerController with fake decoder, no raster images.
2. `file_action_alignment_regression_test.dart`: real readonly code-file controls,
   300/800/1200 widths, text scales 1/2, LTR/RTL, Light/Dark/Paper; measures native
   button bounds and physical right edge, not only the toolbar container.
3. `cloud_collection_page_flow_test.dart`: production ProviderPageFlow and actual
   ExternalContentView with a fake provider; synthetic loading/populated/stale/
   error/retry branches, retained title draft/owner, real wheel residual. This
   does not assert live provider authentication or exercise every AlbumHost branch.

Updated intentional contracts, preserving existing fixtures and retention/data
assertions: `fullscreen_media_actions_test.dart`, `file_header_alignment_test.dart`,
`collection_header_scroll_test.dart`. Old 156/104 split assertions are replaced
with natural-header/viewport geometry; tests include retained offstage subtrees.

After Find work: format/analyze the changed paths; compile/run these six files,
then existing file control, archive, notebook, PDF toolbar/page-turn, album auth,
folder whole-page and collection wheel-coordination suites. Investigate failures,
do not skip or loosen native geometry/state assertions. Expand coverage for
adapter cancellation/coast, image zoom retention, editable/running notebook,
all publishers/long localized actions and real provider-host transitions; the
new suites do not by themselves cover that entire acceptance matrix.

Only the executor should then build normal `lib/main.dart` Release **first** and
Debug **last**, using the existing bundle verification task and preserving the
other agents' changes. Verify refreshed executable and payloads at:

- `frontend/appflowy_flutter/build/windows/x64/runner/Release/AppFlowy.exe`
- `frontend/appflowy_flutter/build/windows/x64/runner/Debug/AppFlowy.exe`

Do not claim this authoring pass refreshed or launched either binary.