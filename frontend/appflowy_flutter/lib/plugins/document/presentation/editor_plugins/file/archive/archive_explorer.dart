import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_selection.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_picker_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_size.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'archive_document.dart';
import 'archive_browser.dart';
import 'archive_entry_viewer.dart';
import 'archive_gallery.dart';
import 'archive_view_factory.dart';

/// How often an open entry is checked for edits made by its viewer.
const Duration archiveWriteBackInterval = Duration(milliseconds: 900);

/// Browses an archive the same way the workspace browses a folder.
///
/// The archive is opened into memory and its contents are dressed as
/// workspace items, so the folder gallery draws them with the very same
/// cards. Opening an entry hands it to the viewer that file type already has,
/// and anything written back lands in the archive on disk.
class ArchiveExplorer extends StatefulWidget {
  const ArchiveExplorer({
    super.key,
    required this.file,
    required this.name,
    this.editable = true,
    this.embedded = true,
    this.toolbarTrailing,
    this.headerIcon,
    this.metadata = const {},
    this.onMetadataChanged,
    this.canEdit,
    this.onSessionViewModeChanged,
    this.onChanged,
    this.mediaActions = const MediaActionService(),
  });

  /// The archive on disk.
  final File file;

  /// What the archive is called in the workspace.
  final String name;

  /// Whether the archive may be written to.
  final bool editable;

  /// Embedded in a page, as opposed to filling the window.
  final bool embedded;

  /// A host supplied control shown at the end of the heading, such as the
  /// block's own menu.
  final Widget? toolbarTrailing;

  /// The host's existing saved-icon picker, never a second icon binding.
  final Widget? headerIcon;
  final Map<String, dynamic> metadata;
  final ValueChanged<Map<String, dynamic>>? onMetadataChanged;
  final bool Function()? canEdit;
  final ValueChanged<FileBrowserViewMode>? onSessionViewModeChanged;

  /// Called after the archive on disk has been rewritten.
  final VoidCallback? onChanged;

  /// Forwarded to the independent expanded route, not the extracted entry.
  final MediaActionService mediaActions;

  @override
  State<ArchiveExplorer> createState() => _ArchiveExplorerState();
}

class _ArchiveExplorerState extends State<ArchiveExplorer> {
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode(debugLabel: 'archive-search');
  final FolderGalleryPreviewCache previewCache = FolderGalleryPreviewCache();
  final browserSelection = WorkspaceExplorerSelection();
  final Map<String, Future<List<ArchiveEntryView>>> directoryEntries = {};
  late Map<String, dynamic> _metadata = Map.of(widget.metadata);
  late FileBrowserViewMode viewMode = FileBrowserViewSettings.read(_metadata);
  Map<String, dynamic>? _incomingMetadata;
  StandaloneFileScope? _host;
  bool get _editable =>
      widget.editable &&
      (widget.canEdit?.call() ?? true) &&
      (_host?.canEdit() ?? true);

  ArchiveDocument? document;
  ArchiveViewFactory? factory;
  Directory? workingDirectory;
  Object? loadError;
  bool loading = true;

  String currentPath = '';
  String query = '';
  bool searching = false;
  String? selectedPath;
  String? renamingPath;
  String? message;
  bool saving = false;
  bool savePending = false;

  Future<List<ArchiveEntryView>>? entries;
  _ArchiveEntrySession? session;
  _ArchiveOpening? opening;
  Timer? writeBackTimer;
  Timer? searchDebounce;
  final _galleryScrolls = <FileBrowserViewMode, ScrollController>{};

  @override
  void initState() {
    super.initState();
    browserSelection.addListener(_selectionChanged);
    unawaited(GalleryCardSizeStore.ensureLoaded());
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ArchiveExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _metadata = Map.of(widget.metadata);
      viewMode = FileBrowserViewSettings.read(_metadata);
      unawaited(_load());
    } else if (!mapEquals(oldWidget.metadata, widget.metadata)) {
      _adoptMetadata(widget.metadata);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host = StandaloneFileScope.forName(context, widget.name);
    final incoming = _host?.metadata ?? widget.metadata;
    if (!mapEquals(_incomingMetadata, incoming)) _adoptMetadata(incoming);
  }

  void _adoptMetadata(Map<String, dynamic> incoming) {
    _incomingMetadata = Map.of(incoming);
    _metadata = Map.of(incoming);
    viewMode = FileBrowserViewSettings.read(incoming);
  }

  void _setViewMode(FileBrowserViewMode mode) {
    if (!mounted || mode == viewMode || renamingPath != null) return;
    setState(() {
      viewMode = mode;
      _metadata = FileBrowserViewSettings.withMode(_metadata, mode);
    });
    // A read-only archive still allows a session-only presentation choice.
    // This never invokes _persist, onChanged, or any file-byte write.
    widget.onSessionViewModeChanged?.call(mode);
    if (_editable) widget.onMetadataChanged?.call(Map.of(_metadata));
  }

  void _selectionChanged() {
    if (!mounted) return;
    final id = browserSelection.anchorId;
    final prefix = '${factory?.archiveId}::';
    final path = id != null && id.startsWith(prefix)
        ? id.substring(prefix.length)
        : null;
    if (selectedPath != path) setState(() => selectedPath = path);
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    writeBackTimer?.cancel();
    // Children are unmounted before their parent, so a source editor inside
    // the viewer has already flushed its pending write by the time this runs.
    _flushSessionSync();
    _disposeWorkingDirectory();
    searchController.dispose();
    searchFocusNode.dispose();
    browserSelection
      ..removeListener(_selectionChanged)
      ..dispose();
    previewCache.clear();
    for (final scroll in _galleryScrolls.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _disposeWorkingDirectory() {
    final directory = workingDirectory;
    workingDirectory = null;
    if (directory == null) {
      return;
    }
    try {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // A working copy that cannot be removed is not worth reporting.
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final loaded = await ArchiveDocument.read(widget.file, name: widget.name);
      final directory = workingDirectory ??
          await Directory.systemTemp.createTemp('appflowy_archive_');
      if (!mounted) {
        return;
      }
      previewCache.clear();
      directoryEntries.clear();
      setState(() {
        document = loaded;
        workingDirectory = directory;
        factory = ArchiveViewFactory(
          archiveId: 'archive-${widget.file.path.hashCode}',
          workingDirectory: directory,
        );
        loading = false;
        currentPath = '';
        selectedPath = null;
        renamingPath = null;
        entries = _resolveEntries();
      });
    } catch (error, stackTrace) {
      Log.error('Unable to open the archive', error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        loadError = error;
        loading = false;
      });
    }
  }

  // ---------------------------------------------------------------- listing

  Future<List<ArchiveEntryView>> _resolveEntries() async {
    final value = document;
    final views = factory;
    if (value == null || views == null) {
      return const [];
    }
    if (query.isNotEmpty) {
      final matches = <ArchiveEntryView>[];
      for (final entry in value.search(query)) {
        matches.add(await views.viewFor(value, entry));
      }
      return matches;
    }
    return _childrenFor(currentPath);
  }

  Future<List<ArchiveEntryView>> _childrenFor(String path) =>
      directoryEntries.putIfAbsent(
        path,
        () => factory!.childrenOf(document!, path),
      );

  void _refreshEntries() {
    // A block body, not an arrow: an arrow would hand setState the future the
    // assignment evaluates to, which it refuses.
    setState(() {
      entries = _resolveEntries();
    });
  }

  List<String> get breadcrumbs {
    if (currentPath.isEmpty) {
      return const [''];
    }
    final paths = <String>[''];
    var accumulated = '';
    for (final segment in currentPath.split('/')) {
      accumulated = accumulated.isEmpty ? segment : '$accumulated/$segment';
      paths.add(accumulated);
    }
    return paths;
  }

  String get _subtitle {
    final value = document;
    if (value == null) {
      return '';
    }
    return [
      value.format.label,
      '${value.fileCount} files',
      '${value.folderCount} folders',
      formatArchiveBytes(value.totalSize),
      if (!_editable) 'Read only',
    ].join('  ·  ');
  }

  void _navigateTo(String path) {
    searchDebounce?.cancel();
    searchController.clear();
    browserSelection.clear();
    setState(() {
      currentPath = path;
      query = '';
      renamingPath = null;
      selectedPath = null;
    });
    _refreshEntries();
  }

  void _scheduleSearch(String value) {
    searchDebounce?.cancel();
    searchDebounce = Timer(
      const Duration(milliseconds: 180),
      () {
        if (!mounted) {
          return;
        }
        setState(() => query = value.trim());
        _refreshEntries();
      },
    );
    setState(() {});
  }

  void _openSearch() {
    setState(() => searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    searchDebounce?.cancel();
    searchController.clear();
    setState(() {
      searching = false;
      query = '';
    });
    _refreshEntries();
  }

  void _open(ArchiveEntryView entry) {
    if (entry.entry.isDirectory) {
      _navigateTo(entry.entry.path);
      return;
    }
    unawaited(_openEntry(entry.entry));
  }

  // ------------------------------------------------------------- open entry

  Future<void> _openEntry(ArchiveEntry entry) async {
    final value = document;
    if (value == null) {
      return;
    }
    await _closeEntry();
    setState(() => opening = _ArchiveOpening(entry: entry, progress: 0));
    try {
      final bytes = value.readBytes(entry.path);
      final directory =
          await Directory.systemTemp.createTemp('appflowy_archive_entry_');
      final extracted = File(p.join(directory.path, entry.name));
      await _writeWithProgress(extracted, bytes, entry);
      final stat = await extracted.stat();
      if (!mounted) {
        await directory.delete(recursive: true);
        return;
      }
      setState(() {
        opening = null;
        session = _ArchiveEntrySession(
          path: entry.path,
          name: entry.name,
          directory: directory,
          file: extracted,
          length: stat.size,
          modified: stat.modified,
        );
      });
      writeBackTimer?.cancel();
      if (_editable) {
        writeBackTimer = Timer.periodic(
          archiveWriteBackInterval,
          (_) => unawaited(_syncSession()),
        );
      }
    } catch (error, stackTrace) {
      Log.error('Unable to open an archive entry', error, stackTrace);
      if (mounted) {
        setState(() => opening = null);
      }
      _showMessage(error.toString());
    }
  }

  /// Unpacks one entry a slice at a time so the wait has a number on it.
  ///
  /// A large member takes long enough that a bare spinner reads as a hang;
  /// writing in chunks costs nothing and lets the card say how far it is.
  Future<void> _writeWithProgress(
    File destination,
    Uint8List bytes,
    ArchiveEntry entry,
  ) async {
    const chunkSize = 512 * 1024;
    if (bytes.length <= chunkSize) {
      await destination.writeAsBytes(bytes, flush: true);
      return;
    }
    final sink = destination.openWrite();
    try {
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = math.min(offset + chunkSize, bytes.length);
        sink.add(Uint8List.sublistView(bytes, offset, end));
        await sink.flush();
        if (!mounted) {
          return;
        }
        setState(
          () => opening = _ArchiveOpening(
            entry: entry,
            progress: end / bytes.length,
          ),
        );
      }
    } finally {
      await sink.close();
    }
  }

  Future<void> _closeEntry() async {
    final open = session;
    if (open == null) {
      return;
    }
    writeBackTimer?.cancel();
    writeBackTimer = null;
    setState(() => session = null);
    // The viewer flushes its own pending edit as it is torn down, so the last
    // read has to wait for the frame that removes it.
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _finishSession(open);
      completer.complete();
    });
    return completer.future;
  }

  /// Copies an entry's edits back into the archive when its file has changed.
  Future<void> _syncSession() async {
    final open = session;
    final value = document;
    if (open == null || value == null || !_editable) {
      return;
    }
    try {
      if (!await open.file.exists()) {
        return;
      }
      final stat = await open.file.stat();
      if (stat.size == open.length && stat.modified == open.modified) {
        return;
      }
      open
        ..length = stat.size
        ..modified = stat.modified;
      value.writeBytes(
        open.path,
        await open.file.readAsBytes(),
        modified: stat.modified,
      );
      factory?.invalidate(open.path);
      directoryEntries.clear();
      previewCache.clear();
      if (mounted) _refreshEntries();
      await _persist();
    } catch (error, stackTrace) {
      Log.error('Unable to save an archive entry', error, stackTrace);
      _showMessage('The change could not be saved into the archive.');
    }
  }

  Future<void> _finishSession(_ArchiveEntrySession open) async {
    final value = document;
    try {
      if (_editable && value != null && await open.file.exists()) {
        final bytes = await open.file.readAsBytes();
        if (!_matchesStored(value, open.path, bytes)) {
          value.writeBytes(open.path, bytes);
          factory?.invalidate(open.path);
          directoryEntries.clear();
          previewCache.clear();
          if (mounted) _refreshEntries();
          await _persist();
        }
      }
    } catch (error, stackTrace) {
      Log.error('Unable to save an archive entry', error, stackTrace);
    } finally {
      try {
        if (await open.directory.exists()) {
          await open.directory.delete(recursive: true);
        }
      } on FileSystemException {
        // A temporary copy that cannot be removed is not worth reporting.
      }
    }
  }

  /// Writes the open entry back without waiting for a frame, for teardown.
  void _flushSessionSync() {
    final open = session;
    final value = document;
    session = null;
    if (open == null) {
      return;
    }
    try {
      if (_editable && value != null && open.file.existsSync()) {
        final bytes = open.file.readAsBytesSync();
        if (!_matchesStored(value, open.path, bytes)) {
          value.writeBytes(open.path, bytes);
          // Staged beside the archive and renamed over it, so a failure here
          // cannot leave a half written file behind.
          final staged = File('${widget.file.path}.appflowy.tmp');
          staged.writeAsBytesSync(value.encode(), flush: true);
          staged.renameSync(widget.file.path);
        }
      }
    } catch (error, stackTrace) {
      Log.error('Unable to save the archive', error, stackTrace);
    }
    try {
      if (open.directory.existsSync()) {
        open.directory.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // Nothing more can be done about a stray temporary directory here.
    }
  }

  bool _matchesStored(ArchiveDocument value, String path, Uint8List bytes) {
    try {
      final stored = value.readBytes(path);
      return stored.length == bytes.length && listEquals(stored, bytes);
    } on ArchiveDocumentException {
      return false;
    }
  }

  // --------------------------------------------------------------- mutation

  Future<void> _persist() async {
    final value = document;
    if (value == null || !_editable) {
      return;
    }
    if (saving) {
      // A change made while the previous write is in flight must not be
      // dropped; the running save picks it up before it finishes.
      savePending = true;
      return;
    }
    setState(() => saving = true);
    try {
      do {
        savePending = false;
        if (!_editable) break;
        await value.saveTo(widget.file);
      } while (savePending);
      widget.onChanged?.call();
    } catch (error, stackTrace) {
      Log.error('Unable to write the archive', error, stackTrace);
      _showMessage('The archive could not be saved.');
    } finally {
      if (mounted) {
        setState(() => saving = false);
      } else {
        saving = false;
      }
    }
  }

  Future<void> _mutate(void Function(ArchiveDocument document) change) async {
    final value = document;
    if (value == null || !_editable) {
      return;
    }
    try {
      change(value);
    } on ArchiveDocumentException catch (error) {
      _showMessage(error.message);
      return;
    }
    factory?.clear();
    directoryEntries.clear();
    previewCache.clear();
    _refreshEntries();
    await _persist();
  }

  /// Offers both places a file can come from: the computer, or a file that
  /// already lives in the workspace.
  Future<void> _addFiles() async {
    final palette = FolderExplorerPalette.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ViewerCard(
          color: palette.floatingSurface,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Row(
                    children: [
                      WorkspaceGlyph.file(
                        widget.name,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Add to ${widget.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: _ArchiveSourceRow(
                    icon: Icons.upload_file_rounded,
                    label: 'Browse this computer…',
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      unawaited(_addFilesFromDisk());
                    },
                  ),
                ),
                Divider(height: 1, color: palette.border),
                WorkspaceFilePickerMenu(
                  maxListHeight: 240,
                  onSelected: (view) {
                    Navigator.of(dialogContext).pop();
                    unawaited(_addWorkspaceFile(view));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addFilesFromDisk() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    final picked = result?.files ?? const [];
    if (picked.isEmpty) {
      return;
    }
    final additions = <String, Uint8List>{};
    for (final file in picked) {
      final path = file.path;
      if (path == null) {
        continue;
      }
      additions[joinArchivePath(currentPath, p.basename(path))] =
          await File(path).readAsBytes();
    }
    if (additions.isEmpty || !mounted) {
      return;
    }
    await _mutate((value) {
      for (final addition in additions.entries) {
        value.writeBytes(addition.key, addition.value);
      }
    });
  }

  /// Copies a file that already lives in the workspace into the archive.
  Future<void> _addWorkspaceFile(ViewPB view) async {
    final reference = view.workspaceFileReference;
    if (reference == null) {
      _showMessage('That item is not a stored file.');
      return;
    }
    try {
      final source = await materializeMediaFile(
        source: reference.url,
        name: reference.name,
      );
      final bytes = await source.readAsBytes();
      if (!mounted) {
        return;
      }
      await _mutate(
        (value) => value.writeBytes(
          joinArchivePath(currentPath, reference.name),
          bytes,
        ),
      );
    } catch (error, stackTrace) {
      Log.error('Unable to add a workspace file', error, stackTrace);
      _showMessage('"${reference.name}" could not be added.');
    }
  }

  /// Adds a folder and drops its card straight into rename mode.
  Future<void> _createFolder() async {
    final value = document;
    if (value == null) {
      return;
    }
    var name = 'New folder';
    var attempt = 2;
    while (value.containsPath(joinArchivePath(currentPath, name))) {
      name = 'New folder $attempt';
      attempt++;
    }
    final path = joinArchivePath(currentPath, name);
    await _mutate((document) => document.createDirectory(path));
    if (mounted && value.containsPath(path)) {
      setState(() {
        selectedPath = path;
        renamingPath = path;
      });
    }
  }

  Future<bool> _commitRename(ArchiveEntryView entry, String name) async {
    final trimmed = name.trim();
    setState(() => renamingPath = null);
    if (trimmed.isEmpty || trimmed == entry.entry.name) {
      return false;
    }
    await _mutate((value) => value.rename(entry.entry.path, trimmed));
    return true;
  }

  Future<void> _delete(ArchiveEntry entry) async {
    final confirmed = await _confirmDelete(entry);
    if (!confirmed || !mounted) {
      return;
    }
    if (session?.path == entry.path ||
        (entry.isDirectory &&
            session?.path.startsWith('${entry.path}/') == true)) {
      await _closeEntry();
    }
    await _mutate((value) => value.remove(entry.path));
    if (mounted &&
        (currentPath == entry.path ||
            currentPath.startsWith('${entry.path}/'))) {
      _navigateTo(entry.parentPath);
    }
  }

  Future<bool> _confirmDelete(ArchiveEntry entry) async {
    final palette = FolderExplorerPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.floatingSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          entry.isDirectory ? 'Remove folder' : 'Remove file',
          style: TextStyle(
            color: palette.textPrimary,
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          entry.isDirectory
              ? 'Remove "${entry.name}" and everything inside it from this archive?'
              : 'Remove "${entry.name}" from this archive?',
          style: TextStyle(
            color: palette.textSecondary,
            fontFamily: 'Inter',
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: palette.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _extract(ArchiveEntry entry) async {
    final value = document;
    if (value == null) {
      return;
    }
    try {
      if (entry.isDirectory) {
        final directory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Extract "${entry.name}" to',
        );
        if (directory == null) {
          return;
        }
        final prefix = '${entry.path}/';
        for (final path in value.paths.toList()) {
          if (!path.startsWith(prefix) || value.isDirectory(path)) {
            continue;
          }
          final relative = p.joinAll(
            path.substring(prefix.length).split('/'),
          );
          final destination = File(p.join(directory, entry.name, relative));
          await destination.parent.create(recursive: true);
          await destination.writeAsBytes(value.readBytes(path), flush: true);
        }
        _showMessage('Extracted "${entry.name}".');
        return;
      }
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Extract "${entry.name}" to',
        fileName: entry.name,
      );
      if (destination == null) {
        return;
      }
      await File(destination).writeAsBytes(
        value.readBytes(entry.path),
        flush: true,
      );
      _showMessage('Extracted "${entry.name}".');
    } catch (error, stackTrace) {
      Log.error('Unable to extract an archive entry', error, stackTrace);
      _showMessage('"${entry.name}" could not be extracted.');
    }
  }

  void _showMessage(String value) {
    if (!mounted) {
      return;
    }
    setState(() => message = value);
  }

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final open = session;
    if (open != null) {
      final viewer = ArchiveEntryViewer(
        key: ValueKey(open.file.path),
        file: open.file,
        name: open.name,
        path: open.path,
        archiveName: widget.name,
        editable: _editable,
        metadata: open.metadata,
        onMetadataChanged: (value) => setState(() {
          open.metadata
            ..clear()
            ..addAll(value);
        }),
        onClose: () => unawaited(_closeEntry()),
      );
      return ColoredBox(color: palette.background, child: viewer);
    }

    if (opening case final pending?) {
      return _shell(
        palette,
        _ArchiveOpeningStage(opening: pending),
      );
    }

    return _shell(
      palette,
      ContextualFindRegion(
        onFind: _openSearch,
        onDismiss: _closeSearch,
        findFocusNode: searchFocusNode,
        findOpen: searching,
        isActive: () => mounted && session == null && opening == null,
        debugLabel: 'Archive search',
        child: Focus(
          autofocus: !widget.embedded,
          child: PremiumScrollScope(
            enabled: true,
            child: _buildGallery(context, palette),
          ),
        ),
      ),
    );
  }

  /// The surface the archive sits on.
  ///
  /// A page embed is a card of its own, like the folder embed beside it; the
  /// full window simply paints the page.
  Widget _shell(FolderExplorerPalette palette, Widget child) {
    if (!widget.embedded) {
      return ColoredBox(color: palette.background, child: child);
    }
    return PreviewToolbarRegion(
      child: ViewerCard(
        color: palette.background,
        borderRadius: BorderRadius.circular(22),
        child: child,
      ),
    );
  }

  Widget _buildGallery(BuildContext context, FolderExplorerPalette palette) {
    if (loading) {
      return Center(
        child: SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: palette.accent,
          ),
        ),
      );
    }
    if (loadError != null) {
      return _ArchiveMessage(
        message: loadError.toString(),
        onRetry: () => unawaited(_load()),
      );
    }
    final value = document;
    return FutureBuilder<List<ArchiveEntryView>>(
      future: entries,
      builder: (context, snapshot) {
        final items = snapshot.connectionState == ConnectionState.done
            ? snapshot.data ?? const <ArchiveEntryView>[]
            : const <ArchiveEntryView>[];
        final header = ArchiveGalleryHeader(
          title: widget.name.isEmpty ? 'Archive' : widget.name,
          leading: widget.headerIcon,
          viewMode: viewMode,
          onViewModeChanged: _setViewMode,
          breadcrumbs: breadcrumbs,
          rootLabel: widget.name.isEmpty ? 'Archive' : widget.name,
          subtitle: _subtitle,
          searchController: searchController,
          searchFocusNode: searchFocusNode,
          searching: searching,
          onSearchChanged: _scheduleSearch,
          onSearchDismissed: _closeSearch,
          onSearchRequested: _openSearch,
          onNavigate: _navigateTo,
          editable: _editable && (value?.supportsMultipleEntries ?? false),
          busy: saving,
          keepActionsVisible: renamingPath != null ||
              (widget.embedded && _editable && value?.fileCount == 0),
          onAddFiles: () => unawaited(_addFiles()),
          onNewFolder: () => unawaited(_createFolder()),
          onRefresh: () => unawaited(_load()),
          trailing: _buildHeaderTrailing(),
        );
        final gallery = viewMode == FileBrowserViewMode.gallery ||
            viewMode == FileBrowserViewMode.thumbnails;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message != null) _buildMessageBanner(palette),
            // Only the listing changes mode. Keep the header/search element
            // in one permanent slot in both embedded and standalone hosts.
            header,
            if (snapshot.hasError)
              TextButton(
                onPressed: () {
                  directoryEntries.clear();
                  _refreshEntries();
                },
                child: const Text('Unable to read this folder. Retry'),
              ),
            if (query.isNotEmpty &&
                snapshot.connectionState == ConnectionState.done)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    '${items.length} matches · all folders',
                    key: const ValueKey('archive-search-results'),
                  ),
                ),
              ),
            Expanded(
              child: !gallery
                  ? ArchiveBrowser(
                      mode: viewMode,
                      entries: items,
                      loading: snapshot.connectionState != ConnectionState.done,
                      path: currentPath,
                      paths: breadcrumbs,
                      rootLabel: widget.name,
                      loadChildren: _childrenFor,
                      selection: browserSelection,
                      onOpen: _open,
                      onNavigate: _navigateTo,
                      onMenu: (entry, position) => unawaited(
                        _showEntryMenu(context, entry.entry, position),
                      ),
                      onBackgroundMenu: (position) =>
                          unawaited(_showBackgroundMenu(context, position)),
                      emptyMessage: query.isEmpty
                          ? 'This archive is empty'
                          : 'No entries match your search',
                      editable: _editable &&
                          (value?.supportsMultipleEntries ?? false),
                      onRename: (entry) =>
                          setState(() => renamingPath = entry.entry.path),
                      onRenameSubmitted: _commitRename,
                      onRenameCancelled: () =>
                          setState(() => renamingPath = null),
                      renamingPath: renamingPath,
                      searching: query.isNotEmpty,
                      listingRevision: entries,
                    )
                  : ArchiveGallery(
                      scrollController: _galleryScrolls.putIfAbsent(
                        viewMode,
                        () => FileBrowserScrollController(),
                      ),
                      searching: query.isNotEmpty,
                      entries: items,
                      previewCache: previewCache,
                      compact: widget.embedded,
                      thumbnails: viewMode == FileBrowserViewMode.thumbnails,
                      selectedPath: selectedPath,
                      renamingPath: renamingPath,
                      editable: _editable &&
                          (value?.supportsMultipleEntries ?? false),
                      onSelect: (entry) =>
                          browserSelection.selectOnly(entry.view.id),
                      onOpen: _open,
                      onRenameRequested: (entry) =>
                          setState(() => renamingPath = entry.entry.path),
                      onRenameSubmitted: _commitRename,
                      onRenameCancelled: () =>
                          setState(() => renamingPath = null),
                      onMore: (entry, position) => unawaited(
                        _showEntryMenu(context, entry.entry, position),
                      ),
                      onBackgroundContextMenu: (position) =>
                          unawaited(_showBackgroundMenu(context, position)),
                      emptyMessage: query.isEmpty
                          ? 'This archive is empty'
                          : 'No entries match your search',
                    ),
            ),
          ],
        );
      },
    );
  }

  /// The controls at the end of the heading.
  ///
  /// An embedded archive can be thrown open into a full window; the full
  /// window has nowhere further to go.
  Widget? _buildHeaderTrailing() {
    if (!widget.embedded) {
      return widget.toolbarTrailing;
    }
    final originalPath = widget.file.path;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ArchivePillButton(
          icon: Icons.open_in_full_rounded,
          tooltip: 'Open full window',
          onPressed: () => unawaited(
            showArchiveFullscreen(
              context,
              file: widget.file,
              name: widget.name,
              editable: _editable,
              canEdit: () =>
                  mounted && widget.file.path == originalPath && _editable,
              metadata: _metadata,
              onSessionViewModeChanged: (mode) {
                if (!mounted || widget.file.path != originalPath) return;
                setState(() {
                  viewMode = mode;
                  _metadata = FileBrowserViewSettings.withMode(_metadata, mode);
                });
              },
              onMetadataChanged: (value) {
                if (!mounted || widget.file.path != originalPath) return;
                setState(() => _adoptMetadata(value));
                if (_editable) widget.onMetadataChanged?.call(value);
              },
              onChanged: widget.onChanged,
              mediaActions: widget.mediaActions,
            ),
          ),
        ),
        if (widget.toolbarTrailing case final trailing?) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  Widget _buildMessageBanner(FolderExplorerPalette palette) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.info_rounded, size: 16, color: palette.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message ?? '',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                color: palette.textSecondary,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => message = null),
            icon: const Icon(Icons.close_rounded, size: 15),
            color: palette.textMuted,
            splashRadius: 14,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  /// The menu behind a right click on the archive's empty space.
  ///
  /// The same operations the heading offers, brought to wherever the pointer
  /// happens to be.
  Future<void> _showBackgroundMenu(
    BuildContext menuContext,
    Offset position,
  ) async {
    final canEdit = _editable && (document?.supportsMultipleEntries ?? false);
    final action = await showAppMenu<_ArchiveBackgroundAction>(
      context: menuContext,
      globalPosition: position,
      entries: [
        if (canEdit) ...[
          AppMenuItem(
            label: 'Add files…',
            icon: workspaceAddFileIcon,
            value: _ArchiveBackgroundAction.addFiles,
          ),
          AppMenuItem(
            label: 'New folder',
            icon: workspaceAddFolderIcon,
            value: _ArchiveBackgroundAction.newFolder,
          ),
          const AppMenuSeparator(),
        ],
        if (currentPath.isNotEmpty)
          const AppMenuItem(
            label: 'Go up',
            icon: Icons.drive_folder_upload_rounded,
            value: _ArchiveBackgroundAction.goUp,
          ),
        const AppMenuItem(
          label: 'Reload archive',
          icon: Icons.refresh_rounded,
          value: _ArchiveBackgroundAction.refresh,
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ArchiveBackgroundAction.addFiles:
        await _addFiles();
      case _ArchiveBackgroundAction.newFolder:
        await _createFolder();
      case _ArchiveBackgroundAction.goUp:
        _navigateTo(archiveParentPath(currentPath));
      case _ArchiveBackgroundAction.refresh:
        await _load();
    }
  }

  Future<void> _showEntryMenu(
    BuildContext menuContext,
    ArchiveEntry entry,
    Offset position,
  ) async {
    final canEdit = _editable && (document?.supportsMultipleEntries ?? false);
    final action = await showAppMenu<_ArchiveEntryAction>(
      context: menuContext,
      globalPosition: position,
      entries: [
        AppMenuItem(
          label: 'Open',
          icon: entry.isDirectory
              ? Icons.folder_open_rounded
              : Icons.open_in_new_rounded,
          value: _ArchiveEntryAction.open,
        ),
        const AppMenuItem(
          label: 'Extract to…',
          icon: Icons.download_rounded,
          value: _ArchiveEntryAction.extract,
        ),
        if (canEdit) ...[
          const AppMenuSeparator(),
          const AppMenuItem(
            label: 'Rename',
            icon: Icons.drive_file_rename_outline_rounded,
            value: _ArchiveEntryAction.rename,
          ),
          const AppMenuItem(
            label: 'Remove',
            icon: Icons.delete_outline_rounded,
            value: _ArchiveEntryAction.delete,
            destructive: true,
          ),
        ],
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ArchiveEntryAction.open:
        if (entry.isDirectory) {
          _navigateTo(entry.path);
        } else {
          await _openEntry(entry);
        }
      case _ArchiveEntryAction.extract:
        await _extract(entry);
      case _ArchiveEntryAction.rename:
        setState(() => renamingPath = entry.path);
      case _ArchiveEntryAction.delete:
        await _delete(entry);
    }
  }
}

/// Opens an archive as a full window of cards.
Future<void> showArchiveFullscreen(
  BuildContext context, {
  required File file,
  required String name,
  required bool editable,
  Map<String, dynamic> metadata = const {},
  ValueChanged<Map<String, dynamic>>? onMetadataChanged,
  bool Function()? canEdit,
  ValueChanged<FileBrowserViewMode>? onSessionViewModeChanged,
  VoidCallback? onChanged,
  MediaActionService mediaActions = const MediaActionService(),
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: MediaQuery.disableAnimationsOf(context) ||
              MediaQuery.accessibleNavigationOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      reverseTransitionDuration: MediaQuery.disableAnimationsOf(context) ||
              MediaQuery.accessibleNavigationOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      pageBuilder: (_, __, ___) => _ArchiveFullscreenView(
        file: file,
        name: name,
        editable: editable,
        metadata: metadata,
        onMetadataChanged: onMetadataChanged,
        canEdit: canEdit,
        onSessionViewModeChanged: onSessionViewModeChanged,
        onChanged: onChanged,
        mediaActions: mediaActions,
      ),
    ),
  );
}

class _ArchiveFullscreenView extends StatefulWidget {
  const _ArchiveFullscreenView({
    required this.file,
    required this.name,
    required this.editable,
    required this.onChanged,
    required this.mediaActions,
    required this.metadata,
    required this.onMetadataChanged,
    this.canEdit,
    this.onSessionViewModeChanged,
  });

  final File file;
  final String name;
  final bool editable;
  final VoidCallback? onChanged;
  final MediaActionService mediaActions;
  final Map<String, dynamic> metadata;
  final ValueChanged<Map<String, dynamic>>? onMetadataChanged;
  final bool Function()? canEdit;
  final ValueChanged<FileBrowserViewMode>? onSessionViewModeChanged;

  @override
  State<_ArchiveFullscreenView> createState() => _ArchiveFullscreenViewState();
}

class _ArchiveFullscreenViewState extends State<_ArchiveFullscreenView> {
  final _chrome = StandaloneFileChromeController();
  final _fileActionsKey = GlobalKey(debugLabel: 'archive-file-actions');
  bool _closing = false;

  void _close() {
    if (!mounted || _closing) return;
    final route = ModalRoute.of(context);
    // A stale callback must not close a newer menu/dialog or the page below us.
    if (route?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final source = MediaActionSource(
      source: widget.file.path,
      name: widget.name,
    );
    return Scaffold(
      key: const ValueKey('archive-fullscreen'),
      backgroundColor: palette.background,
      body: ContextualFindScope(
        child: SafeArea(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _close,
              const SingleActivator(LogicalKeyboardKey.f11): _close,
            },
            child: PreviewToolbarRegion(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<StandaloneFileHeader>(
                    valueListenable: _chrome,
                    builder: (context, controls, _) {
                      final fileActions = Row(
                        key: _fileActionsKey,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MediaActionButtons(
                            source: source,
                            actions: widget.mediaActions,
                            decorated: false,
                          ),
                        ],
                      );
                      final toolbar = controls.toolbarBuilder?.call(
                            context,
                            fileActions,
                          ) ??
                          fileActions;
                      return Padding(
                        // Reserve the existing Copy feedback badge, without a
                        // second action strip above the archive controls.
                        padding: EdgeInsets.only(
                          top:
                              MediaQuery.textScalerOf(context).scale(10) * 1.2 +
                                  6,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: DocumentViewportHeader(
                              identity: DocumentIdentity(
                                title: widget.name,
                                icon: Icons.folder_zip_rounded,
                              ),
                              background: palette.background,
                              keepActionsVisible: controls.keepActionsVisible,
                              toolbar: toolbar,
                            )),
                            // Route-owned, always visible, outside renderer reveal
                            // and horizontal overflow. FileAction slots stay unique.
                            WorkspaceControlButton(
                              key: const ValueKey('archive-fullscreen-close'),
                              icon: Icons.close_rounded,
                              tooltip: 'Close',
                              onPressed: _close,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: StandaloneFileScope(
                      canvas: palette.background,
                      rendererName: widget.name,
                      displayName: widget.name,
                      chrome: _chrome,
                      canEdit: () =>
                          mounted &&
                          widget.editable &&
                          (widget.canEdit?.call() ?? true),
                      canRead: () => mounted,
                      editable: widget.editable,
                      available: true,
                      child: ArchiveExplorer(
                        key: ValueKey('fullscreen-${widget.file.path}'),
                        file: widget.file,
                        name: widget.name,
                        editable: widget.editable,
                        embedded: false,
                        metadata: widget.metadata,
                        onMetadataChanged: widget.onMetadataChanged,
                        canEdit: widget.canEdit,
                        onSessionViewModeChanged:
                            widget.onSessionViewModeChanged,
                        onChanged: widget.onChanged,
                        mediaActions: widget.mediaActions,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ArchiveEntryAction { open, extract, rename, delete }

enum _ArchiveBackgroundAction { addFiles, newFolder, goUp, refresh }

/// An entry on its way out of the archive and into its viewer.
@immutable
class _ArchiveOpening {
  const _ArchiveOpening({required this.entry, required this.progress});

  final ArchiveEntry entry;

  /// How much of the entry has been written out, 0 to 1.
  final double progress;
}

/// What the window shows while an entry is being unpacked.
class _ArchiveOpeningStage extends StatelessWidget {
  const _ArchiveOpeningStage({required this.opening});

  final _ArchiveOpening opening;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final percent = (opening.progress.clamp(0.0, 1.0) * 100).round();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(19),
              ),
              alignment: Alignment.center,
              child: WorkspaceGlyph.file(
                opening.entry.name,
                size: 26,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              opening.entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: opening.progress <= 0 ? null : opening.progress,
                minHeight: 5,
                backgroundColor: palette.accent.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(palette.accent),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              opening.progress <= 0
                  ? 'Unpacking…'
                  : 'Unpacking  ·  $percent%  of  '
                      '${formatArchiveBytes(opening.entry.size)}',
              style: TextStyle(
                color: palette.textMuted,
                fontFamily: 'Inter',
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The extracted working copy of one entry while its viewer is open.
class _ArchiveEntrySession {
  _ArchiveEntrySession({
    required this.path,
    required this.name,
    required this.directory,
    required this.file,
    required this.length,
    required this.modified,
  });

  final String path;
  final String name;
  final Directory directory;
  final File file;
  final Map<String, dynamic> metadata = {};

  int length;
  DateTime modified;
}

class _ArchiveMessage extends StatelessWidget {
  const _ArchiveMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const WorkspaceGlyph.named(
                'file-zip',
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ArchivePillButton(
              icon: Icons.refresh_rounded,
              label: 'Try again',
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// One place a file can be taken from, in the "add to archive" sheet.
class _ArchiveSourceRow extends StatelessWidget {
  const _ArchiveSourceRow({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return TextButton(
      onPressed: onPressed,
      style: WorkspaceChrome.controlStyle(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: [
            WorkspaceGlyph(icon, size: 17, color: palette.accent),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                ),
              ),
            ),
            WorkspaceGlyph(
              Icons.chevron_right_rounded,
              size: 17,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
