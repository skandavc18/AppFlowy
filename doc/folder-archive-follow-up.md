# Folder / archive follow-up (users 5, 7, 10)

2026-09-27. Source changes and focused tests only. **No terminals, test execution,
builds, app launches, images/goldens, code generation, dependency or Rust changes.**
Editor diagnostics are not compile/runtime proof.

## Findings and implementation

- FolderExplorer placed its full cover/title/header in a capped independent
  SingleChildScrollView above the listing. It now passes the unchanged
  FolderGalleryHeader into the listing's native sliver viewport. The header is
  globally keyed across layout switches; selection, query/controller, drafts and
  preview-cache ownership remain in the existing folder shell.
- Gallery, Thumbnails, Tiles, List, Details and Tree share FileBrowserScrollView
  (a native CustomScrollView, not shrink-wrapped tiles). Native delegates remain
  lazy and keyed; tree and archive delegates now also resolve moved child keys.
  Per-mode FileBrowserScrollController retains offsets across detach/reattach.
  Details keeps horizontal scrolling; keyboard row reveal includes measured
  header/draft extent. Columns retains independent native directory scrollers:
  only its active directory borrows a NestedScrollView coordinator to retire the
  page header. No scroll deltas are replayed into another controller.
- WorkspaceExplorerItem.fromView explicitly uses ViewPB.isWorkspaceFolder and
  isWorkspaceFile before the protobuf layout fallback. The prior metadata check
  was equivalent for valid envelopes; no evidence warrants classifying every
  Document-layout item as a folder. Ordinary files and collection files remain
  files. Gallery had no automatic title icon, and Thumbnails had no title icon:
  covers could hide folder identity. Both now show WorkspaceItemIcon beside the
  name. Saved emoji/library/upload identity wins; automatic folder/folder-open
  resolves through the existing semantic mapping in Vivid and Monochrome.
- CollectionViewDefinition.supportsPageHeader opts audited main listings into
  FileBrowserPageHeader. Generic local/remote contents, folder collection views,
  and album Grid/Masonry/Timeline carry their actual collection cover/title and
  controls in the same lazy viewport. Provider loading/error states retain the
  header; cached-failure strips flow with it. Album controllers are unchanged.
  The local folder collection Thumbnail tab previously rendered Gallery; it now
  selects real Thumbnails. Existing stored view IDs are preserved.
- ArchiveDocument.search ALREADY searched every indexed path, including the
  basename, across all subfolders. Do not attribute the report to a missing
  basename comparison or current-directory-only search. The actual TextField
  lacked TextEntryShortcuts and native search-action focus retention. Added both;
  the published fullscreen toolbar already carried the correct callbacks. The
  shared Find router only intercepts Ctrl/Cmd+F/H, not ordinary filename input.
  Search remains literal/case-insensitive (no quote, regex, filename: or settings
  parser). Result count/scope and gallery result paths are visible; clear restores
  the browsed path. The user's precise live failure was not runtime reproduced.
- Fullscreen archive Close is a route-owned visible native button outside the
  renderer's reveal/horizontal-overflow group. It is present during loading and
  opened-entry viewing, uses the shared close glyph, and checks mounted/current
  route plus a once-only guard. Escape/F11 reach the same close operation; a local
  search Escape may close search first. Original-file Copy/Share slots remain
  unique. Archive edit/write-back/encode/save methods were not changed.

## Source files (under frontend/appflowy_flutter/lib)

- shared/file_browser/{file_browser_scroll_view,file_browser_items}.dart
- workspace/application/workspace_item/workspace_explorer_models.dart
- workspace/presentation/widgets/folder_explorer/{folder_explorer,folder_gallery,
  explorer_tree,folder_browser_presentations,workspace_item_icon}.dart
- plugins/document/presentation/editor_plugins/file/archive/{archive_explorer,
  archive_gallery,archive_document}.dart (document change is documentation only)
- workspace/application/collections/collection_registry.dart
- plugins/collection/{collection_page,collection_views}.dart
- plugins/collection/views/collection_contents_view.dart
- plugins/collection/views/folder/folder_collection_views.dart
- plugins/collection/providers/{external_content_view,external_collection_host}.dart
- plugins/collection/views/album/{album_views,album_wall_view,album_chrome,album_host}.dart

## Focused tests written, not executed

- test/widget_test/file_browser_tiles_test.dart: existing tests updated only to
  inspect CustomScrollView/SliverGrid instead of GridView/ListView; geometry,
  controller, keyboard and context-anchor assertions remain intact.
- test/widget_test/folder_whole_page_scroll_test.dart: actual folder shells in
  all seven modes/light/dark/paper; cover/title displacement, hidden hit clipping,
  return geometry, mounted header/EditableText draft+selection retention, lazy
  item bounds, default/saved folder-vs-file identity in both icon styles, preview
  invalidation and per-layout offsets; actual CollectionPage and three album walls.
- test/widget_test/archive_filename_search_follow_up_test.dart: actual archive
  root/search callbacks and native TextField in all seven modes; recursive basename
  results, visible filtering, zero hits, Ctrl+A/Backspace against a competing
  ancestor, Enter focus, clear/path/back restoration, unchanged ZIP bytes; real
  fullscreen published search and one visible route-safe Close at 360px/2x across
  light/dark/paper, repeated/stale close callback and keyboard F11.

## Audit boundaries and integration notes

- Bookmark Grid/Feed/Shelf/Timeline already borrow the existing coordinated page
  controller. Left unchanged; Grid's pre-existing eager Wrap was not refactored.
- Album Filmstrip/Playlist/Places, repository browser/tree/docs/symbols/graph,
  book readers, email panes, native database/table workbenches and custom extension
  views keep their existing controllers/layouts. Whole-page single-viewport
  behavior is **not newly claimed** for these multi-pane/specialized surfaces.
- External providers retain their existing four presentations and local/provider
  search semantics. No recursive provider fetch was introduced. Archive previews
  still use the existing bounded extraction factory; no new extraction strategy.
- Archive standalone identity remains in its media-host header; this change does
  not refactor workspace_file_view/identity or other agents' shared Find/dashboard,
  database palette, or folder_gallery_header files. CoverAppearance preferences
  can continue to be wired by the cover/main agents through the unchanged header.
- Existing folder_shell_follow_up_test.dart assertions requiring
  folder-explorer-header-scroll or the old fixed content/title geometry describe
  the retired capped-header design. They need coordinated expectation updates,
  not restoration of that bug. No golden/reference images were changed or approved.
- A full diff/build/test gate is intentionally deferred to the coordinating agent.