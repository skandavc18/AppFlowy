# Content-first workspace design

Primary reference: the supplied Google AI Studio `notion-home` source and Home
screenshot (20 September 2026). This is a presentation redesign; the prototype's
mock tasks, weather, pages, storage and React implementation are not imported.

## Why the reference reads differently

- A quiet navigation rail is subordinate to one shallow contextual header.
- The page, not a toolbar, supplies identity: broad cover, separate icon, large
  title and a short description, followed by generous whitespace.
- Content shares a continuous canvas. Cards are content objects with a substantial
  preview and a quiet caption, rather than panels full of controls.
- Secondary actions are local to the object and appear on hover or keyboard
  focus. Disclosure never removes keyboard access or shifts the content.
- Typography, spacing and tonal contrast establish hierarchy; borders and shadows
  are supporting cues. The reference's occasional pills and gradients are not
  universal component styles.

## Structural audit and intended changes

| Surface | Previous composition | Workspace composition |
| --- | --- | --- |
| Desktop shell | title/tab bar + context toolbar + page toolbar | one caption/context header; tab rail only when several pages are open |
| Sidebar | utility strip + identity + creation + navigation + large utility footer | workspace identity, quiet navigation/tree, compact utilities |
| Home/dashboard | fixed 22px heading beside editing controls | scrollable page identity and existing content arrangement |
| Documents | cover constrained to text + icon beside title | broad cover, icon above title, retained reading measure/editor |
| Collections | repeated breadcrumbs + dense control heading | page identity, quiet view navigation, local actions |
| Gallery | preview plus multiple competing metadata bands | preview-first objects, title and secondary metadata, contextual overflow |
| Search/settings/overlays | separate panel geometries | shared floating surface and responsive composition |

## Shared contract

`workspace_tokens.dart` owns geometry/motion; `workspace_design.dart` projects
`PremiumThemeExtension`, `PaperTheme` and `EditorSurfaceStyle` into semantic
surfaces, type roles and reusable page identity. `WorkspaceChrome` consumes the
same type and control roles. Controls/inputs/menus/cards/dialogs/heroes use
8/12/16/20/24/28px radii respectively, not capsules everywhere.

Presentation must preserve saved widths/layouts, data models, editor identity,
drafts, drag/drop, keyboard shortcuts, native caption hit targets, focus and
permissions. Light, dark and warm paper mode are equally supported. Reduced
motion skips transitions. At narrow widths composition wraps or overlays rather
than shrinking a desktop toolbar until it overflows.

## Verification

Behavior tests, rendered light/dark/paper comparisons and native Windows visual
inspection accompany the implementation. Compile success alone is not a visual
audit. Windows bundles are built Release first and Debug last, with executable
and Dart-payload freshness and functional parity verified independently.

### Implemented presentation changes

- The desktop shell now owns a single 48px caption/context header. A 32px tab
  rail appears for multiple tabs; single-tab commands remain in an accessible
  overflow. Explicit keyed visibility siblings preserve each page through tab
  reordering. Native window drag areas are separate from interactive controls.
- Sidebar identity and collapse controls share a header; creation and compact
  utilities sit below the page tree. The baseline is 248px with 34px rows, while
  saved relative widths and the existing drawer breakpoint are preserved.
- Home/dashboard identity scrolls with its content and renders saved covers and
  icons. Documents, folders, collections and databases share vertical identity
  and broad covers; embedded databases do not acquire full-page decoration.
- Gallery cards retain preview renderers, titles and drafts while loading,
  hovering, selecting and opening menus. Folder and database galleries share
  surface/type roles, keyboard-accessible overflow, and quieter real metadata.
- Search uses independent width/height constraints and unboxed previews.
  Settings changes from rail/content to a compact navigation picker without
  remounting its content. Existing dialogs and contextual menus share floating
  geometry, semantic surfaces and reduced-motion behavior.
- The default dark appearance uses a neutral tonal hierarchy rather than the
  previous blue-grey chrome; explicit custom dark palettes retain their colors.

### Preservation and safety checks

- Dashboard card wrappers and text/number fields stay mounted across mode/access
  changes. A blocked write retains the local draft; unlocking does not silently
  autosave it. Reaccepted edits merge into the latest widget settings.
- Cover requests capture their owning view and generation. Delayed profile,
  upload or save completions cannot retarget another page, notify its host or
  delete its cover. Only proven new local uploads can be discarded; an ambiguous
  cloud save is not claimed to be an atomic or reversible transaction.
- Folder mutation entrypoints share current permissions, including menus,
  keyboard paste and drops. Workspace identity rights remain separate from a
  member's right to add content. Backend authorization is still authoritative.
- Bookmark grid/feed/shelf/timeline main scrollers borrow their collection's
  nested controller. A scoped wheel fallback uses native nested coordination
  once; unrelated wheels retain premium smoothing. This intentionally trades
  smoothing for correct header/body coordination on the opted-in page only.
  Other specialized collection readers retain their own scrolling models.

### Original redesign validation (21 September 2026)

- **1,453 tests / 51 files passed**, including normal golden comparisons,
  sidebar/tab navigation, retained editor state, permissions, async cover
  requests, dashboard lifecycle, database preview modes, and scrolling.
  Log: `build/performance/workspace-redesign-final-regressions.log`.
- All **126 changed Dart paths** were analyzed in bounded batches. Subsequent
  cleanup of the seven affected paths is recorded in
  `build/performance/workspace-redesign-cleanup-analysis.log` (clean).
  This is targeted analysis, not a claim that unrelated orphan code is clean.
- **18 desktop/compact × light/dark/paper native presentation scenarios passed**.
  Final inventory: `build/performance/workspace-design/run-2edc13d7/manifest.json`;
  log: `build/performance/workspace-redesign-native-final.log`.
  These use actual production widgets with offline fixture models and zero HTTP
  attempts. Captures are native Flutter frame captures, not OS window captures
  and not substitutes for normal-app startup/navigation verification.
- `tool/inspect_workspace_window.ps1` provides DPI-correct OS window captures
  for the final live-app audit, refusing input unless the requested AppFlowy
  window is foreground. It does not edit workspace data or preferences.

### Original redesign Windows bundles

Both normal bundles completed, Release then Debug. Independently rehashed all
**4,798 current inputs** against the build manifest:
`C448877515855F8D7A37DEE51418C93477B032EF23E964D8BDB266C4A93140FD`.
All four executable/Dart payload timestamps are newer than their own build
starts and the latest production edit. The bundles have **1,179 matching
functional assets and 36 native components**, including the same optimized
Rust backend. Manifest: `build/performance/windows-bundles.json`.

- Release: `build/windows/x64/runner/Release/AppFlowy.exe`
  (2026-09-20 19:09:52.5974860 UTC); AOT payload 19:09:13.9928239 UTC.
- Debug: `build/windows/x64/runner/Debug/AppFlowy.exe`
  (2026-09-20 19:11:40.2288949 UTC); kernel 19:11:03.1891418 UTC.

The normal Debug app was opened through Explorer at
2026-09-21 02:02:30.8752361 UTC (PID 32272), with the actual workspace loaded and
responsive. OS-window captures at 2066×1161 include the live gallery, Home,
search and Settings surfaces under `build/performance/workspace-design/live-*.png`
(the initial `live-home.png` caught search before the navigation frame settled;
`live-page.png` shows the completed Home navigation).
No existing app was force-closed, and no workspace content was edited for the
audit. These are visual/navigation checks, not a claim that every integration
or every possible saved layout was manually exercised.

Final process verification at 2026-09-21 02:07:56.2658124 UTC confirmed the normal
Debug executable, Explorer parent, responsive main window, and loaded backend
SHA-256 `5D059D887BFD7FEF28CBBF09230D2481B2F1D91238DBFDF1CC009DDE821B7F84`.
The app was left open at that checkpoint. Temporary verification tasks were
removed; the repository's original tasks and comments were unchanged, and the
diff check was clean.

## Consistency follow-up (21 September 2026)

This supersedes the original single-tab and palette details above:

- Shared `WorkspaceGlyph` outlines use a consistent 24-unit, 1.75-stroke family
  across settings, sidebar, slash/context menus, view tabs, grid toolbar and
  field/property controls. Control labels use weight 500; titles retain their
  hierarchy. Unknown third-party symbols retain their original artwork.
- **Settings → Workspace → Appearance → Default icon set** offers Monochrome
  and Colored / Vivid. The device-local preference is restored at startup and
  published only after an acknowledged save. Existing chosen emoji, uploaded
  images and library icons are not rewritten. Vivid illustrations are used
  where available, otherwise the same outline uses the theme accent. Disabled
  and destructive actions retain their state ink.
- Colorful saved identities have real optical layout slots: 22px artwork in a
  24px sidebar slot, and 64px artwork in a 66px page-header slot. Default outline
  sizes and icon-picker catalogue compatibility remain unchanged.
- Folder, document, dashboard and collection actions share one hover/focus
  reveal row. Collection tabs occupy its persistent leading slot so navigation
  remains discoverable; actions sit alongside at wide widths and wrap when
  necessary. Popup holds, keyboard traversal, permissions and draft retention
  are exercised by tests.
- Empty folders and empty pages/files show their real default identity, not
  invented content. Loading, unavailable and failed previews remain distinct;
  populated renderers, saved covers and chosen icons remain intact.
- Calendar **Month + agenda** and **Month beside agenda** modes are available
  in editor calendar views and dashboard calendar widgets. They use loaded
  events and a selected day, retain existing actions/filters, and adapt at small
  sizes. Paging no longer interpolates finite and unbounded day-badge widths.
- Search results and recents are on the left, with previews on the right.
  Light uses a creamy page with a distinct warm sidebar; Paper retains a warmer
  surface hierarchy. Explicit custom themes and Dark remain supported.
- Collection identities and bodies share a 24px gutter. Database, repository,
  album, bookmark, book and shared email chrome use quiet, unboxed stages.
  Their real editors, draft state, controllers and specialized renderers remain.
- Database view choices wrap instead of hiding in a horizontal scroller. Very
  large sets retain visible vertical scrolling. Workspace tabs use substantial
  38px rounded rectangles and remain visible for a single page, with path first.
- Standalone files/photos have one prominent filename with guarded inline
  rename, one host identity and a continuous page surface. Embedded renderers
  retain their appearance. Renaming changes the workspace title, not the payload
  path; changing an extension takes effect when reopened. OCR uses an outline
  document-scan action labelled **Extract text**.
- Locale block syncing now anchors top-level keys; a nested
  `document.plugins.board` can no longer truncate the document translation
  update. Popup-focus ancestry checks are deferred until tree detachment ends.

### Follow-up validation

- **1,783 tests / 57 files passed** with normal golden comparisons:
  `build/performance/workspace-consistency-final-regressions.log`.
  This is the selected UI/regression set, not every test in the repository.
- **233 touched Dart paths analyzed cleanly**:
  `build/performance/workspace-consistency-analysis-complete.log`.
- Three Light/Dark/Paper component sheets compare Monochrome and Vivid using
  real settings, calendars, file/photo renderers, empty cards, collection schema
  and tab widgets. The sheets, sidebar reference, board previews and 18 prior
  desktop/compact presentation references were rendered and visually reviewed.
- The offline **native Windows component test passed**, capturing all three
  themes with zero HTTP attempts:
  `build/performance/workspace-consistency/run-8afa335d/manifest.json` and
  `build/performance/workspace-consistency-native.log`.
  These are Flutter frame captures, not normal-app OS captures. Fixture models
  replace backend IO; code uses disclosed bundled Roboto Mono substitution,
  not a claim to verify JetBrains Mono. OCR, code execution, Office, WebView and
  native media playback were not exercised by these captures.

### Follow-up normal bundles and live audit

That follow-up's Release → Debug build completed at 2026-09-21 09:16:49 UTC,
with 4,809 identical inputs, 1,179 matching assets and 36 native components.
The user subsequently confirmed the normal app rendered, and reported the
compactness, scrolling and gallery issues addressed in the next section.
These are historical bundles, not verification of the newer changes below.

## Compactness and interaction corrections (21 September 2026)

- The shell combines the path, rectangular tabs, context actions and native
  caption controls in **one 48px row**. `/` represents the workspace root;
  ancestor disclosures load actual children with loading, error/retry and empty
  states. Selection revalidates the view; stale menu requests cannot navigate
  after a page/workspace change. Guest root enumeration is blocked.
- Cover change/remove/download controls now sit on the cover image, revealed
  locally by hover/focus. Icon controls and the missing-cover affordance sit
  beside the icon. Existing reveal motion is 140ms and respects reduced motion.
  Covers use 8px outer margins, default desktop height 176px, an 8px cover-to-
  identity gap and a 6px icon-to-title gap. Explicit cover heights still win.
  Cover state/request ownership remains singular across the presentation slots.
- Nested collection wheels now share the existing premium distance queue and
  apply each animated increment through the native outer `pointerScroll`
  coordinator. They no longer jump by a full notch or write inner pixels past
  the header. Touch, precision input, interruption and boundary behavior remain
  covered by their existing tests; this is not a measured FPS claim.
- Gallery title activation is explicit; passive preview renderers cannot steal
  card input, while retry and overflow remain interactive. A 4px mouse drag
  threshold separates normal click wobble from moving an item. Real-grid tests
  exercise opening, folder navigation, selection, rename, drag/drop and delayed
  previews. The exact original live dead-click was not independently reproduced
  before these corrections, so live verification remains important.
- Empty collection thumbnails use their collection type, not a generic folder.
  All seven kinds preserve custom icons and saved cover precedence.
- Month/agenda layouts use a centered 720px stacked measure or 1,100px split
  measure, bounded circular dates, aligned controls and a readable event list.
  Small dashboard calendars retain all weeks and scrollable real events.
- The actual document viewport resolves the semantic cream/Paper canvas, not
  an inherited white surface. `EditorCanvasScope` lets row-page previews remain
  transparent. Visual comparisons caught and prevented an opaque rectangle
  regression inside board cards; their existing reference images are unchanged.

### Compactness-round verification

The current source set has **243 Dart paths with clean analysis** in
`build/performance/workspace-compact-analysis-final.log`. The final selected
regression run passed **2,157 tests / 68 files**, including normal golden
comparisons: `build/performance/workspace-compact-final-regressions.log`.
Calendar and compact header references were rendered and reviewed in Light,
Dark and Paper. Pixel tests exercise the actual editor canvas, including custom
Light and transparent preview hosts.

Native Windows component capture also passed, with all three themes and zero
HTTP attempts: `build/performance/workspace-compact-native.log` and
`build/performance/workspace-consistency/run-8dc2f5e6/manifest.json`.
The fixture's synthetic-data and disclosed code-font limitations still apply.

Both normal bundles completed, Release first and Debug last; manifest verified
at **2026-09-21 17:07:37.8079344 UTC**. Independent verification after completion
rehashed all **4,810 current inputs**, matching
`DFBA56AA15ABB07E46BCEBD7BB9053C8DC8A4C26EE78375AD4374BB4CC0F3705`.
All four artifacts are newer than their build start and the latest production
edit. The bundles contain **1,179 matching assets and 36 native components**.

- Release: `build/windows/x64/runner/Release/AppFlowy.exe`
  (17:05:04.3011861 UTC); AOT payload 17:04:19.4469275 UTC.
- Debug: `build/windows/x64/runner/Debug/AppFlowy.exe`
  (17:07:10.6347200 UTC); kernel 17:06:27.6445478 UTC.

The fresh normal Debug process (PID 45032) started at
**2026-09-21 17:09:10.4341113 UTC**. Runtime verification confirmed the correct
executable and loaded backend hash
`630802F294ADA6A0613C0FB1D90338B67C906F1CFCAB588308FD98FF10F509BF`.
At 17:12:06 UTC it remained responsive. Launch used Shell.Application, although
the observed parent process was `pwsh`, not Explorer.

**Live visual/navigation audit blocked:** Windows returned blank off-screen
captures and foreground handle zero; the guarded foreground capture sent no
UI input. `build/performance/workspace-compact-live/{startup,settled}.png` are
therefore not proof of live rendering or a diagnosis of app startup failure.
The app is left running for user confirmation of gallery clicks, scrolling and
the compact UI. No existing user app was closed, and no workspace content,
preferences or caches were reset for the audit.

## File, collection and startup repairs (22 September 2026)

This supersedes the compactness round's fixed calendar-width limits.

- Code viewer settings now accumulate against current metadata rather than a
  loader snapshot. Published tools use the header's actual width and retain
  menu/focus visibility, editor drafts, selection, scroll and active-run Stop
  controls. Line-number states have distinct glyphs. File/code/archive controls
  share native button geometry, typography and outline artwork; Copy/Share sit
  with the other archive actions instead of a separate strip.
- Shared hover washes preserve or multiply their existing alpha. Provider,
  folder, collection, editor and menu controls no longer turn a translucent
  hover into an opaque dark fill. Selection, keyboard focus, destructive ink
  and white photo-overlay controls remain distinct.
- Missing Add Icon/Add Cover actions stay discoverable. Standalone files and
  full-page chart/map/slides/table readings use the existing guarded decoration
  model; embeds do not acquire another full-page header. Cover and viewer-state
  writes on files serialize and merge fresh metadata without replacing file
  bytes or remounting their renderer.
- The Books Files regression was reproduced by real collection widgets:
  borrowed FolderExplorer root adoption notified its parent during build;
  the reader's final save also called parent setState while unmount locked the
  tree. Borrowed updates no longer echo back, equal root adoption is silent,
  and the final save remains immediate while its UI repaint is deferred.
  The same tests failed before and passed after the correction.
- Startup no longer navigates to shared latest-view metadata or reconstructs
  old crash tabs. Home opens a valid chosen dashboard in the current workspace,
  otherwise a navigation-only Home with real Workspace/Search/Templates actions.
  No replacement workspace page is automatically created. Sidebar Home is
  explicit; newer navigation wins over delayed startup and manual tabs survive
  a Home visit. Legacy stored tab preferences are not erased.
- Chat thumbnails are classified before database/document reads and show an
  honest AI Chat identity. Default file and collection artwork is classified
  centrally and shared inside/outside archives, with outline and untinted Vivid
  versions. Explicit saved icons and covers retain precedence.
- Full-page month/agenda compositions use available width and height, with
  18px dates, 44px circular badges and readable 16px event titles. Compact cards
  keep their smaller density. Both standalone-calendar and database-card
  customization now expose labelled month-with-events choices; persisted mode
  names, providers, event actions and controller lifetime are preserved.
- The top-left personal avatar and owner-editable workspace icon open the full
  picker, separately from the workspace switcher. Saves await acknowledgement,
  failures remain retryable and do not display raw backend details. User changes,
  permission changes, disposal and delayed profile reads reject stale callbacks.

### Repair verification

- Selected final regression run: **2,758 tests / 94 files passed**, including
  normal image comparisons, in `build/performance/seven-fixes-final-regressions.log`.
  Supplementary coverage passed **211 tests** in
  `build/performance/seven-fixes-final-supplement.log`; these runs overlap and
  their counts are not presented as a unique total. The separate profile/workspace-
  icon suite passed all **38 cases**. The Books lifecycle reproduction changed
  from 22 passing / 7 failing cases to **29 passing cases**.
- **312 changed Dart paths analyzed cleanly**:
  `build/performance/seven-fixes-analysis-final.log`. This is targeted analysis,
  not a claim that every repository test or unrelated source file is clean.
- Real file/code/archive control sheets and typed-icon sheets were reviewed in
  Light, Dark and Paper. Full-page and compact calendar references were reviewed;
  all 58 calendar composition checks passed. Font substitution in the file
  fixtures is explicitly labelled Roboto Mono, not JetBrains Mono verification.
- The native Windows component test passed, with all three 2312×2580 theme
  captures reviewed and zero HTTP attempts:
  `build/performance/workspace-consistency/run-38ddbde0/manifest.json` and
  `build/performance/seven-fixes-native.log`. These are synthetic-data Flutter
  frame captures, distinct from the normal-app OS captures below. They do not
  exercise upload transport, OCR, code execution, Office or media playback.

### Repair Windows bundles and live audit

Both normal bundles completed, **Release first and Debug last**. The manifest
`build/performance/windows-bundles.json` was verified at
**2026-09-22 10:47:38.9824097 UTC**. Independent post-build hashing matched all
**4,813 inputs**, SHA-256
`2DE4E94B62084E7521C0B5E13820DFABD23606F0AFA6C86C41BA7CF0463D300D`.
Both executables and their Dart payloads are nonempty and newer than their own
build starts and the latest production edit. Functional parity checks confirmed
**1,179 matching assets and 36 native components**.

- Release: `build/windows/x64/runner/Release/AppFlowy.exe`
  (10:45:29.5356355 UTC); AOT payload 10:44:49.7205489 UTC.
- Debug: `build/windows/x64/runner/Debug/AppFlowy.exe`
  (10:47:15.0762490 UTC); kernel 10:46:37.8807445 UTC.

The user approved closing their saved Release app and reopening Release after
both builds. Normal close failed for the old windowless PID 31168; the user then
explicitly approved ending that process. Its executable, identity and windowless
state were checked before termination. No workspace, preference or cache reset
was performed.

The fresh normal Release process **37320** started at
**2026-09-22 10:48:43.5299959 UTC**, with verified Explorer parent and loaded
optimized backend SHA-256
`41BCFADFF55DA51A1F214ECED0D954C06E234CE810E863DA8D6948EB69A8C104`.
At **10:56:17.6290118 UTC** it remained responsive with a live main window.
No production inputs changed after the builds.

Normal-app 2066×1161 OS captures are under
`build/performance/seven-fixes-live/`. `startup.png` confirms the selected Home
dashboard and explicit sidebar Home, rather than restored crash tabs.
`profile-picker-settled.png` confirms that the top-left profile icon opens the
full picker; no icon was selected or saved. The actual gallery and Book Reader
were also captured (`library.png` and `current.png`).

**Live Books Reader → Files check remains unconfirmed.** Routes changed between
navigation captures, and the final frame showed a protected-file unlock prompt,
not the Files view. Automated input stopped there; no passphrase was requested,
read or submitted. This is not recorded as a manual regression pass or a crash.
The automated Books lifecycle tests passed, but do not substitute for that
remaining live check. Release was left open; the audit did not edit documents,
execute code, change an icon or bypass protection.

## Notion-inspired shell and sizing follow-up (22 September 2026)

This supersedes the earlier single-row shell and always-visible missing
decoration affordances, following the user's latest screenshots and request.

- The shell has a **40px title/tab strip** and **36px page-context row**.
  Sidebar identity, tab-strip background and native caption controls share the
  sidebar palette in Light, Dark and Paper. Tabs adjoin with no outer inset,
  shadow or floating box; the active face meets the content below. Sidebar,
  Back, Forward and Home controls stay together to the left of the tabs.
  Interactive controls remain outside native drag targets. Narrow overlay
  sidebars retain a local dismiss button when covering the shell controls.
- Every tab has an explicit close target, including a lone or pinned tab.
  Closing the last tab creates a safe Home destination. `+` and Ctrl/Cmd+T
  open a new Home tab; Ctrl/Cmd+N keeps its existing new-page action. Startup
  still opens Home rather than restoring the last page, with intentional
  newer manual/deep-link navigation taking precedence over delayed startup.
  Back/Forward also have Alt+Left/Right shortcuts.
- `PageManager.tabId` separates tab lifetime from page identity. Multiple
  Home tabs resolve independently, and pin/close commands target the exact
  tab. Loading placeholders resolve through Bloc events, with workspace,
  caller, disposal and replacement guards. Their history visits are replaced,
  not appended as invisible intermediate Back destinations. Existing real
  editor selection, drafts and page-manager keys survive tab reordering.
- Page artwork overlaps its cover by **22px in real layout**, with both ends
  of the icon hit-testable. Icon actions remain below the cover. Add Icon and
  Add Cover are hidden at desktop rest, revealed by header hover, keyboard
  focus, touch or accessibility needs, and held while their picker is open.
  Missing decoration is no longer a reason to pin its actions. The standalone
  file header scopes decoration reveal separately from renderer/media menu
  holds, so Copy/Share do not disappear while an originating menu is open.
- Folder and archive galleries now honor requested card widths instead of
  rounding every setting into the same stretched column width. At a 1697px
  folder width the old five-column cap produced 301px cards for every size;
  compact archives could likewise collapse all choices to 154px. The real
  slivers now use target-width grids, with responsive column counts and no
  forced last-row stretching. The existing compact scale remains. Preference
  writes are serialized; stale reads cannot roll back a newer choice, and a
  failed save restores the last acknowledged value.
- Dashboard Configure/More controls occupy their own stable layout slot,
  including on headerless widgets. They no longer overlay standalone calendar
  navigation or an embedded database's tab/settings row. Hover/focus does not
  move the body; dates, provider events, scroll controllers and widget drafts
  remain retained across sizing, appearance, mode and permission changes.

### Shell follow-up verification

- **3,015 selected tests / 100 files passed**, including normal golden
  comparisons: `build/performance/notion-shell-final-regressions.log`.
- **322 touched Dart paths analyzed with no issues**:
  `build/performance/notion-shell-analysis-final.log`.
- Six new 1280px/640px × Light/Dark/Paper shell references and three additional
  interaction/retention cases passed in `notion-shell-visual-render.log`.
  New calendar management references and the intentionally changed shared
  component/gallery/header images were rendered and reviewed; 49 generation
  checks passed in `notion-shell-approved-visuals.log`, followed by the normal
  comparisons in the final selected suite. Fixture and code-font limitations
  stated above still apply; these are not live-app screenshots.
- The native Windows three-theme component test passed:
  `build/performance/notion-shell-native.log`. All three captures in
  `build/performance/workspace-consistency/run-c184f93d/manifest.json` were
  reviewed; the inventory records zero HTTP attempts. These remain offline
  Flutter component captures, not normal-app window captures.

### Shell follow-up bundles and runtime

Both normal bundles completed, **Release first and Debug last**, with manifest
verification at **2026-09-22 16:40:34.4385984 UTC**. Independent post-build hashing
matched all **4,814 current inputs**, SHA-256
`26E8C60A668DA476F01206881C0DE46B3FF982B78D08105CAEF04E87F04A4C0F`.
All four executable/Dart payload artifacts are nonempty, unchanged after mode
switching, and newer than their respective build starts and latest production
source edit. Parity checks confirmed **1,179 matching assets and 36 native
components**, including the same optimized Rust backend.

- Release: `build/windows/x64/runner/Release/AppFlowy.exe`
  (16:38:02.6069703 UTC); AOT payload 16:37:21.5702203 UTC.
- Debug: `build/windows/x64/runner/Debug/AppFlowy.exe`
  (16:40:08.9404947 UTC); kernel 16:39:25.6533089 UTC.

Normal Release **PID 31900** started at **16:44:33.7642147 UTC**, with verified
Explorer parent, correct executable path and loaded optimized backend SHA-256
`1F7A7464430AF387AFA9C32C6997D8C045DE24BD42D82C233D2EA89BC799BF94`.
At **16:48:38.4889562 UTC** the process remained responsive with a main window.
No existing user app was closed for this round, and no workspace, preference or
cache reset was performed. No production inputs changed after the builds.

**Normal-app visual/navigation inspection blocked:** Windows returned blank
off-screen captures and foreground handle zero, including after one targeted
activation attempt. `build/performance/notion-shell-live/startup.png` and
`foreground.png` are therefore neither proof of the new Home/tab UI nor evidence
of an application crash. No keyboard input or blind clicks were sent. Release
was left running; actual new-tab/last-tab-close and gallery/calendar navigation
still need live confirmation. The passing widget/native fixture checks above
are separate evidence, not substitutes for that inspection.

## Vivid coverage and gallery depth (23 September 2026)

- **Vivid is the device default** for a new/unset or unrecognized preference.
  An explicitly saved Monochrome choice remains honored. Reads and writes keep
  the existing acknowledgement, serialization and retry rules; no preferences
  or saved page icons are migrated or overwritten.
- Every known shared default glyph now resolves to Vivid artwork: recognizable
  object illustrations for common actions, and matching-geometry multicolor
  gradients for utility marks. Search, Settings, notifications, slash menus,
  context menus, table fields and page/settings actions share this resolver.
  Unknown third-party symbols still retain their supplied renderer.
- The selectable Vivid catalogue grows from **56 to 150 original icons in
  12 categories**: Essentials, Navigation, Editing, Data, Work, Security,
  Learning, Nature, Travel, Food, Health and Technology. Original Essentials
  identities/artwork remain compatible. Utility variants do not inflate the
  picker count. Search, random choices and saved group/name round trips are
  exercised through the actual picker.
- Remaining ordinary gallery, search-clear and file/control leaves use the
  shared renderer. Explicit roles distinguish decorative Run/Add emphasis from
  Stop, Delete, disabled and success/failure ink. Cupertino search retains its
  native controller and clear button, with a localized accessible label. Saved
  emoji, uploaded artwork, selected library icons, swatches and native toggles
  retain their own rendering and meaning.
- Folder/archive cards have a distinct theme-derived sheet, softly washed
  footer, 0.75px neutral edge and restrained contact/ambient shadows. Paper
  keeps warm cream surfaces rather than white or cool grey. Hover/focus adds
  depth over 140ms without translating, scaling or moving hit targets; reduced
  motion snaps the paint. The existing selection ring and renderer, draft,
  caret, controller and scroll ownership remain intact.

### Vivid/gallery verification

- **3,035 selected tests / 104 files passed** with normal golden comparisons:
  `build/performance/vivid-gallery-final-regressions.log`.
- **349 touched Dart paths analyzed with no issues**:
  `build/performance/vivid-gallery-analysis-final.log`.
- All six new Vivid catalogue/chrome sheets and three gallery-depth sheets were
  rendered and reviewed in Light, Dark and Paper. The catalogue covers all 150
  saved identities at 32px; chrome covers actual sidebar/context/slash/field
  widgets and 16/18px utility marks. Existing affected component references were
  reviewed before regeneration and passed the final normal comparisons.
- The offline **native Windows component check passed**:
  `build/performance/vivid-gallery-native.log` (01:01, one integration case
  capturing three themes). All three native captures were reviewed; inventory
  `build/performance/workspace-consistency/run-46c57332/manifest.json` records
  zero HTTP attempts. Fixture data, native-boundary exclusions and the disclosed
  Roboto Mono substitution remain distinct from live-app evidence.

### Vivid/gallery bundles and runtime

Both normal bundles completed, **Release first and Debug last**, with manifest
verification at **2026-09-23 04:25:47.8217983 UTC**. Independent post-build
verification at **04:26:48.8243199 UTC** rehashed all **4,816 current inputs**,
matching SHA-256
`473A908CC2F24463805194CAB104DB67006D450167080C63499CF14C74A0E1BA`.
All four executable/Dart artifacts are nonempty, unchanged after mode switching,
and newer than their own build starts and the latest production edit. Parity
checks confirmed **1,179 matching functional assets and 36 native components**.

- Release: `build/windows/x64/runner/Release/AppFlowy.exe`
  (04:23:37.1698673 UTC); AOT payload 04:22:51.9914427 UTC.
- Debug: `build/windows/x64/runner/Debug/AppFlowy.exe`
  (04:25:22.8269259 UTC); kernel 04:24:46.8024711 UTC.

Normal Release **PID 31124** started at **04:27:21.4375630 UTC** through Explorer
desktop automation. The actual parent is Explorer, its executable path matches
the verified Release bundle, and its loaded optimized backend matches SHA-256
`77C348C9D0F7C739F0E975764290B35E5F0C8E1D24635C69266AF0B3309B7179`.
At **04:27:59.5416306 UTC** it remained responsive with a main window. No existing
user app was closed, and no workspace data, preferences or caches were reset.
No production inputs changed after the builds.

**Live visual/navigation inspection remains blocked:** both OS-window captures
in `build/performance/vivid-gallery-live/{startup,activated}.png` are blank,
and Windows reports foreground handle zero even after one targeted activation
attempt. This is neither proof of the new live UI nor a diagnosis of an app
crash. No keyboard input or blind clicks were sent. Release is left running for
user confirmation of the new icons and gallery appearance; the passing widget
and native component checks above remain separate evidence.

## Subtle Vivid actions and consistent folder embeds (23 September 2026)

- Refined **28 recently added Vivid action symbols**, including Add, Refresh,
  Copy, Search, Settings, upload/download, formatting and field controls. Thin
  2.0/2.2px rounded strokes on transparent 32px canvases replace heavy filled
  silhouettes, with restrained two-tone palettes. The original 56 Essentials
  illustrations and the 150 saved catalogue identities remain unchanged.
- The editor grip has its own six-dot vertical geometry instead of borrowing
  the three-dot overflow symbol. Editor action artwork is 18px inside the same
  28px hit target; hover uses the shared subtle wash and reduced-motion policy.
  Tab and database-view Add buttons retain native geometry, keyboard activation,
  permission guards and popup behavior. Disabled/destructive/status ink remains
  distinct from decorative Vivid artwork.
- Plain-folder and folder-collection embeds now render children through
  `FolderGalleryPreviewThumbnail`, `GalleryCardSurface` and `GalleryCardFooter`.
  They no longer use ID-hashed colored backgrounds and generic Material folder
  silhouettes. Real document/text/markdown previews, typed file/collection
  identities, saved icons and cover/content precedence match the gallery.
  List rows use the shared identity renderer, without loading thumbnails.
- A lazy, 60-entry controller-owned preview cache survives hover, appearance,
  layout, sorting and size changes. Adopted refreshes invalidate old futures;
  per-child Retry does not reload peers. Root/controller replacement detaches
  old state, and stable item keys preserve eligible loaded renderers across
  reorders. Folder counts use already supplied child metadata, never extra
  enumeration or an invented unread zero. Saved settings and protobufs are
  unchanged. Other specialized collection-embed artwork remains untouched.

### Subtle-action/embed verification

- The final main regression suite passed **3,125 tests / 106 files** with normal
  golden comparisons: `build/performance/subtle-icons-embed-final-regressions.log`.
  The supplementary dashboard-resource lifecycle and collection-embed suites
  also passed in the editor test runner (**55 reported checks**); that count is
  recorded separately rather than added to the CLI total.
- **353 touched Dart paths analyzed with no issues**:
  `build/performance/subtle-icons-embed-analysis-final.log`.
- **98 focused tests passed**, including all new action and embed tests and the
  six Vivid catalogue/chrome sheets. Three new folder-embed comparison sheets
  were reviewed alongside actual gallery cards in Light, Dark and Paper.
  Small-size pixel checks caught and corrected an overly faint 16px grip.
  All 36 affected older image differences were reviewed before regeneration;
  the main suite then passed normal comparisons.
- The native Windows component check passed (01:00, one three-theme case):
  `build/performance/subtle-icons-embed-native.log`. All three captures in
  `build/performance/workspace-consistency/run-85507617/manifest.json` were
  reviewed; zero HTTP attempts. The existing fixture/native-boundary and
  disclosed code-font limitations still apply. New embed tests use real image
  decoding and content renderers, but do not claim native PDF/video playback,
  upload transport or live editor interaction coverage.

### Subtle-action/embed bundles and runtime

Both normal bundles completed, **Release first and Debug last**, with manifest
verification at **2026-09-23 08:06:40.0164418 UTC**. Independent verification at
**08:08:37.9263042 UTC** rehashed all **4,816 current inputs**, matching SHA-256
`65C2D072327E94AB892103106C9D9330C74247485E1B6E3930F6835E7DAAF5FC`.
All four executable/Dart artifacts remain nonempty and newer than their own
build starts and the latest production edit. Functional parity remains
**1,179 matching assets and 36 native components**.

- Release: `build/windows/x64/runner/Release/AppFlowy.exe`
  (08:04:26.3229645 UTC); AOT payload 08:03:46.0277125 UTC.
- Debug: `build/windows/x64/runner/Debug/AppFlowy.exe`
  (08:06:14.2800135 UTC); kernel 08:05:36.8808878 UTC.

Normal Release **PID 14172** started at **08:09:01.6167299 UTC** through Explorer
desktop automation, with verified Explorer parent and executable path. Its
loaded optimized backend matches the build SHA-256
`E7A7BEC057EE0F0CAFEF5C890B684BDE4205B1A00014DDAE390C53AC257901C0`.
At **08:09:30.5549427 UTC** it remained responsive with a main window. No existing
app was closed, no workspace content/preferences were reset, and no application
inputs changed after the builds.

**Live visual/navigation inspection remains blocked:** Windows returned blank
captures in `build/performance/subtle-icons-embed-live/{startup,activated}.png`
and foreground handle zero after one targeted activation attempt. No clicks or
keyboard input were sent. These captures do not prove either correct live
rendering or an app failure. Release is left open for user confirmation of the
subtle controls and folder-embed previews; automated themed evidence is recorded
separately above.

## Charts, contextual Find and local OCR (25 September 2026)

- Chart controls wrap instead of clipping. Hover readouts are integrated
  annotations, bounded away from axis labels and zoom controls at 2× text
  scale. Richer marks retain saved colors, transparent canvases, Paper
  surfaces, reduced motion and live-refresh interaction state.
- Ctrl/Cmd+F routes to visible hovered, focused or selected documents, PDFs,
  spreadsheets, file previews and images. Default matching ignores case.
  Document matches refresh after edits; replacement preserves ownership,
  permissions, text attributes and undo boundaries.
- Scanned PDF matches supplement native PDF text search. Image OCR Find supports
  recognized-word selection and match navigation; only explicit copy actions
  write the clipboard. Cancellation and source changes reject late results.
  Windows paths are canonicalized before WinRT reads the OCR image.
- Webview Find matches text across inline formatting and rejects stale query
  results. Windows may deliver distinct public wrappers for the same native
  controller; comparing the underlying platform object fixes load-complete
  callbacks previously being rejected as stale.
- Bookmark tools align right and retain notes drafts across layout changes.
  PDF page input is centered; its corner Change Icon button is removed, while
  More retains icon editing. Find and non-protective popups dismiss outside
  without stealing the clicked target's focus. Protective dialogs retain
  their existing policies.

### Verification and limitations

- **4,367 tests / 147 selected files passed** in
  `build/performance/chart-find-final-verified-regressions.log` (08:21).
  This includes normal golden comparisons except the three deferred cases
  below. After the final lint-only edit, all **15 file-icon regression cases**
  passed again in `build/performance/chart-find-final-lint-retest.log` (00:14).
- The current native fixes and updated tests have clean analysis in
  `build/performance/chart-find-final-analysis-cleanup.log`; earlier
  `chart-find-final-analysis-0..6.log` and the subsequent cleanup cover the
  wider touched source set. These are scoped checks, not whole-repository
  cleanliness claims.
- **All three native Windows scenarios passed** in
  `build/performance/chart-find-native-3.log` (00:10): real Windows image OCR,
  PDFium text plus scanned-page OCR/highlighting, and WebView2 HTML search
  across formatting with case-option changes. They use synthetic files and
  isolated webview data. Six PDF/image captures are in
  `build/performance/chart-find-native/run-54ecbfce/`. Flutter-host keyboard
  routing is tested; OS-to-webview key delivery is not claimed verified.
- The production JavaScript DOM test passed with jsdom installed only in
  `.dart_tool/chart-find-dom`, without changing application dependencies.
- **Three visual baseline comparisons remain deferred:**
  `test/widget_test/chart_integrated_golden_test.dart`. Copilot's attachment
  service returned image-download 404s, blocking reliable final visual review.
  These comparison tests and their existing baselines are left unchanged;
  they are explicitly excluded from the 147-file gate, not marked passed or
  silently accepted. Full live visual verification is not claimed.

### Chart/Find normal bundles and startup

Both normal bundles completed, **Release first and Debug last**, targeting
`lib/main.dart` rather than the native integration fixture. The build manifest
was verified at **2026-09-25 00:21:10.9224779 UTC**. Independent verification
rehashed all **4,819 current inputs**, matching SHA-256
`3873A878515E9405BE526B81F2BCFA3BFF492FA81A05C067647DD1DDF90A9F0F`.
Both executables and their Dart payloads are nonempty, newer than their own
build starts and the latest production edit, and unchanged after mode switching.
The independent check was repeated before launch at **00:22:59.6970461 UTC**.
Artifact hashes are recorded in
`build/performance/chart-find-bundle-verification.json`.

- Release: `build/windows/x64/runner/Release/AppFlowy.exe`
  (00:17:44.6769813 UTC); AOT payload 00:16:50.7872039 UTC.
- Debug: `build/windows/x64/runner/Debug/AppFlowy.exe`
  (00:20:42.5969241 UTC); kernel 00:19:42.0091373 UTC.

Parity checks confirmed **1,179 matching functional assets and 36 native
components**, including the same optimized Rust backend SHA-256
`989D3C4D850AA384602C18041B99C2DE967E19FDBDC24E14920B0C3F2317EC26`.
Build logs are `windows-rust-release-build.log`, `windows-release-build.log`
(315.9s) and `windows-debug-build.log` (155.6s), under `build/performance/`.

Normal Release **PID 32656** started through Explorer at
**2026-09-25 00:22:59.9617485 UTC**. At **00:24:46.8211302 UTC**, the process
still had a responsive main window, the expected executable path, an Explorer parent
and the verified optimized backend loaded. The runtime report is
`build/performance/chart-find-release-runtime.json`.

No existing app was closed, no workspace content or preferences were reset,
and no production inputs changed during or after the builds. Temporary
verification/launch tasks were removed while preserving the existing tasks.
Release is left running. This confirms normal startup, not a completed live
visual/navigation audit; the three deferred visual comparisons above remain
unapproved and unchanged.

## Image/page Find, file-browser views and file headers (25 September 2026)

- Image Ctrl+F now opens OCR Find when the pointer is over an image even if
  a navigation button still owns focus. Real embedded, standalone and fullscreen
  image hosts reproduced the original no-op. Only image regions opt into this
  control-focus override; editable fields, native webviews, inactive routes and
  protective overlays retain their ownership rules. Hover itself never moves
  focus or selection.
- Page Find includes the actual title, body, nested text/table blocks, embedded
  page text, authorized database display values, spreadsheet display values and
  supported imported text/code/Markdown/HTML/CSV/JSON files. Title highlighting
  is paint-only. Row pages bind to their real primary-cell controller and actual
  document identity, not the table name or an orphaned document title. Revealing
  a title accounts for the Find panel's measured height.
- Referenced hits navigate to the owning embed and show a highlighted location
  and snippet. Replacement remains restricted to writable body deltas in the
  current document; it never silently edits a title, cell or referenced file.
  Row editing authority derives from the current table access/lock state and
  fails closed while metadata or permission reads are pending.
- External indexing is deliberately bounded: depth 3, 24 views, 2,048 text
  entries, 512 KiB total text and 256 KiB per local file. A shared native-read
  scheduler prevents close/reopen from starting overlapping stuck reads. The
  three-second UI deadline rejects stale results but does not claim to cancel
  an unfinished native operation. Permission checks bracket reads; local file
  access stays within the active imported-files directory, rejecting traversal
  and symbolic-link escapes. No arbitrary filesystem or workspace-wide crawl
  is performed. Relations, encrypted/unsupported media, remote content and
  incomplete native membership/cell coverage are reported as partial rather
  than being presented as a complete zero-result search. Page-wide Find does
  not run OCR on every embedded image; image Find remains the OCR entrypoint.
- Ordinary folders, folder embeds and archives share **Gallery, Thumbnails,
  Tiles, List, Details, Columns and Tree** presentations inline and fullscreen.
  Tiles use a leading file identity beside real type/size/date metadata, without
  heavyweight per-tile previews. The existing controllers, listings, selection,
  rename drafts, keyboard navigation and mutation callbacks remain the owners.
  Presentation changes merge existing metadata; read-only hosts allow session
  choices without unauthorized writes. Archive layout changes do not rewrite
  ZIP contents. Specialized provider-backed folder screens are not claimed to
  have received an independent redesign or native verification.
- Archive icon editing uses the normal top-left identity; the duplicate
  bottom-left Change Icon control is removed. Existing picker/source/access
  guards and the same saved icon model are retained.
- Standalone file tools measure their actual width and align to the trailing
  16px content gutter, instead of occupying a fixed 52% start-aligned slot.
  Narrow layouts wrap without replacing editors or losing drafts. Add Cover
  sits above the filename consistently across standalone file types; saved
  covers remain above the identity. Source Copy and original-file Copy retain
  their distinct purposes. Light, Dark, Paper and enlarged text are covered by
  geometry, accessibility and retention tests.

### Find/browser validation status

- **4,668 tests / 154 selected files passed**: 4,667 checks across 153 files
  in `build/performance/find-browser-final-regressions.log` (08:01), plus the
  separate, disjoint DOM test in `find-browser-final-dom.log` (00:07). Explicit
  file inventory: `find-browser-regression-files.json`. The selected suite
  includes unaffected normal golden comparisons, not the deferred cases below.
  Windows' batch argument limit is avoided by invoking the bootstrapped Flutter
  tools through Dart for the long file list. The DOM child has the same bounded
  deadline, now covering input/output pipes as well as exit, with cleanup.
- Scoped application/test analysis is clean, including the initial **136-path**
  analysis and subsequent targeted cleanups. The focused image/router/page/header
  run passed 318 checks, the title/row-host run passed 166, and the updated browser
  compatibility suites passed 116. These overlap the final suite and are not
  added to its total.
- The native image-host fixture passed **all six cases in Release and all six
  in Debug**: page, standalone and fullscreen images, each with and without
  retained navigation-button focus. Reports:
  `build/performance/image-find-native-{release,debug}.json`, verified at
  **15:58:47.843810 UTC** and **16:01:53.405452 UTC** respectively. Native builds
  took 199.7s and 162.9s; both synthetic processes exited normally.
- The first Release attempt exposed a test-only Flutter 3.27 physical-key
  inference failure: Release strips the debug names the simulator uses. The
  fixture now supplies explicit physical Ctrl/F/Escape keys and retains all
  production-host assertions. The six widget cases passed again after this
  change; targeted analysis is clean. No application routing change was made
  for this test harness failure.
- Native cases use real image hosts and Flutter key dispatch with injected OCR
  results. They verify opening, query results, focus, dismissal and retained
  owners—not fresh OCR recognition accuracy or OS-to-WebView key delivery.
  The earlier native OCR/PDF/WebView checks are separate historical evidence.
  Final read-only source review found no further permission, stale-owner,
  replacement or borrowed-title-controller blockers.

Normal bundle verification is recorded separately below; the earlier Chart/Find
binaries do not validate this follow-up.

**Visual review remains deferred, not approved.** Current normal comparisons
report differences in the three `file_controls_visual_test.dart` sheets and
the three `workspace_consistency_visual_test.dart` sheets. Their functional
geometry/retention checks reached the image comparisons. One fresh Paper-image
review attempt still returned only a cached attachment reference, so no further
image retries or unseen baseline updates were made. These six comparisons and
the three historical `chart_integrated_golden_test.dart` cases are explicitly
separate from the selected functional gate. Existing references remain unchanged;
no complete live visual audit is claimed.

### Find/browser normal bundles and runtime

Both normal bundles completed, **Release first and Debug last**, targeting
`lib/main.dart`. The build manifest was verified at
**2026-09-25 16:23:04.6689548 UTC**. Independent verification was repeated before
launch at **16:23:14.5433860 UTC**, rehashing all **4,828 current inputs** to
SHA-256 `DD53167F52425FAE03BFF583EDAE2CA19F72ECD214DDC7E28ABF7D8CFC56BA69`.
Both executables and both Dart payloads are nonempty, newer than their respective
build starts and latest application edit, and unchanged after mode switching.
Artifact hashes: `build/performance/find-browser-bundle-verification.json`.

- Release: `build/windows/x64/runner/Release/AppFlowy.exe`
  (**16:20:16.6091805 UTC**, 132,096 bytes); AOT payload
  **16:19:34.2166451 UTC**, 51,790,752 bytes. Build: 419.3s.
- Debug: `build/windows/x64/runner/Debug/AppFlowy.exe`
  (**16:22:37.5661935 UTC**, 1,116,672 bytes); kernel
  **16:21:53.2693852 UTC**, 191,114,640 bytes. Build: 115.4s.

Parity checks confirmed **1,179 matching functional assets and 36 native
components**, including the same optimized Rust backend SHA-256
`EDCDE14E25420955080778790EEF8017C1F67E48D9B2F580B258E1F227480728`.
Normal build logs are `windows-rust-release-build.log`,
`windows-release-build.log` and `windows-debug-build.log` under
`build/performance/`. Neither final executable points at the image-test fixture.

With the user's saved-work/reopen permission, fresh normal Release **PID 18616**
started through Explorer at **16:23:14.6953102 UTC**. At
**16:24:16.3598063 UTC** it remained responsive with a main window, the correct
executable, Explorer parent and verified optimized backend loaded. Runtime
report: `build/performance/find-browser-release-runtime.json`.

Release is left open. No user app was force-killed, no workspace data or
preferences were reset, and no production inputs changed during or after the
builds. Final diff integrity is clean and no compiler/test processes remain.
The nine explicitly deferred visual comparisons above remain unapproved;
successful runtime verification is not a claim of complete live visual review.

## Active-page Find and stable folder views (25 September 2026)

This supersedes the preceding image-only navigation-focus exception and the
two separate Gallery/Explorer page shells.

- `PageStack` marks the active content with a passive `ContextualFindScope`.
  Ctrl/Cmd+F can reach its outermost visible owner immediately after navigation,
  without a click or caret in the document. Hover can choose a more specific
  viewer while navigation controls retain focus; it never moves focus itself.
  An ancestor navigation route is compatible with its nested content Navigator.
  Hidden tabs, modal routes, native viewers and unrelated editable inputs retain
  the existing protections; ambiguous independent panes are not chosen by
  registration order.
- Folder and collection search registers its existing field and controller.
  Collection search reveals the whole field minimally before focusing it;
  top-aligning an already-visible inner editable had scrolled and clipped the
  field. Archive search uses the same router, including its published sibling
  toolbar. Its header stays mounted when switching presentation modes.
- Native Grid/Board/Calendar and alternative database pages now have a read-only
  Find host bound to the actual selected view. It searches the authorized title,
  column names and saved typed cell values, with highlighted location snippets,
  match counts and navigation. It does not mutate filters, open another database
  controller, replace cells, or claim to include unsaved cell drafts. Snippet
  navigation does not open a row. Unsupported/partial coverage and timeouts are
  visible; two-sided authorization, invalidation generations, bounded text and
  the shared unfinished-native-read slot remain enforced.
- Opened image stages in archives, repositories, provider file dialogs and local
  album lightboxes join the existing image OCR entry point. They read the actual
  displayed/materialized local file and reject stale sources; thumbnails and
  audio/video are not made OCR targets. Provider folder Find filters only the
  already-loaded current-folder names/types, without a new network search.
- All seven ordinary folder modes share one retained identity, cover, breadcrumb
  and action strip, a bounded reading measure, and the same themed canvas.
  The mode selector remains available; contextual actions still reveal on hover,
  keyboard focus or active search. Creation and identity rights stay separate.
  Controllers, loaded listings, cached previews, selection and native drafts
  remain owned by their existing hosts. A mode switch is refused during an
  unfinished rename/create draft.
- Gallery keeps preview cards and metadata. Thumbnails is now a denser contact
  sheet of square previews with names underneath, without Gallery's card footer.
  Its density is separate from Gallery's saved card-size preference. The same
  distinct face is used by folder embeds and archives; preview futures remain
  shared. Tiles use bounded-width icon/name/metadata groups and readable type
  labels rather than exposing generic MIME strings as the primary description.

### Follow-up verification notes

The fresh routing tests reproduce the earlier no-hover/navigation-focus failures.
Real-host tests use `PageStack`, `AppFlowyEditorPage`, `CoverTitle`, folder and
collection widgets—not a test-only Find callback in place of their search UI.
Native data/OCR boundaries are injected; no normal integration startup, user
workspace writes, preference resets, code execution or network downloads are
performed by these fixtures.

The final selected functional run passed **4,778 tests across 159 files** (11:27),
recorded in `build/performance/active-page-final-regressions.log`. The explicit
160-file inventory includes the separately unresolved DOM test; the functional
run excludes it and only the three named image comparisons within the folder
embed suite. The previously deferred visual suites remain outside that inventory.
No image references were regenerated. Earlier action-reveal/permission failures
were corrected rather than excluded. This final run followed all native-test
corrections below and used the same frozen application sources as both builds.

During validation, native Release verification exposed a real pending-focus race in
the database host. Its post-frame Find request could see the old primary focus
while a newer request was still queued. It now resolves pending changes with
the public `FocusManager.applyFocusChangesIfNeeded()` API, then rechecks the
owner/epoch and focus before acting. A same-frame regression fails before the
fix and passes afterward; **163 focused routing/search tests** pass on the final
correction (`active-page-pending-focus-{before,after}.log`). Scoped analysis of
all 38 changed Dart paths, including the final targeted corrections, is clean.

The native fixture's first OS-input attempt was **blocked**: Windows refused to
foreground its owned window, so no Ctrl+F was sent. The foreground safety check
is unchanged. Separate `-FlutterKeySimulation` runs use distinct `-flutter-keys`
reports and do not claim OS key delivery. Release-only fixture corrections avoid
the debug-only platform override and inspect the real attached semantics tree
instead of `RenderObject.debugSemantics`, which always returns null in Release.
Accessibility, focus, text editing and state-retention assertions stay enabled.
The final native fixture passed **57/57 cases in Release and 57/57 in Debug**:
12 image cases, eight actual document/folder/collection hosts, and 37 database
Find/guard regressions. Reports are
`build/performance/image-find-native-{release,debug}-flutter-keys.json`, verified
at **2026-09-26 01:22:52.113485 UTC** and **01:27:14.037287 UTC** respectively.
Both owned synthetic processes closed normally. Builds took 285.0s and 142.9s.
These are Flutter-dispatched keyboard checks in actual native bundles, **not**
OS input verification or tests against the user's live database.

The last Debug failure was a test's fake-clock assumption, confirmed by a
non-invasive timer trace: on reopen the pending count became one, the existing
30ms deadline then expired (about 31ms later), cancelled that queued request, and
left the original native operation in flight. The native frame returned after
the expiry, while a widget-test pump had frozen the clock between those points.
The test now asserts pending count, status, in-flight count and unchanged reads
at the actual enqueue and before/after deadline boundaries. Timer durations,
real scheduler, held read, late-result rejection and successful Retry are
unchanged; no production timeout or concurrency rule was relaxed. The final
57 shared widget checks also pass (`active-page-timeout-final-widget.log`), and
both changed test files analyze cleanly (`active-page-timeout-final-analysis.log`).
Normal application bundles are verified separately below.

The three folder-embed comparison fixtures now allocate 198px for the new 128px
square plus caption and padding. Strict containment and zero-scroll-extent checks
reach the image comparisons; their remaining failures are pixel differences,
not geometry failures (`active-page-embed-visual-comparison.log`).

Exploratory three-theme/seven-mode folder captures are saved under
`build/performance/folder-shell-{theme}-{mode}.png`. Image delivery still returns
only cached attachment references, so these have **not** been visually approved.
These captures precede the final action-reveal correction unless recaptured.
The three folder-embed comparisons and the earlier nine deferred comparisons
retain their original reference images. The unchanged external Node/jsdom Find
test also exceeded its existing 20-second deadline in two isolated runs; its
deadline/assertions were not relaxed. These limitations are not reported as
passing tests or evidence of an AppFlowy image-loading fault.

### Active-page follow-up: normal bundles and runtime

Both normal `lib/main.dart` bundles completed **Release first, Debug last**, in
343.6s and 152.8s. The manifest was verified at
**2026-09-26 02:02:34.5751484 UTC**; independent verification before launch at
**02:02:44.3848505 UTC** rehashed **4,830 inputs**, with SHA-256
`B39228E3834606B00D02304CBFF42DBF7E0F8A55C6079F66B7B7FA717E41002C`.
All four artifacts are nonempty, newer than their build starts and latest
application edit, and unchanged after mode switching and the final recheck.

| Artifact | Modified UTC, 26 September 2026 | Bytes |
| --- | --- | ---: |
| `build/windows/x64/runner/Release/AppFlowy.exe` | 01:58:59.4144084 | 132,096 |
| `build/windows/x64/runner/Release/data/app.so` | 01:58:14.0560981 | 51,856,288 |
| `build/windows/x64/runner/Debug/AppFlowy.exe` | 02:01:56.3795884 | 1,116,672 |
| `build/windows/x64/runner/Debug/data/flutter_assets/kernel_blob.bin` | 02:00:59.2321992 | 191,250,024 |

Parity checks confirmed **1,179 matching functional assets and 36 native
components**, including the optimized Rust backend SHA-256
`227137F96DD9EFBFF50E126BCC4C1BC0D5B7937C3843ECD51F93D9BE4B2E833D`.
Neither final bundle contains the synthetic test entry point. Artifact hashes
and current-input checks are in `build/performance/active-page-bundle-verification.json`;
the final independent verification log is `active-page-final-verification.log`.

Fresh normal **Release PID 39248** started through Explorer at
**02:02:44.5644881 UTC**. At **02:03:55.5523027 UTC** it remained responsive, with
the correct Release executable, Explorer parent, main window and verified
backend loaded. Report: `build/performance/active-page-release-runtime.json`.
Release is left open. No existing user app was force-closed, no workspace data
or preferences were reset, and no application inputs changed after verification.
No compiler/test process remained at the final check; diff integrity is clean.

The requested fixes are delivered with the explicit verification limitations
above: **12 unapproved image comparisons, one unresolved Node/jsdom timeout,
and no successful OS-level Ctrl+F delivery audit**. Native Flutter-key checks
and normal runtime responsiveness are not claims of a full live visual audit.