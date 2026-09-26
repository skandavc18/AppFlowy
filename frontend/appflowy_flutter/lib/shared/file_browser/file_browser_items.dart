import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_selection.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

/// A light projection of a production item, not another file model. Archive
/// adapters can supply the directory aggregates recorded by their index.
class FileBrowserEntry {
  const FileBrowserEntry({
    required this.view,
    required this.item,
    this.depth = 0,
    this.expanded = false,
    this.loading = false,
    this.failed = false,
    this.size,
    this.modified,
  });

  factory FileBrowserEntry.fromView(ViewPB view) => FileBrowserEntry(
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
      );

  final ViewPB view;
  final WorkspaceExplorerItem item;
  final int depth;
  final bool expanded;
  final bool loading;
  final bool failed;
  final int? size;
  final DateTime? modified;

  String get id => item.id;
  int? get byteSize => size ?? item.metadata?.size;
  DateTime? get date => modified ?? item.lastEdited;
  String get type {
    if (item.isFolder) return 'Folder';
    if (item.kind == WorkspaceExplorerItemKind.document) return 'Page';
    if (item.kind == WorkspaceExplorerItemKind.database) return 'Database';
    final mime = item.metadata?.mimeType;
    if (mime != null && mime.isNotEmpty) return mime;
    final dot = item.name.lastIndexOf('.');
    return dot > 0 && dot < item.name.length - 1
        ? item.name.substring(dot + 1).toUpperCase()
        : 'File';
  }

  /// Tiles are for recognition, not MIME inspection. Details retains [type]
  /// verbatim; these labels are derived only from a stored MIME or extension.
  String get tileType {
    if (!item.isFile) return type;
    final mime = item.metadata?.mimeType?.split(';').first.trim().toLowerCase();
    final known = switch (mime) {
      'application/pdf' => 'PDF document',
      'image/png' => 'PNG image',
      'image/jpeg' => 'JPEG image',
      'image/svg+xml' => 'SVG image',
      'application/zip' || 'application/x-zip-compressed' => 'ZIP archive',
      'text/plain' => 'Text file',
      'text/markdown' => 'Markdown document',
      'text/csv' => 'CSV spreadsheet',
      _ => null,
    };
    if (known != null) return known;
    if (mime?.startsWith('image/') ?? false) return 'Image';
    if (mime?.startsWith('video/') ?? false) return 'Video';
    if (mime?.startsWith('audio/') ?? false) return 'Audio';
    if (mime?.startsWith('text/') ?? false) return 'Text file';
    final dot = item.name.lastIndexOf('.');
    final extension = dot > 0 && dot < item.name.length - 1
        ? item.name.substring(dot + 1).toLowerCase()
        : '';
    return switch (extension) {
      'pdf' => 'PDF document',
      'png' ||
      'jpg' ||
      'jpeg' ||
      'gif' ||
      'webp' ||
      'svg' ||
      'avif' =>
        '${extension.toUpperCase()} image',
      'doc' || 'docx' => 'Word document',
      'xls' || 'xlsx' => 'Excel spreadsheet',
      'ppt' || 'pptx' => 'PowerPoint presentation',
      'zip' ||
      'tar' ||
      'gz' ||
      '7z' ||
      'rar' =>
        '${extension.toUpperCase()} archive',
      'md' || 'markdown' => 'Markdown document',
      'txt' => 'Text file',
      '' => 'File',
      _ => '${extension.toUpperCase()} file',
    };
  }
}

String fileBrowserSizeLabel(int? size) {
  if (size == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = size.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
}

/// Compact rows, tabular Details, and adaptive Explorer-style Tiles. The host
/// owns selection, mutations, open/context callbacks and the underlying graph.
class FileBrowserItems extends StatefulWidget {
  const FileBrowserItems({
    super.key,
    required this.entries,
    required this.selection,
    required this.onOpen,
    this.details = false,
    this.tiles = false,
    this.showTileMetadata = true,
    this.tree = false,
    this.openOnTap = true,
    this.autofocus = false,
    this.activeChildId,
    this.editingId,
    this.onRename,
    this.onRenameSubmitted,
    this.onRenameCancelled,
    this.onContextMenu,
    this.onBackgroundContextMenu,
    this.onToggle,
    this.onParent,
    this.onCopy,
    this.onCut,
    this.onPaste,
    this.onDelete,
    this.onActivateColumn,
    this.rowWrapper,
    this.draft,
    this.emptyMessage = 'This folder is empty',
  });

  final List<FileBrowserEntry> entries;
  final WorkspaceExplorerSelection selection;
  final ValueChanged<FileBrowserEntry> onOpen;
  final bool details;
  final bool tiles;
  final bool showTileMetadata;
  final bool tree;
  final bool openOnTap;
  final bool autofocus;
  final String? activeChildId;
  final String? editingId;
  final ValueChanged<FileBrowserEntry>? onRename;
  final Future<bool> Function(FileBrowserEntry entry, String name)?
      onRenameSubmitted;
  final VoidCallback? onRenameCancelled;
  final void Function(FileBrowserEntry entry, Offset position)? onContextMenu;
  final ValueChanged<Offset>? onBackgroundContextMenu;
  final ValueChanged<FileBrowserEntry>? onToggle;
  final VoidCallback? onParent;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;
  final VoidCallback? onDelete;
  final VoidCallback? onActivateColumn;
  final Widget Function(FileBrowserEntry entry, Widget row)? rowWrapper;
  final Widget? draft;
  final String emptyMessage;

  @override
  State<FileBrowserItems> createState() => _FileBrowserItemsState();
}

class _FileBrowserItemsState extends State<FileBrowserItems> {
  final _focus = FocusNode(debugLabel: 'file-browser-items');
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  String? _sort;
  bool _descending = false;
  String? _keyboardCursor;
  int _tileColumns = 1;
  double _tileWidth = 0;

  static const _tilePadding = 8.0;
  static const _tileSpacing = 8.0;

  // A fullscreen browser can share navigation with its still-mounted inline
  // owner. Only the current route may focus a newly opened column; Flutter's
  // inactive routes skip traversal but still allow explicit focus requests.
  bool get _shouldAutofocus =>
      widget.autofocus && ModalRoute.of(context)?.isCurrent != false;

  List<FileBrowserEntry> get _ordered {
    if (_sort == null || widget.tree) return widget.entries;
    final rows = [...widget.entries];
    rows.sort((a, b) {
      if (a.item.isFolder != b.item.isFolder) return a.item.isFolder ? -1 : 1;
      // Unknown values stay last in either direction, never a fabricated zero.
      final Object? left = _sortValue(a);
      final Object? right = _sortValue(b);
      if (left == null || right == null) {
        return left == right ? 0 : (left == null ? 1 : -1);
      }
      final compared = switch ((left, right)) {
        (final int l, final int r) => l.compareTo(r),
        (final DateTime l, final DateTime r) => l.compareTo(r),
        _ => left.toString().compareTo(right.toString()),
      };
      return _descending ? -compared : compared;
    });
    return rows;
  }

  Object? _sortValue(FileBrowserEntry row) => switch (_sort) {
        'Type' => row.type.toLowerCase(),
        'Size' => row.byteSize,
        'Date modified' => row.date,
        _ => row.item.name.toLowerCase(),
      };

  @override
  void didUpdateWidget(covariant FileBrowserItems oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _shouldAutofocus) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final height = widget.tiles
        ? math.max(
            80.0,
            24 +
                (scaler.scale(13) * 1.4).ceilToDouble() +
                (widget.showTileMetadata
                    ? 2 * (scaler.scale(11) * 1.4).ceilToDouble()
                    : 0),
          )
        : math.max(34.0, scaler.scale(13) * 1.4 + 12);
    final ordered = _ordered;
    return AnimatedBuilder(
      animation: widget.selection,
      builder: (context, _) => Focus(
        focusNode: _focus,
        autofocus: _shouldAutofocus,
        onKeyEvent: (node, event) => _key(event, ordered, height),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: widget.onBackgroundContextMenu == null
              ? null
              : (details) =>
                  widget.onBackgroundContextMenu!(details.globalPosition),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
              // Keep the glyph at 36px; grow the adjacent text allowance with
              // text scaling. Even a narrow 2x embed gets one usable column.
              _tileColumns = math.max(
                1,
                ((constraints.maxWidth - 2 * _tilePadding + _tileSpacing) /
                        (72 + 200 * scale + _tileSpacing))
                    .floor(),
              );
              final tileAvailable = math.max(
                0.0,
                constraints.maxWidth -
                    2 * _tilePadding -
                    (_tileColumns - 1) * _tileSpacing,
              );
              _tileWidth = math.min(
                tileAvailable / _tileColumns,
                (72 + 200 * scale) * 1.2,
              );
              final tileRemainder = tileAvailable - _tileWidth * _tileColumns;
              final indices = <Key, int>{
                for (var index = 0; index < ordered.length; index++)
                  ValueKey(ordered[index].id): index,
              };
              Widget itemBuilder(BuildContext context, int index) =>
                  _row(ordered[index], ordered);
              final width = widget.details
                  ? math.max(constraints.maxWidth, 640.0 * scale)
                  : constraints.maxWidth;
              return Scrollbar(
                controller: _horizontal,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.details) _heading(context, scale),
                        if (widget.draft != null) widget.draft!,
                        Expanded(
                          child: ordered.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      widget.emptyMessage,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: palette.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                )
                              : widget.tiles
                                  ? GridView.builder(
                                      key: const ValueKey('file-browser-tiles'),
                                      controller: _vertical,
                                      padding: EdgeInsetsDirectional.fromSTEB(
                                        _tilePadding,
                                        _tilePadding,
                                        _tilePadding + tileRemainder,
                                        _tilePadding,
                                      ),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: _tileColumns,
                                        crossAxisSpacing: _tileSpacing,
                                        mainAxisSpacing: _tileSpacing,
                                        mainAxisExtent: height,
                                      ),
                                      itemCount: ordered.length,
                                      findChildIndexCallback: (key) =>
                                          indices[key],
                                      itemBuilder: itemBuilder,
                                    )
                                  : ListView.builder(
                                      key: PageStorageKey(
                                        widget.key ?? 'file-browser-list',
                                      ),
                                      controller: _vertical,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      itemExtent: height,
                                      itemCount: ordered.length,
                                      findChildIndexCallback: (key) =>
                                          indices[key],
                                      itemBuilder: itemBuilder,
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _row(FileBrowserEntry entry, List<FileBrowserEntry> ordered) {
    final row = _FileBrowserRow(
      key: ValueKey('file-browser-row-${entry.id}'),
      entry: entry,
      details: widget.details,
      tiles: widget.tiles,
      showTileMetadata: widget.showTileMetadata,
      tree: widget.tree,
      selected: widget.selection.contains(entry.id) ||
          widget.activeChildId == entry.id,
      editing: widget.editingId == entry.id,
      onTap: () => _tap(entry, ordered),
      onOpen: () => widget.onOpen(entry),
      onFocus: () {
        _keyboardCursor = entry.id;
        widget.onActivateColumn?.call();
        widget.selection.selectOnly(entry.id);
      },
      onRename: widget.onRename == null ? null : () => widget.onRename!(entry),
      onSubmitted: (name) =>
          widget.onRenameSubmitted?.call(entry, name) ?? Future.value(false),
      onCancelled: widget.onRenameCancelled ?? () {},
      onToggle: widget.onToggle == null ? null : () => widget.onToggle!(entry),
      onMenu: widget.onContextMenu == null
          ? null
          : (position) {
              widget.onActivateColumn?.call();
              if (!widget.selection.contains(entry.id)) {
                widget.selection.selectOnly(entry.id);
              }
              widget.onContextMenu!(entry, position);
            },
    );
    return KeyedSubtree(
      key: ValueKey(entry.id),
      child: widget.rowWrapper?.call(entry, row) ?? row,
    );
  }

  Widget _heading(BuildContext context, double scale) => Padding(
        key: const ValueKey('file-browser-details-heading'),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(child: _sortButton(context, 'Name')),
            SizedBox(width: 130 * scale, child: _sortButton(context, 'Type')),
            SizedBox(width: 90 * scale, child: _sortButton(context, 'Size')),
            SizedBox(
              width: 160 * scale,
              child: _sortButton(context, 'Date modified'),
            ),
          ],
        ),
      );

  Widget _sortButton(BuildContext context, String label) => TextButton(
        style: WorkspaceChrome.controlStyle(context).copyWith(
          alignment: AlignmentDirectional.centerStart,
        ),
        onPressed: () => setState(() {
          _descending = _sort == label && !_descending;
          _sort = label;
        }),
        child:
            Text('$label${_sort == label ? (_descending ? ' ↓' : ' ↑') : ''}'),
      );

  void _tap(FileBrowserEntry entry, List<FileBrowserEntry> ordered) {
    _keyboardCursor = entry.id;
    widget.onActivateColumn?.call();
    _focus.requestFocus();
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      widget.selection.selectRange(
        id: entry.id,
        visibleIds: ordered.map((row) => row.id).toList(),
      );
    } else if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      widget.selection.toggle(entry.id);
    } else {
      widget.selection.selectOnly(entry.id);
      if (widget.openOnTap || entry.item.isBrowsable) widget.onOpen(entry);
    }
  }

  KeyEventResult _key(
    KeyEvent event,
    List<FileBrowserEntry> rows,
    double height,
  ) {
    if (event is! KeyDownEvent ||
        widget.editingId != null ||
        widget.draft != null) {
      return KeyEventResult.ignored;
    }
    // Text editors and menu buttons retain their native shortcut ownership.
    if (!_focus.hasPrimaryFocus &&
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorStateOfType<_FileBrowserRowState>() ==
            null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    final cursor =
        _keyboardCursor != null && widget.selection.contains(_keyboardCursor!)
            ? _keyboardCursor
            : widget.selection.anchorId;
    final index = rows.indexWhere((row) => row.id == cursor);
    final selected = index < 0 ? null : rows[index];
    final columns = widget.tiles ? _tileColumns : 1;
    if (widget.tiles &&
        keyboard.isAltPressed &&
        key == LogicalKeyboardKey.arrowLeft &&
        widget.onParent != null) {
      widget.onParent!();
      return KeyEventResult.handled;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final step = switch (key) {
      LogicalKeyboardKey.arrowDown => columns,
      LogicalKeyboardKey.arrowUp => -columns,
      LogicalKeyboardKey.arrowLeft when widget.tiles => rtl ? 1 : -1,
      LogicalKeyboardKey.arrowRight when widget.tiles => rtl ? -1 : 1,
      LogicalKeyboardKey.home when widget.tiles => -rows.length,
      LogicalKeyboardKey.end when widget.tiles => rows.length,
      _ => null,
    };
    if (step != null) {
      if (rows.isEmpty) return KeyEventResult.handled;
      final next = key == LogicalKeyboardKey.end
          ? rows.length - 1
          : index < 0
              ? 0
              : (index + step).clamp(0, rows.length - 1);
      final ids = rows.map((row) => row.id).toList();
      _keyboardCursor = ids[next];
      if (keyboard.isShiftPressed) {
        widget.selection.selectRange(id: ids[next], visibleIds: ids);
      } else {
        widget.selection.selectOnly(ids[next]);
      }
      _focus.requestFocus();
      if (_vertical.hasClients) {
        final target = widget.tiles
            ? _tilePadding + (next ~/ columns) * (height + _tileSpacing)
            : next * height;
        final position = _vertical.position;
        if (target < position.pixels ||
            target + height > position.pixels + position.viewportDimension) {
          _vertical.jumpTo(
            target.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
        }
      }
      return KeyEventResult.handled;
    }
    if (!widget.tiles &&
        key == LogicalKeyboardKey.arrowLeft &&
        widget.onParent != null) {
      widget.onParent!();
      return KeyEventResult.handled;
    }
    if (selected != null &&
        (key == LogicalKeyboardKey.contextMenu ||
            (key == LogicalKeyboardKey.f10 && keyboard.isShiftPressed)) &&
        widget.onContextMenu != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final top = widget.tiles
            ? _tilePadding + (index ~/ columns) * (height + _tileSpacing)
            : index * height;
        final y =
            (top - (_vertical.hasClients ? _vertical.offset : 0) + height / 2)
                .clamp(0.0, box.size.height);
        var x = 20.0;
        if (widget.tiles) {
          x = _tilePadding +
              (index % columns) * (_tileWidth + _tileSpacing) +
              _tileWidth / 2;
          if (rtl) x = box.size.width - x;
        }
        widget.onContextMenu!(selected, box.localToGlobal(Offset(x, y)));
      }
      return KeyEventResult.handled;
    }
    if (isWorkspaceRenameShortcut(Theme.of(context).platform, key) &&
        selected != null &&
        widget.onRename != null) {
      widget.onRename!(selected);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space ||
            (key == LogicalKeyboardKey.arrowRight &&
                selected?.item.isBrowsable == true)) &&
        selected != null) {
      widget.onOpen(selected);
      return KeyEventResult.handled;
    }
    final VoidCallback? action = switch (key) {
      LogicalKeyboardKey.delete => widget.onDelete,
      LogicalKeyboardKey.keyC when command => widget.onCopy,
      LogicalKeyboardKey.keyX when command => widget.onCut,
      LogicalKeyboardKey.keyV when command => widget.onPaste,
      _ => null,
    };
    if (command && key == LogicalKeyboardKey.keyA) {
      widget.selection.selectAll(rows.map((row) => row.id));
      return KeyEventResult.handled;
    }
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class _FileBrowserRow extends StatefulWidget {
  const _FileBrowserRow({
    super.key,
    required this.entry,
    required this.details,
    required this.tiles,
    required this.showTileMetadata,
    required this.tree,
    required this.selected,
    required this.editing,
    required this.onTap,
    required this.onOpen,
    required this.onFocus,
    required this.onRename,
    required this.onSubmitted,
    required this.onCancelled,
    required this.onToggle,
    required this.onMenu,
  });

  final FileBrowserEntry entry;
  final bool details;
  final bool tiles;
  final bool showTileMetadata;
  final bool tree;
  final bool selected;
  final bool editing;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onFocus;
  final VoidCallback? onRename;
  final Future<bool> Function(String) onSubmitted;
  final VoidCallback onCancelled;
  final VoidCallback? onToggle;
  final ValueChanged<Offset>? onMenu;

  @override
  State<_FileBrowserRow> createState() => _FileBrowserRowState();
}

class _FileBrowserRowState extends State<_FileBrowserRow> {
  final _focus = FocusNode(debugLabel: 'File browser row');
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _menu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      widget.onMenu?.call(box.localToGlobal(box.size.center(Offset.zero)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final entry = widget.entry;
    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontSize: 13, color: palette.textPrimary);
    Widget cell(String text) => Tooltip(
          message: text,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(color: palette.textSecondary),
          ),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): _menu,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): _menu,
      },
      child: Focus(
        focusNode: _focus,
        canRequestFocus: !widget.editing,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused && _focus.hasPrimaryFocus) widget.onFocus();
        },
        onKeyEvent: (node, event) {
          if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (isWorkspaceRenameShortcut(
                Theme.of(context).platform,
                event.logicalKey,
              ) &&
              widget.onRename != null) {
            widget.onRename!();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onOpen();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: entry.item.name,
          value: widget.tiles && widget.showTileMetadata
              ? [_tileTypeSize, if (_tileModified != null) _tileModified!]
                  .join('; ')
              : null,
          onTap: widget.onOpen,
          child: Material(
            color: widget.selected ? palette.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              canRequestFocus: false,
              onTap: widget.onTap,
              onDoubleTap: widget.onOpen,
              onSecondaryTapDown: widget.onMenu == null
                  ? null
                  : (details) => widget.onMenu!(details.globalPosition),
              hoverColor: palette.hover,
              splashFactory: NoSplash.splashFactory,
              child: Container(
                key: widget.tiles
                    ? ValueKey('file-browser-tile-${entry.id}')
                    : null,
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: widget.tiles ? 10 : 0,
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: _focused
                      ? Border.all(color: palette.accent, width: 1.2)
                      : null,
                ),
                child: widget.tiles
                    ? _tile(palette)
                    : Row(
                        children: [
                          if (widget.tree) ...[
                            SizedBox(width: math.min(entry.depth * 16.0, 96)),
                            SizedBox(
                              width: 24,
                              child: entry.item.isBrowsable
                                  ? IconButton(
                                      tooltip: entry.failed
                                          ? 'Retry loading folder'
                                          : entry.expanded
                                              ? 'Collapse'
                                              : 'Expand',
                                      onPressed: widget.onToggle,
                                      padding: EdgeInsets.zero,
                                      icon: entry.loading
                                          ? const SizedBox.square(
                                              dimension: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1.4,
                                              ),
                                            )
                                          : Icon(
                                              entry.failed
                                                  ? Icons.error_outline_rounded
                                                  : entry.expanded
                                                      ? Icons
                                                          .expand_more_rounded
                                                      : Icons
                                                          .chevron_right_rounded,
                                              size: 17,
                                            ),
                                    )
                                  : null,
                            ),
                          ],
                          WorkspaceItemIcon(
                            item: entry.item,
                            view: entry.view,
                            showThumbnail: false,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: WorkspaceInlineEditableText(
                              text: entry.item.name,
                              editing: widget.editing,
                              onSubmitted: widget.onSubmitted,
                              onCancelled: widget.onCancelled,
                              selectFileStem: entry.item.isFile,
                              style: style ?? const TextStyle(fontSize: 13),
                            ),
                          ),
                          if (widget.details) ...[
                            SizedBox(
                              width: 130 * scale,
                              child: cell(entry.type),
                            ),
                            SizedBox(
                              width: 90 * scale,
                              child: cell(fileBrowserSizeLabel(entry.byteSize)),
                            ),
                            SizedBox(
                              width: 160 * scale,
                              child: cell(
                                entry.date == null
                                    ? '—'
                                    : DateFormat.yMMMd().format(entry.date!),
                              ),
                            ),
                          ] else if (entry.item.isBrowsable && !widget.tree)
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: palette.textMuted,
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _tileTypeSize => [
        widget.entry.tileType,
        if (widget.entry.byteSize != null)
          fileBrowserSizeLabel(widget.entry.byteSize),
      ].join(' · ');

  String? get _tileModified {
    final date = widget.entry.date;
    return date == null ? null : 'Modified ${DateFormat.yMMMd().format(date)}';
  }

  Widget _tile(FolderExplorerPalette palette) {
    final entry = widget.entry;
    final nameStyle = TextStyle(
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: palette.textPrimary,
    );
    final detailStyle = TextStyle(
      fontSize: 11,
      height: 1.4,
      color: palette.textSecondary,
    );
    return Tooltip(
      message: [
        entry.item.name,
        if (widget.showTileMetadata) ...[
          _tileTypeSize,
          if (_tileModified != null) _tileModified!,
        ],
      ].join('\n'),
      excludeFromSemantics: true,
      child: Row(
        children: [
          ExcludeSemantics(
            child: WorkspaceItemIcon(
              item: entry.item,
              view: entry.view,
              size: 36,
              showThumbnail: false,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ExcludeSemantics(
              excluding: !widget.editing,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // No card/rename transition: reduced-motion Tiles retain the
                  // native editor's input behavior without adding a fade.
                  if (widget.editing)
                    WorkspaceInlineNameEditor(
                      initialValue: entry.item.name,
                      onSubmitted: widget.onSubmitted,
                      onCancelled: widget.onCancelled,
                      selectFileStem: entry.item.isFile,
                      textStyle: nameStyle,
                    )
                  else
                    Text(
                      entry.item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nameStyle,
                    ),
                  if (widget.showTileMetadata) ...[
                    const SizedBox(height: 2),
                    Text(
                      _tileTypeSize,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: detailStyle,
                    ),
                    if (_tileModified != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _tileModified!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: detailStyle,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One column is one real directory. The caller supplies its cached listing
/// and status, keeping provider/workspace/archive ownership out of the widget.
class FileBrowserColumn {
  const FileBrowserColumn({
    required this.id,
    required this.label,
    required this.child,
  });

  final String id;
  final String label;
  final Widget child;
}

class FileBrowserColumns extends StatefulWidget {
  const FileBrowserColumns({
    super.key,
    required this.columns,
    required this.onNavigate,
  });

  final List<FileBrowserColumn> columns;
  final ValueChanged<String> onNavigate;

  @override
  State<FileBrowserColumns> createState() => _FileBrowserColumnsState();
}

class _FileBrowserColumnsState extends State<FileBrowserColumns> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant FileBrowserColumns oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columns.lastOrNull?.id != widget.columns.lastOrNull?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final palette = FolderExplorerPalette.of(context);
          final width = constraints.maxWidth.clamp(200.0, 280.0);
          return Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              key: const ValueKey('file-browser-columns-scroll'),
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: constraints.maxHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final column in widget.columns)
                      SizedBox(
                        key: ValueKey('file-browser-column-${column.id}'),
                        width: width,
                        child: Focus(
                          canRequestFocus: false,
                          onFocusChange: (focused) {
                            if (!focused) return;
                            final target =
                                FocusManager.instance.primaryFocus?.context;
                            if (target != null) {
                              unawaited(Scrollable.ensureVisible(target));
                            }
                          },
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: BorderDirectional(
                                end: BorderSide(
                                  color: palette.border.withValues(alpha: 0.25),
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextButton(
                                  onPressed: () => widget.onNavigate(column.id),
                                  style: WorkspaceChrome.controlStyle(context),
                                  child: Text(
                                    column.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(child: column.child),
                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
