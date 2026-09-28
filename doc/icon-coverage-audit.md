# Default icon coverage audit

Date: 2026-09-26. Package: `frontend/appflowy_flutter`.

## Scope and verification status

This is an implemented palette/alias audit, **not a claim that every caller has
been migrated**. The original icon-library pass changed four library files and
three tests. The subsequent shared-control migration is recorded below.
`default_extra_artwork.dart` does not exist in this checkout; outlines live in
`default_icon_artwork.dart`. Saved/custom icon renderers remain unchanged.

The final seven-suite icon/hover selection passed **62 tests**, including the
complete **4,548-render** default-icon matrix. Evidence:
`build/performance/final-icon-hover-matrix-verified.log` at the repository root.
These renders verify actual decoded SVG sources, sizes, themes and state ink;
they are not 4,548 separate tests or a visual-quality approval.

Three additional production-component fixtures passed and exported fresh
light/dark/Paper sheets under the Flutter application's `build/performance/`.
Both the direct image viewer and one fresh integrated-browser capture returned
unviewable attachment placeholders. **Visual approval remains blocked**; no
golden baseline was changed. Normal application bundle verification is recorded
separately from these tests. No external artwork or icon asset preload was added.

## Inventory and coverage

| Measure | Before | After | Evidence |
| --- | ---: | ---: | --- |
| Known default semantic names | 281 | **379** | `defaultIconNames`; 380 entries including the non-renderable `unknown` diagnostic sentinel |
| Default names using explicit illustrations | 82 | **221** | `vividNameFor`, explicit artwork maps, exact utility allowlist in the coverage test |
| Default names using semantic utility gradients | 199 | **158** | Exact `_utilityDefaults` test snapshot; no generic fallback glyph counted |
| Explicit Vivid illustrations | 150 | **275** | `vividIllustrationNames`; **125** new `_Illustration.action` entries |
| Saved Vivid picker choices | 150 | **150** | `appFlowyVividIconGroups`; all 56 Essentials identities and their order retained |
| Newly covered Material constants | — | **119** | 120 `_auditedMaterialNames` entries, including one existing Help constant moved from `info` to `help` |
| SVG path-stem aliases | — | **640** | `_svgNames`; includes compatibility aliases, not 640 distinct caller sites |

All 379 known defaults have a declared counterpart: 221 explicit and 158 utility.
The exact-set tests reject both a missing default and a previously explicit action
silently reverting to `utility-name`. Utility coverage is not being presented as
independently illustrated coverage.

### Search method

The source search covered literal `Icons.*` and `FlowySvgs.*` references across
`lib`, including shared controls, page/editor actions, files, collections,
databases, sidebar/workspace UI, canvas, extensions, AI and mobile. An exclusion
probe against the original Material aliases returned **186 textual references in
97 files**; the equivalent SVG probe returned **464 textual references in 203
files**. These are search hits, not unique icons or confirmed rendering gaps:
comments, repeated uses and platform APIs must not inflate coverage claims.

The new source-inventory test uses Dart's existing analyzer dependency to inspect
AST references rather than count comments/string contents. It checks generated
SVG paths through the real resolver, and checks literal/conditional
`WorkspaceGlyph.named` and `DSWorkspaceGlyph.named` identities. Generated source
declarations are not counted as UI callers. New unmapped source references fail
with file/line locations instead of being silently grandfathered in.

### Representative source evidence

Paths in the following tables are relative to the package's `lib/` directory.

| Area inspected | Examples of source references | Change |
| --- | --- | --- |
| `shared/find_replace/find_replace_bar.dart`, document spreadsheet toolbar | `find_replace_rounded`, `change_circle_rounded` | Separate find/replace and replace-all outlines and illustrations |
| File PDF toolbar, sidebar and preview menus | fit, width, rotate, print, zoom, scanner, highlights | Explicit fit/page/width/actual-size, rotation, printer, lenses, OCR and marker artwork |
| Image editor, canvas and media controls | CCW, flip, crop, pan, cursor, five-second seeks, volume | Missing aliases plus directional/state-specific illustrations |
| Collection album/book/bookmark views | shuffle, previous track, remove-done, add bookmark, untagged | Separate `shuffle`, `skip-previous`, `check-off`, `bookmark-plus`, `tag-off` identities |
| Repository and provider views | commit, rebase, license scales, server, key, missing extension | Dedicated semantics instead of repository/page/code substitutions |
| Database fields/cells/calendar | checked/unchecked, alarms, available/busy dates, multiple inboxes | Real generated SVG aliases; state differences remain distinct |
| Sidebar, settings and common actions | folder/file creation, move/upload, lock, archive/unarchive, help | Explicit action artwork and additional legacy aliases |
| Shared document viewer and dashboard | broken/hidden images, warning/help, weather, devices | Missing semantic identities and original small illustrations |
| Mobile/AI editor controls | toolbar cuts, heading variants, copy, send, feedback, keyboard directions | Explicit path aliases; typography/navigation can retain utility geometry |

## Artwork and semantic decisions

- New artwork is original, compiled SVG on a transparent 32px canvas. Two colored
  drawing parts are independently painted; it is not a color filter over the
  24px monochrome SVG. Common actions have dedicated silhouettes/strokes, and
  small navigation/typography marks can retain the exact utility geometry.
- `rotate` now has a clockwise outline; `rotate-ccw` is a separate identity. Both
  explicit drawings have direction-specific arrowheads. Horizontal and vertical
  flips, zoom-in/out, seek-back/forward and hide/show states are distinct.
- `tree` means hierarchy in default chrome, so its counterpart is `hierarchy`,
  **not the saved nature-tree illustration**. Archive action uses `archive-box`,
  ZIP identity still uses `archive`, and a straight ruler uses `measure` rather
  than replacing the saved triangular ruler. Link actions use `link`; an inbox
  remains an inbox instead of becoming an envelope.
- Real SVG source was inspected for misleading filenames: `details.svg` contains
  two vertical dots, `details_horizontal.svg` three horizontal dots,
  `arrow_tight.svg` a down chevron, `pull_left_outlined.svg` an arrow docking left,
  and `show_menu.svg` double right chevrons. `unable_select.svg` is a disabled
  checked box, not a blocked-action symbol. These have precise aliases.
- `vividNameFor` validates that a default semantic name exists before selecting
  explicit artwork. A Vivid-only saved name such as `terminal` cannot accidentally
  become a default alias. Unknown source glyphs retain the existing source-renderer
  behavior; unknown names do not acquire unrelated Vivid art.
- `WorkspaceGlyph` rendering, `WorkspaceGlyph.adapt`, file/collection factories,
  saved/custom renderers and device preference storage were not changed. Explicit
  monochrome choice still uses the outline. `preserveInk` scopes/roles still win
  for disabled, destructive and status ink, including over an explicitly vivid
  child. Standard Vivid pictures have no color filter.
- Existing Vivid SVG bytes are retained: the optional action stroke group is
  emitted only by the new action constructor. `vivid_icons.dart` and all persisted
  picker groups were left unchanged. There are no new picker aliases disguised
  as extra choices.

## Original caller inventory and migration outcome

These are confirmed source call sites. Inspection-time line numbers may move.
The coordinator migrated the live map/table/mind-map/reminder/image-editor
wrappers and collection table/slide controls listed below. Their actual native
controls and draft/state retention pass `shared_control_glyph_adoption_test.dart`
and `reminder_composer_glyph_test.dart`. Retired viewer modules were deliberately
not revived. Typed-property and Git-provider raw leaves remain local adoption
candidates; their semantic counterparts are available in the library.

| Shared wrapper / location | Remaining bypass | Main-agent follow-up |
| --- | --- | --- |
| `shared/maps/app_map_toolbar.dart`: `MapControlButton` (35) | Former raw default icon | Migrated; native disabled ink, selected state, tooltip and hit area retained |
| Same file: `AppMapSearchField` | Former raw search/close icons | Migrated; controller, selection and focus verified |
| `shared/table_views/table_view_chrome.dart`: `TableViewButton` (41), `_TableViewActionState` (593) | Former raw default icons | Migrated shared gallery/feed/form/mailbox/timeline controls |
| `shared/document_viewer/document_chrome.dart`: `_DocumentGlyph` (184) | Retired rewrite | Excluded; zero task diff, not a live production adoption target |
| `shared/document_viewer/document_viewer_shell.dart` (173) | Retired rewrite | Excluded; zero task diff, no replacement viewer introduced |
| `shared/mind_map/mind_map_canvas.dart`: `_ToolbarButtonState` (1250), another control (1517) | Former raw default icons | Migrated; disabled/active state and pan/zoom callbacks retained |
| `shared/calendar/reminder_composer.dart`: `_PickerButton` (530), `_ChoiceButton` (597) | Former raw default icons | Migrated; real reminder drafts, choice and disabled state verified |
| `shared/table_views/table_property_view.dart` (438) | Raw typed-property icon | Keep semantic/status tint separate from decorative Vivid colors |
| Document image `image_editor/image_editor_controls.dart`: `ImageEditorIconButton` (70), text/chip controls (158, 234) | Former raw default icons | Migrated; named artwork, transforms and callbacks verified |
| `plugins/collection/table_view_plugin.dart` (403), `plugins/collection/slide_plugin.dart` (346) | Former raw settings/header icons | Migrated through shared glyph handling |
| `plugins/collection/providers/git/git_panel.dart` (918, 968, 990) | Raw action/metadata icons | Commit/rebase/server counterparts now exist; status colors still need `preserveInk` |

Existing `WorkspaceControlButton`, `AppMenuIconButton`, `AppMenuRow`,
`ChartIconAction`, `DocumentViewportButton` and the Find bar already use
`WorkspaceGlyph` or its adapter. Their coverage should not be counted as a new
caller migration merely because the palette now contains more art.

### Removed wrapper-local substitutions

- `plugins/collection/views/book/book_reader_controls.dart`, `BookControlButton`:
  now retains `remove_done_rounded` as `check-off`, not `history_rounded`.
- `plugins/collection/views/repository/repository_style.dart`, `RepoGlyphIcon`:
  retains license scales, commits and XML brackets as `scales`, `commit` and
  `brackets`. `RepoAction` no longer substitutes `segment_rounded`.
- `plugins/collection/views/email/email_chrome.dart`, `EmailAction`/`EmailChip`:
  preserves outlined download, segment/headline, all-inboxes and empty-hourglass
  identities. The later `email_toolbar.dart` rail correction also preserves
  `all_inbox_rounded` as `inboxes`, rather than a single inbox.

Do not migrate wrappers by filtering an entire subtree: uploaded images, saved
pack icons, emoji and inline/colorful SVGs must keep their own renderer/colors.
Native `IconButton.disabledForegroundColor` alone does not communicate the
semantic state to a custom SVG leaf; preserve it explicitly at the default glyph
or through the existing shared control/scope.

## Context-sensitive and intentionally unresolved cases

1. **One glyph, multiple meanings:** `crop_free_rounded` is “Fit page” in PDF,
   “Actual size” in the image editor and a frame in canvas. Its existing global
   fullscreen-shaped mapping was retained. Use `.named('fit-page')` or
   `.named('actual-size')` at the relevant callers; their art is ready. No PDF or
   image behavior was changed. The image editor's existing rotated horizontal
   flip can remain rotated, or adopt the new explicit vertical identity.
2. **Reset-zoom semantics:** the command palette uses
   `youtube_searched_for_rounded` for reset zoom. It now resolves rather than being
   unknown, but the caller can prefer the explicit `actual-size` identity when
   that better describes its operation.
3. **Utility versus illustration:** 158 names intentionally retain valid utility
   gradients. These include tiny navigation/typography/geometry plus specialty
   controls such as chart variants, gauge, density and spacing. They are not
   missing color counterparts, but further explicit-art enrichment is possible.
   Their full list is frozen in `_utilityDefaults`; don't claim all 379 defaults
   are independent illustrations.
4. **Intentional source renderers:** the source test has 17 documented exceptions:
   the Google Drive brand constant, the `Icons.adaptive` API, and 15 SVG references
   covering brand/provider identity, existing sign-in/empty-state illustrations,
   and three structural document bullet levels. These are not silently replaced
   by unrelated objects or subjected to the default device style.
5. **Audit boundary:** dynamically constructed icon names/data, dependency
   packages, WebView artwork and saved/uploaded user content are not a literal
   `lib` source inventory. The tests do not prove all caller state/hover behavior;
   shared-wrapper migration needs its own integration tests.
6. **Visual validation blocked:** the executed render matrix and three component
  fixtures passed, but the attachment-preview transport prevented pixel review.
  Existing goldens were neither approved nor modified.

## Added tests

Paths relative to `frontend/appflowy_flutter`:

- `test/unit_test/util/workspace_icon_coverage_test.dart`
  - Exact 281 original + 98 added defaults, plus sentinel; exact utility allowlist.
  - All Material/SVG alias targets exist; every known default has valid local SVG.
  - Exactly 125 independent new drawings and 275 total explicit illustrations;
    no duplicate geometry, palette-only clones or saved-choice collisions.
  - Direction/meaning pairs, actual generated SVG aliases, local gradient
    references, no external resources and rejection of unknown default names.
- `test/unit_test/util/workspace_icon_source_inventory_test.dart`
  - AST inventory across all `lib` areas with explicit non-chrome exceptions.
  - Comments/string examples cannot count as coverage. Named glyphs, the
    `DSWorkspaceGlyph` typedef and literal conditional branches are checked.
- `test/widget_test/workspace_icon_coverage_test.dart`
  - Executed matrix: **379 names × 2 styles × 2 sizes × 3 appearances = 4,548**
    rendered glyph cases, decoded through actual `SvgPicture` loaders.
  - Real light/dark/paper themes, 200% text scaling, fixed 16px/18px slots,
    exact loader/source equality and unfiltered Vivid output.
  - Mounted style changes retain host/element/slot and accessible labels.
  - Disabled/destructive/status outlines retain their exact ink; a preserve-ink
    scope outranks explicit vivid style and decorative child colors.
  - Saved/custom/inline/colorful renderers remain identity-preserved by the
    adapter; future unmapped Material glyphs retain the original renderer.
  - No golden or screenshot generation; no icon asset loads or pack preloading.

Existing regression suites relevant to the main agent include
`default_icon_style_test.dart`, `default_icon_consistency_test.dart`,
`workspace_file_icon_test.dart`, `grid_default_icon_adoption_test.dart`, and
`test/unit_test/util/vivid_icons_test.dart`. Existing picker/golden expectations
were not relaxed or rewritten.

## Original icon-library pass paths

- `frontend/appflowy_flutter/lib/shared/workspace_icons.dart`
- `frontend/appflowy_flutter/lib/shared/icon_emoji_picker/default_icon_artwork.dart`
- `frontend/appflowy_flutter/lib/shared/icon_emoji_picker/vivid_icon_artwork.dart`
- `frontend/appflowy_flutter/lib/shared/icon_emoji_picker/vivid_extra_artwork.dart`
- The three new test files listed above.
- `doc/icon-coverage-audit.md` (this file).

`vivid_icons.dart`, saved/custom icon renderers, assets and existing goldens were
left unchanged. PDF/layout/Find and shared-wrapper changes belong to the broader
feature implementation, not the original four-file artwork pass. The live Fit
control now uses the shared named glyph, including `fit-page` in PDF chrome.