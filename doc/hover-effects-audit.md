# Warm chrome and hover-effects audit

Initial audit: 2026-09-26; scoped follow-up: 2026-09-27  
Application root: `C:/AppFlowy/frontend/appflowy_flutter`

## Coordinator verification update

The later all-Find regression run passed **635 cases across 38 files**, including
the compact bar's new single-wash hover and both reduced-motion flags. Its
buttons no longer stack an opaque hover over the shared theme's hover fill.
Evidence: repository-root `build/performance/final-all-find-verified.log`.

Three additional real-component fixtures passed in light, dark and Paper:
`test/widget_test/find_chrome_visual_review_test.dart`. They verify shared
caption/sidebar color, a single PDF/file action row, 56/112px page icons,
fractional resize/cancel, compact Find/Replace, hit areas and no network/backend
writes. Fresh review PNGs and `find-chrome-review.html` are saved under the
application's `build/performance/`; log:
repository-root `build/performance/find-chrome-visual-capture.log`.

**Pixel review remains blocked.** The direct image preview and one fresh local
browser capture returned attachment placeholders, not viewable images. No
unseen golden changes were approved; all existing baselines remain unchanged.
The component tests do not exercise an entire live workspace or native caption
buttons. Earlier scoped-pass statements below describe those individual passes,
not the coordinator's later native-input verification or final bundle build.

## Status and boundaries

**The 2026-09-27 scoped legacy follow-up is verified:** 18 widget cases and four
AST contracts passed separately and together; the final seven-suite icon/hover
matrix passed **62/62**, including **4,548 default-icon render checks**. The nine
toolbar failures in the original matrix were a test assertion across a heading
transaction, not a missing popup owner. This verification changed only
`test/widget_test/legacy_warm_hover_test.dart` and this audit; production code
and the AST test were not changed. Exact evidence and boundaries appear below.
The earlier **106 passes remain separate historical evidence**, not additional
passes for this follow-up.

Earlier central-pass sequential verification is complete: **106 tests passed across the five requested
files** (13 palette + 33 widget + 13 premium-theme + 38 alpha-contract + 9 workspace
hover regressions). The new-suite counts remain **13 and 33, both delta 0**; reruns
are not added to the total. All 17 scoped Dart paths (12 retained production files
and five test files) report no editor diagnostics. The tracked hover diff passes
the whitespace check. These are targeted checks, not a workspace-wide analysis.

**No application builds, launches/restarts, native integration tests, user-data
access, image captures, or golden updates were performed in this recovery.** No
visual approval is claimed. Numeric contrast/color and rendered-widget state
assertions are test evidence, not a review of screenshots or the running app.

This is a source audit of the central color mappings and representative shared
consumers, **not a claim that every pixel, widget, hover path, or custom theme was
reviewed**. Native scrolling, controller/data APIs, artwork, Find, PDF renderer
files, and page-identity implementations were not changed. The only edits in
`workspace_design.dart` are in `WorkspacePalette`. Scoped edits preserve the
existing worktree. Git was used read-only for `show HEAD`, diffs, status, and
verification; reversals were exact file patches. No restore, reset, stash,
cleanup, dependency, SDK, or user-data changes were made.

## Retired-viewer rollback and test repair

`build/performance/icon-hover-database-check.log` showed that the new widget
suite imported the retired `document_viewer_shell.dart`, exposing its existing
ambiguous `DocumentIdentity` import and missing `DocumentReveal`. These are
orphans from a reverted rewrite, not current production viewer paths.

Only the reviewed hover-task hunks were reversed in:

- `lib/shared/document_viewer/document_chrome.dart`
- `lib/shared/document_viewer/document_viewer_shell.dart`
- `lib/shared/document_viewer/document_viewer_theme.dart`

All three now have **zero diff against HEAD**. The theme was inspected before
reverting: its references are confined to the retired viewer cluster, and neither
current `EditorSurfaceStyle` nor its HEAD diff integrates `DocumentViewerTheme`.
Its new palette projection therefore did not belong to the live hover scope.
No `DocumentReveal`, compatibility export, or replacement viewer was added.

The 33 widget cases now import the live `document_viewport.dart` and
`document_viewport_style.dart`. Six notice-action cases were replaced with actual
`DocumentViewportButton`/`DocumentViewportFitButton` hover and geometry checks;
three retired-theme-scope cases now exercise custom premium hover/selection on
`WorkspaceControlButton`. Selected-control and accessible-navigation cases also
use the live controls. No test was skipped and no contrast threshold was reduced.

The first compiling run passed 27 and failed six focus assertions. One isolated
diagnostic proved that `getSemantics` on the keyed outer tooltip returned the
**route** node while the document button's attached node was already focused.
The fixture now finds the unique `Semantics(button: true)` descendant, checks
attachment and exact label, and keeps the merged focus/selection/button/tap
assertions plus actual Tab/Enter/Space dispatch. Disabled-node checks now inspect
that boundary too, rather than accepting a route's absent enabled flag. Production
focus behavior was not changed to satisfy the test.

## Palette decisions

| Role | Standard light | Paper | Standard dark |
| --- | --- | --- | --- |
| Shared caption/sidebar | `#F6F0E5` warm neutral cream | `#F0E6D4` established cream, unchanged | `#27231F` warm charcoal |
| Canvas | `#FFFCF6` | `#FBF5E9` | `#1C1A18` |
| Surface | `#F8F5EE` | `#FEF8EE` | `#25221F` |
| Floating surface | `#FFFDF8` | `#FFFAF0` | `#2E2A26` |
| Muted surface | `#F4F0E7` | `#F4EAD9` | `#292521` |
| Hover-wash RGB | `#675443` | `#675443` | `#F8E6CA` |
| Effective built-in hover alpha | approximately 3.82% | approximately 4.59% | approximately 3.82% |

Dark text now uses `#EEE9E2` / `#BEB5A8` / `#998F82` for primary,
secondary, and muted ink. Its existing sage accent `#98B7AA` remains distinct
from the warm charcoal. Custom theme character is retained by the existing
premium resolver; explicit premium control overrides remain caller-owned.

`PaperTheme.chromeBackground` aliases the established sidebar cream, rather
than retinting Paper's writing canvas. `EditorSurfaceStyle.chromeBackground`
is the shared shell resolver. `WorkspacePalette.chrome`, `SidebarPalette`,
`SidebarStyle`, and the default `WindowTitleBar` use that role. A scoped editor
canvas cannot recolor the shell. The actual `HomeTopBar` already explicitly
passed the sidebar background to its titlebar and was left untouched.

## Alpha and state contract

- Hover is an overlay, not a replacement opaque grey. Premium hover alpha is
  `clamp(sourceAlpha * 0.65, 0, 0.07)`; pressed alpha is
  `clamp(sourceAlpha * 1.2, 0, 0.12)`. There is no minimum-alpha floor.
- `PremiumThemeExtension.hoverOn`, `pressedOn`, and `selectedOn` use
  `Color.alphaBlend(wash, actualRestingSurface)` when a caller owns that surface.
  For an unfilled control, paint the wash once over its existing parent instead.
- A transparent animation endpoint retains its wash RGB. Do not interpolate
  from transparent black, or replace a low-alpha color with
  `.withValues(alpha: 0.35)` / `.withValues(alpha: 1)` in a consumer.
- Selected shared workspace/collection controls composite hover/press feedback
  over their selected base. The live `DocumentViewportButton` retains its existing
  `controlActive` selected fill on hover/focus instead of adopting a new state
  policy. Neither path replaces selection with an unselected pointer wash.
- Background feedback and an Ink overlay must not both paint the same hover.
  Shared workspace/collection/Fit buttons use one background wash and a zero-alpha
  overlay. The live viewport icon button uses its existing decorated background.
  Collection navigation keeps its native pressed highlight separate from the
  animated hover decoration.
- Default text/icon ink stays fixed across pointer hover. Explicit caller ink
  overrides, destructive colors, and disabled distinctions remain separate.
- Workspace/sidebar/legacy hover decorations use 140ms ease-out transitions;
  native button styles specify 140ms and keep framework animation policy. Flutter
  3.27.4 Material does not tween ordinary background-color changes, so this is not
  a claim that every native hover fill fades for 140ms.
  Shared wrappers use zero duration for `disableAnimations` or
  `accessibleNavigation`. No hover scale/translation is added. Sidebar action
  reveal no longer slides; the existing live viewport controls remain stationary.
  Retired document controls are explicitly outside this contract.
- Focus is not a stronger grey hover: shared workspace/live viewport controls use
  an opaque accent stroke; sidebar rows use a retained 1.5px foreground stroke;
  AF base controls retain their outside 1.5px ring, now at full accent opacity.
  Borderless text-field defaults, caret/selection roles, and the existing
  platform splash policy were not globally replaced.

## Source findings and shared coverage

Paths in this table are relative to the application root.

| Central family / inspected sources | Finding and outcome |
| --- | --- |
| `lib/shared/premium_theme.dart` | `surfaceColorScheme.layer03Hover` and `layer04Hover` formerly jumped to `pressed`; `fill.secondaryHover` jumped to `selected`. All now blend the subtle wash over their own resting surface. Material neutral button focus/ink remain separate from hover. |
| `lib/shared/paper_theme.dart`, `editor_surface_style.dart`, `workspace_design.dart`, `window_title_bar.dart` | One shared chrome color replaces independent fallbacks. The titlebar default formerly used the canvas; the actual workspace override already matched the sidebar. |
| `lib/workspace/presentation/home/menu/sidebar_design.dart`, `sidebar_style.dart` | Removed independently tuned grey/white hover washes in favor of premium roles. Selection uses a persistent overlay; focused rows gain a non-layout-changing ring. Disclosure/action buttons adopt the shared native control style. Icon mappings/artwork and scroll behavior are unchanged. |
| `lib/shared/workspace_chrome.dart` | Covers shared file/code/archive and other adopting controls. One wash, retained selected base, full focus stroke, stable ink, reduced motion. `workspace_tokens.dart` already supplied 140ms/ease-out and both accessibility flags; those tokens are reused, not duplicated. |
| `lib/plugins/collection/collection_workspace_surface.dart` | Shared collection actions and rail rows previously used fixed 0.35/0.4/0.3 alpha derived from an opaque hover surface. They now use explicit hover/selected/pressed roles; selected/focused feedback stays distinct. Disabled caller ink scales its existing alpha instead of forcing a new opacity. |
| `lib/shared/document_viewer/document_viewer_theme.dart`, `document_chrome.dart`, `document_viewer_shell.dart` | Retired rewrite: all hover-task edits reversed after reading HEAD/diffs; all three have zero HEAD diff. Their pre-existing orphan errors are not repaired or pulled into the new tests. |
| `lib/shared/document_viewer/document_viewport.dart`, `document_viewport_style.dart` | Live controls already route hover through `WorkspaceChrome`. Tested without hover-task production edits: viewport/Fit geometry and ink, actual rendered fills, retained selected fill, keyboard activation, attached semantics, full focus strokes, disabled states, and reduced motion. Unrelated existing glyph edits in `document_viewport.dart` were preserved. |
| `packages/flowy_infra_ui/lib/style_widget/hover.dart`, `icon_button.dart`, inspected `button.dart` | The shared wrapper formerly changed inherited ink to `onSurface` even without an override. It now retains text and scoped icon ink. Opaque `greyHover`, `lightGreyHover`, and `toolbarHoverColor` aliases are remapped only for hover, not selection. Translucent/custom colors are preserved. Explicit resting backgrounds are retained under a wash. This reaches existing Flowy button/icon consumers in database, AI, and editor chrome without changing their call sites. |
| `lib/workspace/application/settings/appearance/{desktop_appearance,mobile_appearance}.dart`, `lib/plugins/document/presentation/editor_style.dart` | Crucial mixed-role finding: `greyHover` also supplies selected menu items, dividers, borders, and tab indicators. These adapters were intentionally not globally made transparent. Their pointer-only consumers are adapted at the wrapper instead. |
| `packages/appflowy_ui/lib/src/component/button/base_button/base_button.dart`, inspected ghost button | Shared AF ghost/menu fades previously started from the floating surface's transparent RGB while hovering toward a different RGB. Premium `fill.content` now retains the hover wash RGB. The AF focus ring no longer halves the accent's opacity. Explicit builder-provided styles remain caller-owned. |
| `lib/shared/context_menu/app_menu_style.dart` | Already has shared subtle hover, stronger pressed/selected roles, stable label/icon ink, and RGB-preserving transparent endpoints. Its translucent popup/blur and elevation shadows are not pointer washes and were not flattened. |
| `lib/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart`, `lib/plugins/collection/collection_style.dart` | Existing folder/collection palettes already expose a low-alpha hover separate from opaque selected surfaces and type accents. They inherit the warmer core palette; no controller or layout edits were needed. Existing alpha-contract tests continue to cover their derived consumers. |
| `lib/shared/premium_theme_backdrop.dart` | The Paper backdrop paints sparse warm grain, not a blanket grey surface; left intact. A literal `graySurface`/`greySurface` role was not found in the scoped application/package search. The actual opaque contributors above were traced instead. |

## Intentional exceptions and remaining bypasses

These are **not** reported as fully converted or visually approved:

1. **Black image/editor chrome:**
   `lib/workspace/presentation/widgets/image_viewer/interactive_image_toolbar.dart`
   explicitly uses black at 60%, white ink, a 10% white hover, and disabled grey.
   Those colors are relative to photographs/immersive black, not a cream page.
   The source was inspected; it was not edited or rendered. Other image-editor
   instances need their own surface-local checks.
2. **Status controls, charts, and maps:** success/error/sync states, chart series,
   map markers, and user-specified colors are semantic data, not neutral hover
   aliases. No blanket desaturation, opacity replacement, or chart/map audit is
   claimed. Existing map custom-alpha guards remain in the regression suite.
3. **Native caption controls:** the installed `window_manager` caption widget
   owns immediate black/white washes and its red close action. Its source was
   inspected, but package-cache code, native behavior, and caption artwork were
   not changed. The surrounding titlebar surface is now shared warm chrome.
4. **Legacy heading/alignment menus — follow-up rendered tests passed:**
   `lib/plugins/document/presentation/editor_plugins/heading/heading_toolbar_item.dart`
   and `lib/plugins/document/presentation/editor_plugins/align_toolbar_item/align_toolbar_item.dart`
  no longer request 30% grey. Their existing `FlowyButton` wrappers supply the
  shared wash and motion policy. Triggers respect toolbar-provided ink; popup
  backgrounds and neutral glyphs use premium floating-surface/primary-ink roles
  (card/on-surface fallbacks), and dividers use the semantic divider color.
  Caller-provided highlight colors, glyph artwork, toolbar registration, editor
  transformations, popup callbacks, and focus holds remain unchanged.
5. **Legacy explicit button variants — reviewed, intentionally unchanged:**
  `packages/flowy_infra_ui/lib/style_widget/button.dart` retains
  `FlowyTextButton.secondary` accent-fill/on-accent hover: this is an explicit
  semantic accent control, not a contrasting grey alias.
  `FlowyRichTextButton` defaults to `Theme.hoverColor` over its resting fill via
  native `RawMaterialButton`; no hard-coded grey hover was found there. Its
  native feedback policy and explicit caller overrides remain unchanged. No
  universal animation/stable-ink/focus claim is made for these variants.
6. **Direct alias paints — three converted, other callers not blanket-rewritten:**
  - `lib/plugins/database/widgets/cell_editor/media_cell_editor.dart`,
    `_RenderMediaState`: the row's direct grey decoration now uses
    `FlowyHoverContainer`, driven by the same `isHovering` value.
  - `lib/plugins/database/widgets/cell_editor/relation_cell_editor.dart`,
    `_RowListItem`: the row's direct light-grey decoration now uses the same
    adapter, driven by the existing focused-option state. Linked-row actions,
    keyboard/search logic, hover events, 28px height, and margins are unchanged.
  - `lib/workspace/presentation/notifications/widgets/notification_item.dart`,
    `_NotificationItemState`: only the actionable-row hover paint is adapted.
    Read opacity, action gating, the unread accent stripe, and the action
    panel's `lightGreyHover` **border** remain unchanged. The stripe stays in a
    separate `DecoratedBox` so it cannot add container border padding.
  These call sites still pass their aliases to the adapter: built-in opaque
  hover aliases soften there, while already-translucent custom colors retain
  their RGB/alpha. Other hits can be selected surfaces, borders, or existing
  wrapper consumers; none were globally made transparent. Full row runtime
  coverage remains pending and is not supplied by source guards alone.
7. **Explicit/custom and non-premium hosts:** custom premium hover/selection
  overrides and scoped editor-canvas isolation are covered by live-control tests.
  The retired `DocumentViewerThemeScope` is not a current production surface or
  part of this verification. Bare Material/third-party controls outside the
  shared wrappers retain framework motion policy; no full reduced-motion audit
  of every caller is claimed.
8. **Other-agent ownership:** workspace icon libraries/artwork/APIs, Find,
   grid/current-cell editing behavior and themes, native PDF, and page identity
   were not patched. The only icon-related follow-up is the requested email
   call-site correction: `_RailRow` passes `icon!` directly rather than converting
   `all_inbox_rounded` to `inbox_rounded`; the existing central `inboxes` mapping
   is unchanged. Inheriting the palette is not a claim that all pixels were reviewed.

## Completed test evidence — earlier central pass only

All commands ran synchronously, one test file at a time, from the application
root, using `C:/Users/skand/development/flutter/bin/cache/dart-sdk/bin/dart.exe`,
`--packages=C:/Users/skand/development/flutter/packages/flutter_tools/.dart_tool/package_config.json`,
`C:/Users/skand/development/flutter/bin/cache/flutter_tools.snapshot`, then
`test --no-pub --reporter expanded --concurrency=1` and the explicit test path.
No shell timeouts, sleep/wait loops, polling, parallel test commands, or app builds
were used. The isolated diagnostic additionally used `--plain-name`.

Logs below are under `C:/AppFlowy/build/performance/`; each final suite log ends
with `All tests passed!` and `EXIT_CODE=0`:

| Test path relative to application root | Passed | Exact final log |
| --- | ---: | --- |
| `test/unit_test/shared/warm_hover_palette_test.dart` | 13 | `warm-hover-verified-palette-20260926-231842-994.log` |
| `test/widget_test/warm_hover_surfaces_test.dart` | 33 | `warm-hover-verified-widgets-final-20260926-232248-472.log` |
| `test/unit_test/shared/premium_theme_test.dart` | 13 | `warm-hover-verified-premium-theme-20260926-232347-866.log` |
| `test/unit_test/shared/hover_alpha_contract_test.dart` | 38 | `warm-hover-verified-alpha-contract-20260926-232427-702.log` |
| `test/widget_test/workspace_hover_regression_test.dart` | 9 | `warm-hover-verified-workspace-regression-20260926-232508-150.log` |
| **Total unique selected cases** | **106** | **No skipped cases** |

The 33 widget cases are four groups × three appearances × two motion settings,
plus three groups × three appearances. Palette 13 → 13 and widgets 33 → 33:
**no count reduction**. The selected-control group now traverses six enabled
controls and skips both disabled controls.

Failure/diagnostic evidence is retained, not overwritten:

- `warm-hover-verified-widgets-20260926-231922-132.log`: 27 passed, six failed on
  the fixture's semantics-boundary assertion.
- `warm-hover-verified-focus-diagnostic-20260926-232100-666.log`: the single-case
  failing diagnostic with the already-focused document button in the tree.
- `warm-hover-verified-scope-20260926-232747-102.log`: zero HEAD diff for all three
  retired files, clean tracked hover diff, independently checked final totals,
  and no active test/build processes (editor daemon excluded).

New-test coverage retained and verified:

- `C:/AppFlowy/frontend/appflowy_flutter/test/unit_test/shared/warm_hover_palette_test.dart`
  - Warm RGB ordering and distinct dark/light luminance ranges on base/hover
    surfaces; primary text contrast at least 7:1, secondary at least 4.5:1,
    focus accent at least 3:1.
  - Maximum normalized RGB hover difference strictly between 0.003 and 0.055,
    hover/base contrast below 1.30:1, selected/pressed differences greater than
    1.5 times the hover difference, and selected/focus separation.
  - Exact per-surface blending for AF semantic hover families; no custom-alpha
    floor; unchanged selected/focus tokens; no blanket input-decoration fill.
- `C:/AppFlowy/frontend/appflowy_flutter/test/widget_test/warm_hover_surfaces_test.dart`
  - Light/dark/Paper with and without reduced motion: caption/sidebar equality,
    sampled 70ms hover paint, fixed row/label/icon rectangles, retained text-field
    state/draft, unchanged borderless focused input decoration.
  - Real Tab/Enter/Space dispatch, merged button/selected/focus semantics,
    full-strength focus rings, disabled traversal, and destructive ink.
  - Legacy aliases versus selected/custom colors, explicit-base blending,
    scoped icon ink, AF fades, custom faint aliases, live premium control
    overrides, `accessibleNavigation`, and editor-canvas isolation.
  - Live viewport/Fit controls on an explicit resting surface; no hover lift,
    stable glyph geometry/ink, one rendered wash, and disabled Fit feedback.

Existing assertions updated to the new roles:

- `C:/AppFlowy/frontend/appflowy_flutter/test/unit_test/shared/premium_theme_test.dart`
- `C:/AppFlowy/frontend/appflowy_flutter/test/unit_test/shared/hover_alpha_contract_test.dart`

The existing `workspace_hover_regression_test.dart` was run unchanged. The
alpha-contract suite emitted missing-localization-key warnings in its existing
fixture but passed all 38 cases. No localization source or generated assets were
changed for those warnings.

### Remaining boundaries

- **No blocker remains in the five requested suites.** The retired viewer's
  pre-existing compilation problems remain intentionally unfixed and its old
  suites were not run. Do not import them to validate production chrome.
- The page-icon failures in the earlier combined main log, Find, native scrolling,
  and PDF-specific work are outside this recovery and were not repaired/retested.
- Broader sidebar/collection suites, workspace-wide CLI analysis, native runtime,
  and image/golden review were not performed here. Inherited palette coverage is
  not evidence of every consumer's layout or pixels.
- App builds were explicitly prohibited for this recovery; no executable
  freshness/startup claim or automatic restart is made.

## Original central-pass production-file inventory (12 paths)

All paths below are relative to `C:/AppFlowy/frontend/appflowy_flutter/`:

- `lib/shared/paper_theme.dart`
- `lib/shared/premium_theme.dart`
- `lib/shared/editor_surface_style.dart`
- `lib/shared/workspace_design.dart` — `WorkspacePalette` only
- `lib/shared/workspace_chrome.dart`
- `lib/shared/window_title_bar.dart`
- `lib/workspace/presentation/home/menu/sidebar_style.dart`
- `lib/workspace/presentation/home/menu/sidebar_design.dart` — palette/interaction styles only
- `lib/plugins/collection/collection_workspace_surface.dart`
- `packages/flowy_infra_ui/lib/style_widget/hover.dart`
- `packages/flowy_infra_ui/lib/style_widget/icon_button.dart`
- `packages/appflowy_ui/lib/src/component/button/base_button/base_button.dart`

Retained hover-task test changes (four paths):

- `test/unit_test/shared/warm_hover_palette_test.dart` — new, unchanged in recovery
- `test/widget_test/warm_hover_surfaces_test.dart` — new, repaired in recovery
- `test/unit_test/shared/premium_theme_test.dart` — existing role assertions retained
- `test/unit_test/shared/hover_alpha_contract_test.dart` — existing role assertions retained

The earlier central-pass recovery modified only `test/widget_test/warm_hover_surfaces_test.dart` and
`C:/AppFlowy/doc/hover-effects-audit.md`, plus the three exact retired-file
reversals listed above. All 12 live production hover edits were retained without
further changes. Other worktree changes are not included in this inventory.

## Scoped legacy follow-up — 2026-09-27, verified

### Root cause and color policy

The four legacy toolbar button overrides used `Colors.grey` at 30% alpha.
Because these are explicit translucent colors, the shared wrapper correctly
preserved them rather than treating them as opaque legacy aliases. Removing
those overrides restores the existing semantic hover wash. Coordinating popup
surface and ink also removes the obsolete assumption that every toolbar has an
inverse background and white glyphs.

The three row bypasses painted mixed-role AF aliases directly instead of going
through the hover-only adapter. They now pass their existing state into
`FlowyHoverContainer` without adding another pointer region, gesture handler,
Ink overlay, controller, or text-field replacement. One wash paints over the
actual resting parent; its transparent endpoint retains the wash RGB. The
existing adapter supplies 140ms ease-out-cubic motion, or zero duration for
**either** `disableAnimations` **or** `accessibleNavigation`. Selection, border,
disabled/status colors, semantic accents, and custom translucent aliases were
not globally recolored or assigned a new alpha.

### Exact follow-up files

Production, relative to the application root:

- `lib/plugins/document/presentation/editor_plugins/heading/heading_toolbar_item.dart`
- `lib/plugins/document/presentation/editor_plugins/align_toolbar_item/align_toolbar_item.dart`
- `lib/plugins/database/widgets/cell_editor/media_cell_editor.dart`
- `lib/plugins/database/widgets/cell_editor/relation_cell_editor.dart`
- `lib/workspace/presentation/notifications/widgets/notification_item.dart`
- `lib/plugins/collection/views/email/email_toolbar.dart`

New tests, also relative to the application root:

- `test/widget_test/legacy_warm_hover_test.dart` — **18/18 passed**:
  light/dark/Paper × normal/disable-animations/accessible-navigation, with two
  groups per combination. Actual legacy heading/alignment controls and native
  popovers cover midpoint/final/exit paint, stable glyph ink/geometry, semantic
  popup surfaces/dividers, caller highlight ink, editor-model selection/text
  retention during non-mutating popup use, real formatting actions, retained
  native popup contexts, focus-hold balance, and Escape dismissal. A separate
  rendered **shared-adapter harness**, not an imported database editor, covers
  the three row styles over different resting surfaces, retained fixture text
  fields/drafts/focus, and the non-layout unread stripe.
- `test/unit_test/shared/legacy_warm_hover_source_test.dart` — four declared AST
  contracts, **4/4 passed unchanged**: the actual media, relation, and notification call sites
  retain their state gates/ownership and use the adapter; the notification action
  border remains a border; the email rail forwards its original icon into the
  existing central mapping. These guards do not prove database/notification
  runtime behavior or substitute for the database agent's tests.

Documentation: `C:/AppFlowy/doc/hover-effects-audit.md` (this file).

### Test failure root cause and fixture repair

The preserved `final-icon-hover-matrix.log` recorded **53 passes and nine
failures** at the original widget-test line 191: `state.selection` was null.
It was not a read of the popover controller's private state. The real heading
action inserts a heading and deletes the selected paragraph. In the installed
editor implementation, `Transaction.deleteNode` leaves `afterSelection` null
when deleting the selected node; `EditorState.apply` assigns that value.

The isolated `legacy-warm-hover-selection-diagnostic.log` reproduced the
failure and recorded the actual frame boundary: selection `[0]:0–8` before the
heading action, null immediately after it, **popup mounted=true and option has
native owner=true**, and still null after Escape. Thus additional pumps or a
production focus/popover-lifecycle change would not repair this assertion.
The temporary trace statements were removed after this single diagnostic run.

The fixture now finds the `PopoverState` beneath its own keyed trigger and
matches the native overlay by that state's layout delegate. Hover checks retain
the same popup state and option elements, require mounted contexts and attached
render objects, and keep strict **non-null native-owner** assertions. It first
dismisses without a formatting action and requires the **original non-null
selection** and text. It then reopens through the real pointer handler, applies
heading/alignment formatting, and verifies dismissal preserves the action's
selection result rather than inventing a selection-restoration contract. Both
cycles check focus-hold balance and popup disposal while the trigger stays
mounted. Failure cleanup closes only the owned native state, not every popover.
No controller-private reads, synthetic on-open callback, or production edits
were introduced.

### Completed serial verification

All verification commands ran synchronously from the application root using
`C:/Users/skand/development/flutter/bin/cache/dart-sdk/bin/dart.exe`,
`--packages=C:/Users/skand/development/flutter/packages/flutter_tools/.dart_tool/package_config.json`,
`C:/Users/skand/development/flutter/bin/cache/flutter_tools.snapshot`, then
`test --no-pub --concurrency=1 --reporter expanded` and the explicit paths below.
No command timeout, parallel test invocation, dependency fetch, or application
build was used. The diagnostic additionally selected the widget file with
`--plain-name 'light/normal: legacy toolbar paint and native popup ownership'`
and exited 1 as expected; every subsequent verification completed with exit 0.

Logs are under `C:/AppFlowy/build/performance/`:

| Verification, in execution order | Passed | Log |
| --- | ---: | --- |
| `test/widget_test/legacy_warm_hover_test.dart`, isolated | 18 | `legacy-warm-hover-widget-verified.log` |
| `test/unit_test/shared/legacy_warm_hover_source_test.dart`, isolated | 4 | `legacy-warm-hover-source-verified.log` |
| Both legacy paths above, widget then source | 22 | `legacy-warm-hover-pair-verified.log` |
| Exact seven-suite matrix below | 62 | `final-icon-hover-matrix-verified.log` |

All four logs end with `All tests passed!` and `EXIT_CODE=0`. Reruns are not
added together: legacy counts remain **18 + 4**, and the matrix contains **62
unique cases**, with no skips or count reduction.

| Final matrix path, in command order | Passed |
| --- | ---: |
| `test/widget_test/workspace_icon_coverage_test.dart` | 14 |
| `test/widget_test/shared_control_glyph_adoption_test.dart` | 15 |
| `test/widget_test/reminder_composer_glyph_test.dart` | 3 |
| `test/widget_test/legacy_warm_hover_test.dart` | 18 |
| `test/unit_test/shared/legacy_warm_hover_source_test.dart` | 4 |
| `test/unit_test/util/workspace_icon_coverage_test.dart` | 6 |
| `test/unit_test/util/workspace_icon_source_inventory_test.dart` | 2 |
| **Total** | **62** |

The default-icon rendering cases cover 379 names × two styles × two sizes ×
three appearances = **4,548 renders**, with actual SVG loader/artwork checks.
Missing-localization warnings for heading/alignment tooltip labels remain;
translation assets and warning filters were not changed to obtain a pass.

### Validation boundary and handoff

The edited widget test was formatted through the editor; both legacy test files
report no editor diagnostics. Only that new widget test and this audit were
edited in this verification. The source guards and the other five matrix files
were run unchanged. The fixture mounts real toolbar/popover widgets against an
`EditorState`, not a full document editor. Row coverage remains the explicitly
limited shared-adapter harness plus AST guards, not native database runtime
coverage.

Production focus, popover lifecycle, Find/shared Find bar, themes, icon artwork,
and retired viewers were not edited. No application builds, launches, OS/user
data access, process operations, images, goldens, dependency changes, or memory
operations were performed. No visual or executable-freshness approval is
claimed. The earlier 106 passed cases remain historical central-pass evidence;
native image/caption chrome, semantic accent/status/data colors, mixed-role
alias borders/selection, explicit custom overrides, and other unreviewed direct
consumers retain the exceptions above.