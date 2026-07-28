import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
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
    this.emptyMessage = 'This archive is empty',
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

  final String emptyMessage;

  double get _cardHeight =>
      compact ? 292 : KnowledgeGalleryLayout.cardHeight;

  double get _spacing =>
      compact ? 16 : KnowledgeGalleryLayout.cardSpacing;

  double get _minimumCardWidth =>
      compact ? 218 : KnowledgeGalleryLayout.minimumCardWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onBackgroundContextMenu == null
          ? null
          : (details) => onBackgroundContextMenu!(details.globalPosition),
      child: CustomScrollView(
        key: const ValueKey('archive-gallery-scroll-view'),
        cacheExtent: 900,
        slivers: [
          if (header != null) SliverToBoxAdapter(child: header),
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
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  compact ? 4 : 8,
                  horizontal,
                  compact ? 20 : 84,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _columnCount(
                      constraints.crossAxisExtent - horizontal * 2,
                    ),
                    mainAxisSpacing: _spacing,
                    crossAxisSpacing: _spacing,
                    mainAxisExtent: _cardHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final entry = entries[index];
                      return FolderGalleryCard(
                        key: ValueKey('archive-card-${entry.entry.path}'),
                        item: entry.item,
                        view: entry.view,
                        preview: previewCache.previewFor(
                          view: entry.view,
                          item: entry.item,
                        ),
                        userProfile: null,
                        selected: selectedPath == entry.entry.path,
                        editing: renamingPath == entry.entry.path,
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
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  int _columnCount(double width) {
    if (!width.isFinite || width <= 0) {
      return 1;
    }
    return ((width + _spacing) / (_minimumCardWidth + _spacing))
        .floor()
        .clamp(1, 5);
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
              child: Icon(
                Icons.folder_zip_rounded,
                size: 28,
                color: palette.accent.withValues(alpha: 0.7),
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

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            KnowledgeGalleryLayout.horizontalPadding(constraints.maxWidth);
        final compact = constraints.maxWidth < 860;
        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 14),
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
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.folder_zip_rounded,
                        size: 20,
                        color: palette.accent,
                      ),
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
                    const SizedBox(width: 12),
                    if (searching)
                      _ArchiveSearchField(
                        controller: searchController,
                        focusNode: searchFocusNode,
                        onChanged: onSearchChanged,
                        onDismissed: onSearchDismissed,
                      )
                    else
                      ArchivePillButton(
                        icon: Icons.search_rounded,
                        tooltip: 'Search this archive  ·  Ctrl+F',
                        onPressed: onSearchRequested,
                      ),
                    const SizedBox(width: 8),
                    if (editable) ...[
                      ArchivePillButton(
                        icon: Icons.add_rounded,
                        label: compact ? null : 'Add files',
                        tooltip: 'Add files to this archive',
                        onPressed: busy ? null : onAddFiles,
                        primary: true,
                      ),
                      const SizedBox(width: 8),
                      ArchivePillButton(
                        icon: Icons.create_new_folder_rounded,
                        tooltip: 'New folder',
                        onPressed: busy ? null : onNewFolder,
                      ),
                      const SizedBox(width: 8),
                    ],
                    ArchivePillButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Reload archive',
                      onPressed: onRefresh,
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
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

/// A soft, fully rounded action button — the shape used across the file
/// surfaces so a control never reads as a framework default.
class ArchivePillButton extends StatefulWidget {
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
  State<ArchivePillButton> createState() => _ArchivePillButtonState();
}

class _ArchivePillButtonState extends State<ArchivePillButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final enabled = widget.onPressed != null;
    final background = widget.primary
        ? palette.accent.withValues(alpha: enabled ? (hovered ? 1 : 0.92) : 0.4)
        : hovered
            ? Color.alphaBlend(palette.hover, palette.surface)
            : palette.surface;
    final foreground = widget.primary
        ? Colors.white
        : enabled
            ? palette.textSecondary
            : palette.textMuted.withValues(alpha: 0.5);

    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 36,
          padding: EdgeInsets.symmetric(
            horizontal: widget.label == null ? 9 : 14,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
            border: widget.primary
                ? null
                : Border.all(color: palette.border, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 17, color: foreground),
              if (widget.label != null) ...[
                const SizedBox(width: 7),
                Text(
                  widget.label!,
                  style: TextStyle(
                    color: foreground,
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip ?? widget.label;
    if (tooltip == null) {
      return button;
    }
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: button,
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
      height: 38,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onDismissed,
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: palette.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search this archive',
            hintStyle: TextStyle(
              fontFamily: 'Inter',
              color: palette.textMuted,
              fontSize: 13,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 17,
              color: palette.textMuted,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 34),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close_rounded, size: 15),
              color: palette.textMuted,
              splashRadius: 13,
              onPressed: onDismissed,
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 32),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: BorderSide(color: palette.border, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: BorderSide(color: palette.border, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: BorderSide(color: palette.accent, width: 1.2),
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
      height: 26,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => Icon(
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
            style: TextButton.styleFrom(
              foregroundColor:
                  isLast ? palette.textPrimary : palette.textSecondary,
              disabledForegroundColor: palette.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
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
