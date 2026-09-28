import 'dart:async';

import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_scope.dart';
import 'package:appflowy/shared/document_viewer/file_action_band.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'archive_document.dart';
import 'archive_view_factory.dart';

/// The contents of an archive, laid out as the folder gallery lays out a
/// collection.
///
/// Same grid, same cards, same spacing: an archive opens as a folder of
/// cards, and the only difference is where the files come from.
class ArchiveGallery extends StatelessWidget {
  const ArchiveGallery({
    super.key,
    required this.entries,
    required this.previewCache,
    required this.selectedPath,
    required this.renamingPath,
    required this.editable,
    required this.onSelect,
    required this.onOpen,
    required this.onRenameRequested,
    required this.onRenameSubmitted,
    required this.onRenameCancelled,
    required this.onMore,
    this.onBackgroundContextMenu,
    this.header,
    this.compact = false,
    this.thumbnails = false,
    this.emptyMessage = 'This archive is empty',
    this.scrollController,
    this.searching = false,
  });

  final List<ArchiveEntryView> entries;
  final FolderGalleryPreviewCache previewCache;
  final String? selectedPath;
  final String? renamingPath;
  final bool editable;
  final ValueChanged<ArchiveEntryView> onSelect;
  final ValueChanged<ArchiveEntryView> onOpen;
  final ValueChanged<ArchiveEntryView> onRenameRequested;
  final Future<bool> Function(ArchiveEntryView entry, String name)
      onRenameSubmitted;
  final VoidCallback onRenameCancelled;
  final void Function(ArchiveEntryView entry, Offset position) onMore;

  /// Raised by a right click on empty space, so files can be added without
  /// reaching for the heading.
  final ValueChanged<Offset>? onBackgroundContextMenu;
  final Widget? header;

  /// Tightens the grid for a card embedded in a page, where the full window
  /// measurements would fit barely one card.
  final bool compact;

  final bool thumbnails;

  final String emptyMessage;
  final ScrollController? scrollController;
  final bool searching;

  /// An embed has a fraction of the window's width, so the same setting asks
  /// for cards a step smaller there.
  double get _scale => compact ? 0.74 : 1;

  double get _spacing => compact ? 16 : KnowledgeGalleryLayout.cardSpacing;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GalleryCardSize>(
      valueListenable: GalleryCardSizeStore.notifier,
      builder: (context, cardSize, _) => _buildGrid(context, cardSize),
    );
  }

  Widget _buildGrid(BuildContext context, GalleryCardSize cardSize) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onBackgroundContextMenu == null
          ? null
          : (details) => onBackgroundContextMenu!(details.globalPosition),
      child: StandaloneFileScrollRegion(
        controller: scrollController,
        enabled: scrollController != null,
        child: FileBrowserScrollView(
          scrollKey: const ValueKey('archive-gallery-scroll-view'),
          controller: scrollController,
          header: header,
          cacheExtent: 900,
          slivers: [
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final horizontal = compact
                    ? 18.0
                    : KnowledgeGalleryLayout.horizontalPadding(
                        constraints.crossAxisExtent,
                      );
                if (entries.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ArchiveGalleryEmptyState(message: emptyMessage),
                  );
                }
                final contentWidth =
                    constraints.crossAxisExtent - horizontal * 2;
                final metrics = thumbnails
                    ? GalleryCardMetrics.thumbnails(
                        available: contentWidth,
                        compact: compact,
                        textScale:
                            MediaQuery.textScalerOf(context).scale(13) / 13,
                      )
                    : GalleryCardMetrics.resolve(
                        available: contentWidth,
                        size: cardSize,
                        spacing: _spacing,
                        scale: _scale,
                        maximumColumns: null,
                        fillRow: false,
                        textScale:
                            MediaQuery.textScalerOf(context).scale(15) / 15,
                      );
                return SliverPadding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    horizontal,
                    compact ? 4 : 8,
                    horizontal +
                        (contentWidth - metrics.gridWidth)
                            .clamp(0.0, double.infinity),
                    compact ? 20 : 84,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: metrics.columns,
                      mainAxisSpacing: metrics.spacing,
                      crossAxisSpacing: metrics.spacing,
                      mainAxisExtent: metrics.height,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final entry = entries[index];
                        return FolderGalleryCard(
                          key: ValueKey('archive-card-${entry.entry.path}'),
                          thumbnail: thumbnails,
                          item: entry.item,
                          view: entry.view,
                          preview: previewCache.previewFor(
                            view: entry.view,
                            item: entry.item,
                          ),
                          userProfile: null,
                          selected: selectedPath == entry.entry.path,
                          editing: renamingPath == entry.entry.path,
                          canRename: editable,
                          searchPath: searching ? entry.entry.path : null,
                          onTap: () {
                            onSelect(entry);
                            onOpen(entry);
                          },
                          onRename: () =>
                              editable ? onRenameRequested(entry) : null,
                          onRenameSubmitted: (name) =>
                              onRenameSubmitted(entry, name),
                          onRenameCancelled: onRenameCancelled,
                          onMore: (position) {
                            onSelect(entry);
                            onMore(entry, position);
                          },
                          onContextMenu: (position) {
                            onSelect(entry);
                            onMore(entry, position);
                          },
                        );
                      },
                      childCount: entries.length,
                      findChildIndexCallback: (key) {
                        final index = entries.indexWhere(
                          (entry) =>
                              key ==
                              ValueKey('archive-card-${entry.entry.path}'),
                        );
                        return index < 0 ? null : index;
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveGalleryEmptyState extends StatelessWidget {
  const _ArchiveGalleryEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: const WorkspaceGlyph.named(
                'file-zip',
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              style: TextStyle(
                color: palette.textSecondary,
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The heading above the archive grid: where you are, what is inside, and the
/// handful of things you can do to it.
///
/// One row, not three: the search field only joins it once it has been asked
/// for, so the grid starts as high up the window as it can.
class ArchiveGalleryHeader extends StatelessWidget {
  const ArchiveGalleryHeader({
    super.key,
    required this.title,
    required this.breadcrumbs,
    required this.rootLabel,
    required this.subtitle,
    required this.searchController,
    required this.searchFocusNode,
    required this.searching,
    required this.onSearchChanged,
    required this.onSearchDismissed,
    required this.onSearchRequested,
    required this.onNavigate,
    required this.editable,
    required this.busy,
    required this.onAddFiles,
    required this.onNewFolder,
    required this.onRefresh,
    this.trailing,
    this.leading,
    this.viewMode = FileBrowserViewMode.gallery,
    this.onViewModeChanged,
    this.keepActionsVisible = false,
  });

  final String title;
  final List<String> breadcrumbs;
  final String rootLabel;
  final String subtitle;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool searching;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchDismissed;
  final VoidCallback onSearchRequested;
  final ValueChanged<String> onNavigate;
  final bool editable;
  final bool busy;
  final VoidCallback onAddFiles;
  final VoidCallback onNewFolder;
  final VoidCallback onRefresh;
  final Widget? trailing;
  final Widget? leading;
  final FileBrowserViewMode viewMode;
  final ValueChanged<FileBrowserViewMode>? onViewModeChanged;
  final bool keepActionsVisible;

  @override
  Widget build(BuildContext context) {
    final host = StandaloneFileScope.forName(context, title);
    if (host == null) return _buildHeader(context);
    return StandaloneFileHeaderSlot(
      controller: host.chrome,
      controls: StandaloneFileHeader(
        responsiveToolbar: true,
        toolbarBuilder: (context, fileActions) => CallbackShortcuts(
          // Published controls are siblings of the renderer, so they no
          // longer inherit the explorer body's keyboard shortcuts.
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                onSearchRequested,
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                onSearchRequested,
          },
          child: _buildHeader(context, fileActions: fileActions),
        ),
        keepActionsVisible: searching || busy || keepActionsVisible,
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {Widget? fileActions}) {
    final palette = FolderExplorerPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = fileActions == null
            ? KnowledgeGalleryLayout.horizontalPadding(constraints.maxWidth)
            : 0.0;
        final compact = constraints.maxWidth < 860;
        final available =
            (constraints.maxWidth - horizontal * 2).clamp(0.0, double.infinity);
        final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
        final stacked = constraints.maxWidth < (searching ? 1000 : 720) * scale;
        final actionsWidth =
            fileActions != null || stacked ? available : available * 0.62;
        final identityWidth = fileActions != null || stacked
            ? available
            : available - actionsWidth - 12;
        return Padding(
          padding: fileActions == null
              ? EdgeInsets.fromLTRB(horizontal, 20, horizontal, 14)
              : EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: KnowledgeGalleryLayout.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (breadcrumbs.length > 1) ...[
                  _ArchiveBreadcrumbs(
                    paths: breadcrumbs,
                    rootLabel: rootLabel,
                    onSelected: onNavigate,
                  ),
                  const SizedBox(height: 8),
                ],
                // Keep both groups at the same depth when a narrow preview
                // wraps. In particular the live search field must not remount.
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (fileActions == null)
                      SizedBox(
                        width: identityWidth,
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              alignment: Alignment.center,
                              child: leading ??
                                  WorkspaceGlyph.file(title, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontFamily: 'Inter',
                                      fontSize: compact ? 17 : 19,
                                      height: 1.2,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontFamily: 'Inter',
                                      fontSize: 11.5,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      width: actionsWidth,
                      child: PreviewToolbar(
                        keepVisible: fileActions != null ||
                            searching ||
                            busy ||
                            keepActionsVisible,
                        child: Wrap(
                          key: const ValueKey('archive-controls'),
                          spacing: 4,
                          runSpacing: 6,
                          alignment: fileActionRunAlignment(context),
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (onViewModeChanged != null)
                              FileBrowserViewButton(
                                mode: viewMode,
                                onChanged: onViewModeChanged!,
                                compact: compact,
                              ),
                            if (searching)
                              SizedBox(
                                width: actionsWidth.clamp(0.0, 244.0),
                                child: _ArchiveSearchField(
                                  controller: searchController,
                                  focusNode: searchFocusNode,
                                  onChanged: onSearchChanged,
                                  onDismissed: onSearchDismissed,
                                ),
                              )
                            else
                              ArchivePillButton(
                                icon: Icons.search_rounded,
                                tooltip: 'Search this archive  ·  Ctrl+F',
                                onPressed: onSearchRequested,
                              ),
                            if (editable) ...[
                              ArchivePillButton(
                                icon: Icons.add_rounded,
                                label: compact ? null : 'Add files',
                                tooltip: 'Add files to this archive',
                                onPressed: busy ? null : onAddFiles,
                                primary: true,
                              ),
                              ArchivePillButton(
                                icon: Icons.create_new_folder_rounded,
                                tooltip: 'New folder',
                                onPressed: busy ? null : onNewFolder,
                              ),
                            ],
                            if (viewMode == FileBrowserViewMode.gallery)
                              Builder(
                                builder: (buttonContext) => ArchivePillButton(
                                  icon: Icons.tune_rounded,
                                  tooltip: 'Card size',
                                  onPressed: () {
                                    final box = buttonContext.findRenderObject()
                                        as RenderBox?;
                                    if (box == null) return;
                                    unawaited(
                                      showGalleryCardSizeMenu(
                                        context: buttonContext,
                                        globalPosition: box.localToGlobal(
                                          Offset(0, box.size.height + 4),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ArchivePillButton(
                              icon: Icons.refresh_rounded,
                              tooltip: 'Reload archive',
                              onPressed: onRefresh,
                            ),
                            if (fileActions != null) fileActions,
                            if (trailing != null) trailing!,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Retains the public archive API while sharing the file/code control style.
class ArchivePillButton extends StatelessWidget {
  const ArchivePillButton({
    super.key,
    required this.icon,
    this.label,
    this.tooltip,
    this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return WorkspaceControlButton(
      icon: icon,
      tooltip: tooltip ?? label ?? '',
      label: label,
      foregroundColor: primary ? palette.accent : null,
      iconRole: WorkspaceGlyphRole.standard,
      onPressed: onPressed,
    );
  }
}

/// The search field, shown only once Ctrl+F has asked for it.
///
/// A short pill rather than a full width bar: it sits beside the actions,
/// takes as little of the heading as it can, and Escape puts it away.
class _ArchiveSearchField extends StatelessWidget {
  const _ArchiveSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onDismissed,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return SizedBox(
      width: 244,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onDismissed,
        },
        child: TextEntryShortcuts(
          child: TextField(
            key: const ValueKey('archive-search-field'),
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            onEditingComplete: () {},
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: palette.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filename or path · all folders',
              hintStyle: TextStyle(
                fontFamily: 'Inter',
                color: palette.textMuted,
                fontSize: 13,
              ),
              prefixIcon: WorkspaceGlyph(
                Icons.search_rounded,
                size: 17,
                color: palette.textMuted,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 34),
              suffixIcon: IconButton(
                tooltip: 'Close search',
                icon: const WorkspaceGlyph(Icons.close_rounded, size: 15),
                color: palette.textMuted,
                splashRadius: 13,
                onPressed: onDismissed,
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 32),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              filled: true,
              fillColor: palette.surface,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(WorkspaceChrome.controlRadius),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(WorkspaceChrome.controlRadius),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(WorkspaceChrome.controlRadius),
                borderSide: BorderSide(color: palette.accent, width: 1.2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchiveBreadcrumbs extends StatelessWidget {
  const _ArchiveBreadcrumbs({
    required this.paths,
    required this.rootLabel,
    required this.onSelected,
  });

  final List<String> paths;
  final String rootLabel;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return SizedBox(
      height: (MediaQuery.textScalerOf(context).scale(12) * 1.4 + 10)
          .clamp(26.0, double.infinity),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => WorkspaceGlyph(
          Icons.chevron_right_rounded,
          size: 15,
          color: palette.textMuted,
        ),
        itemBuilder: (context, index) {
          final path = paths[index];
          final isLast = index == paths.length - 1;
          final label = path.isEmpty ? rootLabel : archiveEntryName(path);
          return TextButton(
            onPressed: isLast ? null : () => onSelected(path),
            style: WorkspaceChrome.controlStyle(context).copyWith(
              minimumSize: const WidgetStatePropertyAll(Size.zero),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}
