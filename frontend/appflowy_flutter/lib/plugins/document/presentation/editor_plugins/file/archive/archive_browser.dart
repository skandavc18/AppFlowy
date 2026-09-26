import 'dart:async';

import 'package:appflowy/shared/file_browser/file_browser_items.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_selection.dart';
import 'package:flutter/material.dart';

import 'archive_document.dart';
import 'archive_view_factory.dart';

/// Row and tile archive presentations over the exact entries used by the gallery.
/// Neither changing a mode nor expanding a directory encodes the archive.
class ArchiveBrowser extends StatefulWidget {
  const ArchiveBrowser({
    super.key,
    required this.mode,
    required this.entries,
    required this.path,
    required this.paths,
    required this.rootLabel,
    required this.loadChildren,
    required this.selection,
    required this.onOpen,
    required this.onNavigate,
    required this.onMenu,
    required this.onBackgroundMenu,
    required this.emptyMessage,
    required this.editable,
    required this.onRename,
    required this.onRenameSubmitted,
    required this.onRenameCancelled,
    required this.listingRevision,
    this.renamingPath,
    this.searching = false,
    this.loading = false,
  });

  final FileBrowserViewMode mode;
  final List<ArchiveEntryView> entries;
  final String path;
  final List<String> paths;
  final String rootLabel;
  final Future<List<ArchiveEntryView>> Function(String) loadChildren;
  final WorkspaceExplorerSelection selection;
  final ValueChanged<ArchiveEntryView> onOpen;
  final ValueChanged<String> onNavigate;
  final void Function(ArchiveEntryView, Offset) onMenu;
  final ValueChanged<Offset> onBackgroundMenu;
  final String emptyMessage;
  final bool editable;
  final ValueChanged<ArchiveEntryView> onRename;
  final Future<bool> Function(ArchiveEntryView, String) onRenameSubmitted;
  final VoidCallback onRenameCancelled;
  final String? renamingPath;
  final bool searching;
  final bool loading;
  final Object? listingRevision;

  @override
  State<ArchiveBrowser> createState() => _ArchiveBrowserState();
}

class _ArchiveBrowserState extends State<ArchiveBrowser> {
  final _expanded = <String>{};
  final _children = <String, List<ArchiveEntryView>>{};
  final _loading = <String>{};
  final _failed = <String>{};
  int _generation = 0;

  @override
  void didUpdateWidget(covariant ArchiveBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listingRevision != widget.listingRevision) {
      _generation++;
      _children.clear();
      _loading.clear();
      _failed.clear();
      for (final path in _expanded) {
        unawaited(_load(path));
      }
    }
  }

  Future<void> _load(String path) async {
    if (_children.containsKey(path) || !_loading.add(path)) return;
    final generation = _generation;
    try {
      final entries = await widget.loadChildren(path);
      if (!mounted || generation != _generation) return;
      setState(() {
        _children[path] = entries;
        _loading.remove(path);
        _failed.remove(path);
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading.remove(path);
        _failed.add(path);
      });
    }
  }

  FileBrowserEntry _entry(ArchiveEntryView entry, [int depth = 0]) =>
      FileBrowserEntry(
        view: entry.view,
        item: entry.item,
        size: entry.entry.size,
        modified: entry.entry.modified,
        depth: depth,
        expanded: _expanded.contains(entry.entry.path),
        loading: _loading.contains(entry.entry.path),
      );

  Widget _items(
    List<ArchiveEntryView> entries, {
    String? activePath,
    bool tree = false,
    bool currentColumn = false,
  }) {
    final byId = <String, ArchiveEntryView>{};
    final rows = <FileBrowserEntry>[];
    void append(List<ArchiveEntryView> values, int depth) {
      for (final value in values) {
        byId[value.view.id] = value;
        rows.add(_entry(value, depth));
        if (tree && _expanded.contains(value.entry.path)) {
          append(_children[value.entry.path] ?? const [], depth + 1);
        }
      }
    }

    append(entries, 0);
    String? idForPath(String? path) {
      for (final entry in byId.values) {
        if (entry.entry.path == path) return entry.view.id;
      }
      return null;
    }

    return FileBrowserItems(
      entries: rows,
      selection: widget.selection,
      details: widget.mode == FileBrowserViewMode.details,
      tiles: widget.mode == FileBrowserViewMode.tiles,
      tree: tree,
      openOnTap: widget.mode != FileBrowserViewMode.columns,
      autofocus: currentColumn && widget.paths.length > 1,
      activeChildId: idForPath(activePath),
      editingId: widget.editable ? idForPath(widget.renamingPath) : null,
      onOpen: (entry) => widget.onOpen(byId[entry.id]!),
      onRename:
          widget.editable ? (entry) => widget.onRename(byId[entry.id]!) : null,
      onRenameSubmitted: (entry, name) => widget.editable
          ? widget.onRenameSubmitted(byId[entry.id]!, name)
          : Future.value(false),
      onRenameCancelled: widget.onRenameCancelled,
      onContextMenu: (entry, position) =>
          widget.onMenu(byId[entry.id]!, position),
      onBackgroundContextMenu: widget.onBackgroundMenu,
      onParent: widget.path.isEmpty
          ? null
          : () => widget.onNavigate(archiveParentPath(widget.path)),
      onToggle: (entry) {
        final path = byId[entry.id]!.entry.path;
        setState(() {
          if (!_expanded.remove(path)) _expanded.add(path);
        });
        if (_expanded.contains(path)) unawaited(_load(path));
      },
      emptyMessage: widget.emptyMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == FileBrowserViewMode.columns && !widget.searching) {
      return FileBrowserColumns(
        onNavigate: widget.onNavigate,
        columns: [
          for (var index = 0; index < widget.paths.length; index++)
            FileBrowserColumn(
              id: widget.paths[index],
              label: widget.paths[index].isEmpty
                  ? widget.rootLabel
                  : archiveEntryName(widget.paths[index]),
              child: widget.paths[index] == widget.path
                  ? widget.loading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _items(widget.entries, currentColumn: true)
                  : FutureBuilder<List<ArchiveEntryView>>(
                      future: widget.loadChildren(widget.paths[index]),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text('Unable to read this folder'),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }
                        return _items(
                          snapshot.data!,
                          activePath: widget.paths[index + 1],
                        );
                      },
                    ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final path in _failed)
          TextButton(
            onPressed: () => unawaited(_load(path)),
            child: Text('Retry ${archiveEntryName(path)}'),
          ),
        Expanded(
          child: widget.loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _items(
                  widget.entries,
                  tree: widget.mode == FileBrowserViewMode.tree &&
                      !widget.searching,
                ),
        ),
      ],
    );
  }
}
