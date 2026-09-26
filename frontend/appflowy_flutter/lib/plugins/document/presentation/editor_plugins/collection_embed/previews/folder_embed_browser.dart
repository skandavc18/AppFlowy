import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/shared/file_browser/file_browser_items.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// Browsing only: item activation uses the existing embed callback, and its
/// context menu remains the host's guarded menu. No repository writes here.
class FolderEmbedBrowser extends StatefulWidget {
  const FolderEmbedBrowser({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  State<FolderEmbedBrowser> createState() => _FolderEmbedBrowserState();
}

class _FolderEmbedBrowserState extends State<FolderEmbedBrowser> {
  void _navigate(ViewPB view) {
    widget.embed.controller.navigateFolder(view);
  }

  void _open(FileBrowserEntry entry) {
    if (entry.item.isBrowsable) {
      _navigate(entry.view);
    } else {
      widget.embed.onOpenObject(entry.view);
    }
  }

  Widget _items(ViewPB folder, {String? activeChildId}) {
    final embed = widget.embed;
    final controller = embed.controller;
    final query = controller.folderQuery;
    final rows = <FileBrowserEntry>[];
    final visited = <String>{};
    void append(String id, int depth) {
      if (!visited.add(id)) return;
      for (final view in controller.orderedChildren(id, embed.settings.sort)) {
        final item = WorkspaceExplorerItem.fromView(view);
        final expanded = controller.expandedFolders.contains(view.id);
        if (query.isEmpty || view.name.toLowerCase().contains(query)) {
          rows.add(
            FileBrowserEntry(
              view: view,
              item: item,
              depth: depth,
              expanded: expanded,
              loading: controller.loadingChildren(view.id),
              failed: controller.childrenError(view.id) != null,
            ),
          );
        }
        if (embed.settings.folderViewMode == FileBrowserViewMode.tree &&
            expanded &&
            item.isBrowsable) {
          append(view.id, depth + 1);
        }
      }
    }

    append(folder.id, 0);
    if (controller.loadingChildren(folder.id) && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (controller.childrenError(folder.id) != null) {
      return Center(
        child: TextButton(
          key: ValueKey('folder-browser-retry-${folder.id}'),
          onPressed: () => unawaited(controller.retryChildren(folder.id)),
          child: const Text('Unable to read this folder. Retry'),
        ),
      );
    }
    return FileBrowserItems(
      key: ValueKey('folder-embed-browser-${folder.id}'),
      entries: embed.settings.itemLimit == null
          ? rows
          : rows.take(embed.settings.itemLimit!).toList(),
      selection: controller.folderSelection,
      activeChildId: activeChildId,
      details: embed.settings.folderViewMode == FileBrowserViewMode.details,
      tiles: embed.settings.folderViewMode == FileBrowserViewMode.tiles,
      showTileMetadata: embed.settings.showMetadata,
      tree: embed.settings.folderViewMode == FileBrowserViewMode.tree,
      openOnTap: embed.settings.folderViewMode != FileBrowserViewMode.columns,
      // Initial page paint must not steal the document's caret. Navigation is
      // explicit; newly opened columns then own arrow/Enter activation.
      autofocus: embed.settings.folderViewMode == FileBrowserViewMode.columns &&
          controller.folderPath.length > 1 &&
          controller.folderPath.last.id == folder.id,
      onOpen: _open,
      onContextMenu: (_, position) => embed.onShowMenu(position),
      onBackgroundContextMenu: embed.onShowMenu,
      onParent: controller.folderPath.length > 1
          ? () =>
              _navigate(controller.folderPath[controller.folderPath.length - 2])
          : null,
      onToggle: (entry) {
        if (controller.childrenError(entry.id) != null) {
          unawaited(controller.retryChildren(entry.id));
          return;
        }
        setState(() {
          if (!controller.expandedFolders.remove(entry.id)) {
            controller.expandedFolders.add(entry.id);
          }
        });
        if (controller.expandedFolders.contains(entry.id)) {
          unawaited(controller.ensureLoaded(entry.id));
        }
      },
      emptyMessage:
          query.isEmpty ? 'This folder is empty' : 'No matching items',
    );
  }

  @override
  Widget build(BuildContext context) {
    final embed = widget.embed;
    final path = embed.controller.folderPath;
    final current = path.last;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        primary: false,
        child: SizedBox(
          // At tiny/high-DPI embed sizes chrome scrolls rather than overflowing
          // or being hidden. In an ordinary viewport this adds no outer scroll.
          height: math.max(180.0, constraints.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FolderEmbedFilter(embed: embed),
              if (path.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final ancestor in path)
                        TextButton(
                          onPressed: () => _navigate(ancestor),
                          style: WorkspaceChrome.controlStyle(context),
                          child: Text(ancestor.name, maxLines: 1),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: embed.settings.folderViewMode ==
                            FileBrowserViewMode.columns &&
                        embed.controller.folderQuery.isEmpty
                    ? FileBrowserColumns(
                        onNavigate: (id) =>
                            _navigate(path.firstWhere((view) => view.id == id)),
                        columns: [
                          for (var index = 0; index < path.length; index++)
                            FileBrowserColumn(
                              id: path[index].id,
                              label: path[index].name,
                              child: _items(
                                path[index],
                                activeChildId: index + 1 < path.length
                                    ? path[index + 1].id
                                    : null,
                              ),
                            ),
                        ],
                      )
                    : _items(current),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One controller across presentation changes and the expanded route.
class FolderEmbedFilter extends StatelessWidget {
  const FolderEmbedFilter({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: TextEntryShortcuts(
          child: TextField(
            key: const ValueKey('folder-browser-filter'),
            controller: embed.controller.folderFilter,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Filter this folder',
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              border: InputBorder.none,
            ),
          ),
        ),
      );
}
