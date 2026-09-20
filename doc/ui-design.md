# UI direction: calm workspace, richer content

Reference for the visual/experience refinement (September 2026).

## Intent

Borrow Notion's quiet writing surface and Capacities' clear object identity,
without changing AppFlowy's organisation model. Preserve the warm paper theme
alongside ordinary light and dark appearances.

## Rules

- Content leads; navigation and tools stay compact and predictable.
- Share typography, spacing and interaction roles, not a single layout for every
  kind of page. Documents have expressive titles; collections have compact ones.
- Keep the existing soft, borderless media cards. Avoid extra nested frames,
  decorative gradients, heavy shadows and app-wide glass effects.
- Hover must not move text or change control geometry. Keyboard focus must be
  visible and offer the same actions as the pointer.
- Reuse `PremiumThemeExtension`, `PaperTheme` and `EditorSurfaceStyle`. Never
  introduce white/cool-grey patches into paper mode.
- Preserve content, chosen covers, saved preferences, editor state and scrolling.

## First pass

1. Put Windows tabs in the existing title bar; keep native caption controls and
   window dragging. Give tabs readable widths, overflow access, reordering and
   stable selection when another tab closes.
2. Turn collapsed breadcrumb ancestors into a usable picker.
3. Share page/collection title styling and make collection controls and view tabs
   fit narrower panes.
4. Offer Reading / Wide / Full document-width presets, explicitly application-wide;
   retain the custom width slider and existing saved values.
5. Align the remaining touched chrome with theme-aware surfaces and quiet states.

## Verification and boundaries

Check light/dark/paper, narrow panes, long titles, many/pinned tabs, keyboard
navigation, reduced motion and persistence. Test changes; build Release then
Debug on Windows and verify fresh executables and runtime payloads.

Universal object types, backlinks, new property models and renderer/scroll-engine
rewrites are outside this visual pass. Refine further screens using these rules
after reviewing the first pass in the running app.

## Two-finger navigation

- Swipe right for Back, left for Forward; commit once on release after a
  deliberate horizontal gesture, not vertical scrolling, a pinch or a mouse drag.
- AppFlowy follows workspace visits (not tab order); new visits clear the forward
  branch and workspace switches reset the session history.
- Inside bookmarks, use the website's own history. Horizontal tables and custom
  pan/zoom viewers retain their gestures, including at scroll boundaries.
- During a horizontal swipe, the page follows the fingers over a read-only
  preview. Release completes the slide or returns the same page to rest.
- At either end of history, show a resisted nudge and "No previous page" /
  "No next page" instead of silent failure. Reduced motion keeps the cue without
  moving the page. Previews are bounded, memory-only, and never retained for a
  workspace with vault protection enabled.
- Sidebar swipes drive the page pane's feedback without shifting the sidebar.
  HTML/Markdown reading previews opt into boundary feedback while their own
  pan guard keeps all scrolling; they do not acquire bookmark website history.
- Incoming viewers initialize at their final coordinates behind the transition
  preview. File loads retain their own identity and never display the previous
  file's content while waiting. Windows HTML/Markdown uses a private loopback
  resource origin for relative images, fonts and styles; a genuinely unavailable
  remote image cannot be repaired by a redraw or history replay.
- Sleep/wake recovery is a separate application lifecycle issue, not a history
  gesture feature.

## Responsive foundation (September 2026)

### Verified source-level causes

- The desktop page body wraps each block's action row in editor padding. The
  actual `BlockActionList` occupies **63 logical pixels**: two unchanged 28px
  targets, a 2px inter-button gap, and a 5px trailing gap. The legacy
  `EditorStyleCustomizer.optionMenuWidth` is 44px, not that row's width.
  With the previous main-page padding of left 40/right 84, body content began
  at 103 and ended 84px before the page edge. The title/cover added 44 to both
  sides instead, beginning at 84 and ending 128px before the edge. That was a
  19px leading mismatch and a different trailing reading edge.
- Cover toolbar positioning separately read `editorState.renderBox` from a
  previous layout, retried after the first frame, and consulted the saved width
  rather than sharing the current page's resolved geometry.
- `HomeLayout.menuIsDrawer` was not initialized when the menu was collapsed;
  sidebar width had a minimum but no available-space maximum. Shell layout used
  window width, the drawer threshold was 768 while the bloc's threshold was
  1024, and notification dismissal width did not subtract the sidebar offset.
- `WorkspaceHeaderLayout` handed infinity to its children in unbounded hosts.
  Its fixed text-scale cutoff also stacked even very wide layouts, rather than
  allowing enough space for the larger controls.
- The title's first-line measurement omitted the current text scaler, so the
  icon alignment calculation could disagree with the rendered title.

### Changes and expected measurements

`shared/workspace_layout.dart` contains pure, theme-independent logical-pixel
calculations. The main document resolves its width from the actual pane's
`LayoutBuilder`: `pageWidth = min(paneWidth, savedMaxWidth)`. The saved maximum
still includes margins; no document, font, embed, or database-column preference
is rewritten. At supported desktop widths the equal reading insets are
`clamp(pageWidth * 0.1, 64, 96)`. Body padding subtracts the **real** action gutter
on the leading side only (mirrored in RTL). `DocumentHeaderContent` is shared by
cover and title and adds that gutter back, with no previous-frame measurement.
An existing title icon remains beside the text; the identity group's outer
edge, not the text after the icon, aligns with the body's reading edge.

For saved maximum 1920, the formulas give the following expected logical
measurements (not native screenshot measurements):

| Pane width | Page width | Inset within page, each side | Reading width | Reading left within pane |
| ---: | ---: | ---: | ---: | ---: |
| 320 | 320 | 64 | 192 | 64 |
| 480 | 480 | 64 | 352 | 64 |
| 800 | 800 | 80 | 640 | 80 |
| 1280 | 1280 | 96 | 1088 | 96 |
| 1920 | 1920 | 96 | 1728 | 96 |
| 2560 | 1920 | 96 | 1728 | 416 |

The same logical width has the same geometry at DPR 1 and 2. Text scaling does
not change stored font sizes or the action targets. The header allocates space
using the effective scale at 14px, with an 840px base split threshold and
24px/12px horizontal/vertical gaps. It retains the same Wrap and child slots
while stacking; unbounded hosts receive a finite fallback width.

The shell and its bloc share the **1024 logical-pixel** drawer threshold. At or
above it, a 320px main-content budget is reserved before allocating sidebar/edit
panels. Below it, those positioned panels overlay rather than squeeze the
editor and reserve at least 32px of outer clearance when space permits. Example:
a remembered 460px
sidebar beside a 400px edit panel renders at 304px in a 1024px shell, then
returns to 460px when space returns. No resize preference is saved on a window
resize. Constrained/drawer offsets snap rather than animate obsolete geometry;
ordinary desktop transitions and reduced-motion preferences are retained.
Notification dismissal coverage ends at the available pane edge, and its
fixed paint order keeps it reachable above a drawer sidebar.

### Regression coverage and boundaries

- Geometry and widget cases are written for 320/480/800/1280/1920/2560 logical
  widths, DPR 1/2, and text scale 1/2. Header and document cases use light, dark,
  and paper themes. No new surface colors are introduced.
- `test/unit_test/shared/workspace_layout_test.dart` covers finite allocation,
  exact measures, custom saved maxima, degenerate inputs, and sidebar recovery.
- `test/widget_test/home_layout_test.dart` covers collapsed/floating/expanded
  construction, edit/notification extents, local constraints, retained focused
  drafts, the shared bloc threshold, and absence of resize-persistence calls.
- `test/widget_test/workspace_header_test.dart` adds the full width/DPR/scale
  matrix, unbounded hosts, and focused search selection/state retention.
- `test/unit_test/editor/document_responsive_layout_test.dart` uses the actual
  lazy/shrink-wrapped page renderer, action wrapper, buttons, and color cover;
  it checks shared title-frame/body/cover edges, RTL, focus/selection/state
  retention, custom maximum restoration, and unchanged document serialization.
  Its title/body inputs are offline fixtures, not backend rename transactions.
- Existing explicitly padded row editors/previews retain their padding API.
  Collection/folder/dashboard outer gutters, secondary-plugin splits, panel
  internals, cover action control layouts, embed hover controls, viewer chrome,
  spreadsheets, and database tab toolbars are not redesigned by this foundation.
  Very small panes below the tested 320px range cannot be promised room for all
  unchanged controls simply by making the arithmetic finite.

## Quiet preview controls

- `PreviewToolbarRegion` surrounds the actual preview, not its alignment
  margins. `PreviewToolbar` fades actions in on hover or local keyboard focus;
  filenames, headings, contents and essential setup/recovery actions remain.
- Hidden tools retain their layout, state and Tab order, but do not intercept
  pointers or contribute invisible accessibility nodes. Touch devices and
  assistive navigation do not require hovering; touch on a hybrid desktop
  reveals the controls without invoking the previously hidden action.
- Menus hold their originating preview controls open, including nested scopes.
  A detached search field cannot leave a stale focus flag pinning the toolbar.
- The policy is shared by file/PDF/code/notebook/archive, page/folder/collection,
  chart/map/slide, database/calendar/table-view, diagram/canvas and extension
  preview hosts. Normal standalone viewer tools retain their fixed chrome;
  existing fullscreen idle-hide choices remain separate.
- Revealing tools does not resize the viewport or reload its renderer. The
  140ms fade skips motion when accessibility preferences request it.

## Spreadsheet interaction and appearance

- Resting unformatted cells share the page surface. The old body row-wide
  hover plus a second cell tint made a moving row conspicuously darker; only
  the pointed-at cell now receives a quiet, short fade. Explicit saved cell
  backgrounds remain intact rather than being erased as apparent banding.
- An accepted single click opens the real cell editor. Pointer-down, range
  dragging, modifier selection, fill handles, right-click and read-only cells
  do not start an edit. Native caret selection and text shortcuts remain local.
- Inline editing keeps text on the same baseline without a raised inset box.
  Enter/Tab/Escape, formulas, undo, fill, and row/column resize remain supported;
  cancellation restores transient resize/fill state instead of committing it.
- Search/replace wraps within narrow panes without replacing its input state;
  summaries scroll within their footer instead of overflowing. Header tools
  use the same accessible reveal policy as other embeds.

## Charts on the page

- A chart normally draws directly against its host background: no automatic
  white card, border or card shadow. Inline blocks, chart database tabs/embeds,
  standalone charts, collection chart views and neutral dashboard charts share
  this rule. Explicit chart backgrounds and saved dashboard accents still win.
- The chart canvas reference remains opaque for point/slice contrast; it is
  not painted as a rectangle. Tooltips and menus keep their floating theme
  surfaces, and numeric labels use secondary ink rather than disabled hints.
- Data, chosen series colors, grouping, zoom, selection, reload behavior and
  dashboard grips are unchanged. Other dashboard card types retain their own
  surfaces. Golden references show real bar/line/donut renderers in all themes.

### Subtle mark shadows

- All ten chart types use a small mark-only halo (1.2px blur sigma, 1px downward
  offset, no spread), derived from the existing light/dark/paper shadow ink.
  Bars, continuous lines, areas, scatter/bubble points and circular charts gain
  depth without restoring a white card or changing their saved colors.
- Shadows stay behind the actual marks, including translucent strokes and
  stacked seams. Pie/donut shadows use one outer silhouette; the donut hole
  remains transparent. Halos stay clipped to the plot at narrow/zoomed sizes.
- Pixel regressions cover all chart types in all themes, foreground preservation,
  seams, holes and plot clipping. These are appearance checks, not a measured
  rendering-performance improvement.

## Vivid illustrated icons

- **Icons → Vivid** adds 24 original AppFlowy illustrations with rich gradients,
  contrasting highlights and transparent backgrounds. The catalogue includes
  home, book, lightning, coffee, target, rocket, seedling, bulb, sparkles, planet,
  books, camera, music, calendar, folder, chart, globe, palette, gem, trophy,
  heart, cloud, mountain and compass. Artwork uses the repository license.
- SVGs are compiled in a lazy catalogue, with no new asset download or startup
  preload. Saved icon identities resolve even before opening the picker. Existing
  Default/Color/Phosphor styles, emoji, uploads and removal remain supported.
- Colorful selections retain their own palette rather than receiving a
  monochrome tint. Mixed recent icons retain their original pack identity after
  filtering/reordering. Native buttons expose keyboard focus and accessible
  labels; style choices wrap/scroll and illustrations stay within their cells
  at larger text sizes. Hover and attribution typography follow the host theme.

### Consistent icon access

- Workspace icons in the sidebar, workspace menus/settings, and the main
  workspace-folder heading now offer Emoji, Default icons, Icons (including
  Vivid, Color and Phosphor), and Upload. Folder headings expose the picker even
  when no custom icon is set. View renaming offers the same complete tabs.
- File chips and embedded previews expose a clickable identity icon and a
  **Change icon** menu action. Native attachments store their icon in the block
  with normal undo/redo; workspace-file references update the owning view rather
  than creating a conflicting copy in the document. Standalone file viewers
  subscribe to icon changes without reopening the file or replacing its editor.
- Database row banners and row-title pickers are no longer emoji-only. Cards
  and desktop/mobile grid titles decode the same typed value. Workspace/row
  string fields retain old emoji bytes unchanged; other types use a versioned
  envelope. Malformed tagged values use the default glyph rather than displaying
  serialized JSON. Existing view protobufs and database schemas are unchanged.
- File/gallery titles display saved custom icons, with the original type glyph
  as the fallback. File bytes, paths, preview metadata, drafts, selections and
  scroll state remain independent of icon updates. Stale/dismissed picker
  callbacks cannot edit a different workspace, view or detached block. Read-only
  controls and locked view identities do not gain mutation actions.
- Space/property-symbol controls keep their existing library-icon format;
  their Icons tab already includes the colorful libraries. This change does not
  reinterpret account-avatar strings or add icon editing to read-only mentions.

The icon-access follow-up passed **462 tests across 24 files**, including
storage round trips, real library selections, upload-completion boundaries,
workspace switching, locked/rebound targets, file/PDF renderer retention,
undo/redo, sidebar/gallery rendering and unchanged Vivid golden comparisons in
light/dark/paper. Upload/network/native backend boundaries use test doubles;
these tests do not modify a live workspace or claim cloud upload end-to-end
verification.

Both Windows bundles were rebuilt and verified on September 20 against
4,793 current input hashes, with matching functional assets and native backend.
Release's executable was refreshed at 12:30:41 UTC and Debug's at 12:34:57 UTC;
both AOT/kernel payloads were also fresh. The updated Release was opened through
Explorer and verified responsive with the correct loaded backend. Executables:
`frontend/appflowy_flutter/build/windows/x64/runner/Release/AppFlowy.exe` and
`frontend/appflowy_flutter/build/windows/x64/runner/Debug/AppFlowy.exe`.

## Verification scope

Regression coverage uses real editor, preview, chart and spreadsheet widgets,
with injected backend/native boundaries where needed and temporary test files,
not the user's workspace data. The visual references cover light/dark/paper.
The changes do not claim pixel-identical Notion rendering, app-wide performance
gains, redesigned secondary-plugin layouts, or native Office/provider handoff
verification. Windows Release and Debug bundles are verified separately after
the final coordinated test pass.

The coordinated September 20 regression run passed **1,727 tests in 56 files**
(`build/performance/ui-enhancements-final-regressions.log`). All **97 changed
Dart paths** passed targeted CLI analysis (`ui-analysis-final-*.log`), and
`git diff --check` was clean. Nine new light/dark/paper golden references for
preview controls, spreadsheet states, and integrated charts were visually
reviewed and passed normal comparison tests. These are widget/pixel tests,
not a claim that every native renderer or external provider was exercised.

The chart-shadow/Vivid follow-up passed **1,825 tests across 59 files**
(`charts-startup-vivid-final-regressions.log`) and scoped analysis of all
**117 changed Dart files** (`charts-startup-vivid-analysis-*.log`). After final
test-lint corrections, all **78 affected unit/widget/golden cases** passed again
(`vivid-final-post-lint-tests.log`). Vivid light/dark/paper references were
reviewed with the corrected attribution font; normal golden comparisons pass.