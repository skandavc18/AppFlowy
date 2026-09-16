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