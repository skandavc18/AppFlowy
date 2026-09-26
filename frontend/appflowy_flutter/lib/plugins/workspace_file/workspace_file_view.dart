import 'dart:async';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/plugins/collection/views/email/email_file_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_migrator.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/scrolling/trackpad_history_navigation.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

typedef WorkspaceFileExtraWriter = Future<FlowyResult<void, FlowyError>>
    Function({
  required String viewId,
  required String extra,
});

Future<FlowyResult<void, FlowyError>> _writeWorkspaceFileExtra({
  required String viewId,
  required String extra,
}) async {
  final result =
      await ViewBackendService.updateView(viewId: viewId, extra: extra);
  // UpdateView returns a success ACK, not necessarily a populated ViewPB.
  return result.fold(
    (_) => FlowyResult.success(null),
    FlowyResult.failure,
  );
}

/// The full window renderer for a workspace file.
///
/// Every file type reuses the viewer the editor already embeds: the PDF
/// reader, the media player, the picture stage, the source editor and the
/// office bridge. Only the surrounding chrome differs.
class WorkspaceFileView extends StatefulWidget {
  const WorkspaceFileView({
    super.key,
    required this.view,
    this.mediaActions = const MediaActionService(),
    this.resolveStorageUrl,
    this.materializeFile = materializeMediaFile,
    this.editable = true,
    this.iconListenerFactory,
    this.repository = const WorkspaceItemService(),
    this.coverBackend = const ViewCoverActionsBackend(),
    this.updateIcon = ViewBackendService.updateViewIcon,
    this.writeExtra = _writeWorkspaceFileExtra,
    this.ocrService,
    this.ocrSourceBuilder,
  });

  final ViewPB view;
  final MediaActionService mediaActions;

  /// Identity editing is independent of whether materialized bytes are local.
  final bool editable;
  final ViewListener Function(String viewId)? iconListenerFactory;
  final WorkspaceItemRepository repository;
  final ViewCoverActionsBackend coverBackend;
  final WorkspaceFileIconWriter updateIcon;
  final WorkspaceFileExtraWriter writeExtra;

  /// OCR-only boundaries; the retained image and its storage IO are unchanged.
  final OcrService? ocrService;
  final ImageOcrSourceBuilder? ocrSourceBuilder;

  /// Optional IO boundaries; the normal storage migration and materialization
  /// remain the defaults, and every renderer still receives the resolved file.
  final Future<String?> Function(ViewPB view)? resolveStorageUrl;
  final Future<File> Function({required String source, required String name})
      materializeFile;

  @override
  State<WorkspaceFileView> createState() => _WorkspaceFileViewState();
}

class _WorkspaceFileViewState extends State<WorkspaceFileView> {
  static const _migrator = WorkspaceFileMigrator();

  late Map<String, dynamic> metadata;
  Future<File>? _file;
  String? _source;
  int _fileRevision = 0;
  late ViewPB _view;
  late String _rendererName;
  ViewListener? _listener;
  int _listenerGeneration = 0;
  bool _available = true;
  Object _binding = Object();
  int? _size;
  Widget? _renderer;
  File? _renderedFile;
  bool? _renderedEditable;
  bool? _renderedEditingSource;
  PageAccessLevelBloc? _access;
  StandaloneFileChromeController _chrome = StandaloneFileChromeController();
  late MediaActionService _guardedActions;
  MediaActionSource? _actionTarget;
  late bool Function() _canEditBinding;
  late bool Function() _canReadBinding;
  late ViewCoverActionsBackend _guardedCoverBackend;
  Future<void> _viewWrites = Future.value();
  int _pendingMetadataWrites = 0;
  final _fileFocus = FocusNode(debugLabel: 'Standalone file');
  final _focused = ValueNotifier(false);

  String get _name => _view.name.isEmpty ? 'Untitled' : _view.name;

  bool get _canRename {
    if (!mounted || !widget.editable || !_available || _view.isLocked) {
      return false;
    }
    final access = _access;
    if (access == null) return true;
    return !access.isClosed &&
        access.state.view.id == _view.id &&
        !access.state.isLoadingLockStatus &&
        !access.state.isReadOnly &&
        access.state.isEditable;
  }

  /// Files kept inside AppFlowy's own storage can be written back in place.
  /// A downloaded copy of a cloud object cannot, so it opens read only.
  bool get _isEditable {
    if (!_canRename) return false;
    final source = _source;
    if (source == null || source.isEmpty) {
      return false;
    }
    final scheme = Uri.tryParse(source)?.scheme.toLowerCase() ?? '';
    return scheme != 'http' && scheme != 'https';
  }

  FilePreviewKind? get _previewKind => filePreviewKindFromName(_rendererName);

  FileMediaKind? get _mediaKind => fileMediaKind(_rendererName, _source);

  bool get _isImage => imgExtensionRegex.hasMatch(_rendererName.toLowerCase());

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_syncFocus);
    _view = widget.view;
    _rendererName = _name;
    metadata = _seedMetadata(
      WorkspaceFilePreviewCodec.decode(widget.view.extra),
    );
    _resolveFile();
    _listen();
  }

  @override
  void didUpdateWidget(covariant WorkspaceFileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id ||
        oldWidget.view.workspaceItem?.storageUrl !=
            widget.view.workspaceItem?.storageUrl ||
        oldWidget.resolveStorageUrl != widget.resolveStorageUrl ||
        oldWidget.materializeFile != widget.materializeFile) {
      _view = widget.view;
      _rendererName = _name;
      metadata = _seedMetadata(
        WorkspaceFilePreviewCodec.decode(widget.view.extra),
      );
      _resolveFile();
    } else if (oldWidget.view != widget.view) {
      _adoptMetadata(widget.view);
      _view = widget.view;
    }
    if (oldWidget.view.id != widget.view.id ||
        oldWidget.iconListenerFactory != widget.iconListenerFactory) {
      unawaited(_listener?.stop());
      _listen();
    }
    if (oldWidget.mediaActions != widget.mediaActions) {
      _bindMediaActions();
      // Update the forwarded service without changing renderer keys or bytes.
      _renderer = null;
    }
    if (oldWidget.ocrService != widget.ocrService ||
        oldWidget.ocrSourceBuilder != widget.ocrSourceBuilder) {
      _renderer = null;
    }
    if (oldWidget.repository != widget.repository ||
        oldWidget.coverBackend != widget.coverBackend) {
      _bindCoverActions();
    }
  }

  void _listen() {
    final generation = ++_listenerGeneration;
    _available = true;
    _listener = (widget.iconListenerFactory?.call(_view.id) ??
        ViewListener(viewId: _view.id))
      ..start(
        onViewUpdated: (view) {
          if (mounted && generation == _listenerGeneration) _accept(view);
        },
        onViewDeleted: (result) => result.onSuccess((_) {
          if (mounted && generation == _listenerGeneration) {
            setState(() => _available = false);
          }
        }),
        onViewMoveToTrash: (result) => result.onSuccess((_) {
          if (mounted && generation == _listenerGeneration) {
            setState(() => _available = false);
          }
        }),
        onViewRestored: (result) => result.onSuccess((view) {
          if (mounted && generation == _listenerGeneration) {
            _accept(view, restored: true);
          }
        }),
      );
  }

  void _accept(ViewPB view, {bool restored = false}) {
    if (!mounted || view.id != widget.view.id) return;
    // Only an explicit restore can reopen a deleted binding. A delayed rename
    // or icon notification must not make its original-file actions live again.
    if (!_available && !restored) return;
    final changedSource =
        _view.workspaceItem?.storageUrl != view.workspaceItem?.storageUrl;
    setState(() {
      if (!changedSource) _adoptMetadata(view);
      _view = view;
      _available = true;
      if (changedSource) {
        _rendererName = _name;
        metadata = _seedMetadata(WorkspaceFilePreviewCodec.decode(view.extra));
        _resolveFile();
      }
    });
  }

  void _adoptMetadata(ViewPB view) {
    if (_pendingMetadataWrites != 0) return;
    final stored = WorkspaceFilePreviewCodec.decode(view.extra);
    if (!const DeepCollectionEquality().equals(
      stored,
      WorkspaceFilePreviewCodec.decode(_view.extra),
    )) {
      metadata = _seedMetadata(stored);
    }
  }

  void _syncFocus() {
    if (mounted && _focused.value != _fileFocus.hasFocus) {
      _focused.value = _fileFocus.hasFocus;
    }
  }

  @override
  void dispose() {
    _listenerGeneration++;
    _fileRevision++;
    FocusManager.instance.removeListener(_syncFocus);
    _fileFocus.dispose();
    _focused.dispose();
    unawaited(_listener?.stop());
    _chrome.dispose();
    super.dispose();
  }

  /// Plain text opens ready to type. Markup keeps its rendered preview and an
  /// explicit toggle, the same way the embedded block behaves.
  Map<String, dynamic> _seedMetadata(Map<String, dynamic> stored) {
    if (_previewKind == FilePreviewKind.text &&
        !stored.containsKey(filePreviewEditModeKey)) {
      return {...stored, filePreviewEditModeKey: true};
    }
    return stored;
  }

  void _resolveFile() {
    _source = null;
    _binding = Object();
    _chrome.dispose();
    _chrome = StandaloneFileChromeController();
    _size = _view.workspaceItem?.size;
    _renderer = null;
    _renderedFile = null;
    _actionTarget = null;
    _pendingMetadataWrites = 0;
    final binding = _binding;
    _canEditBinding = () => mounted && binding == _binding && _isEditable;
    _canReadBinding = () =>
        mounted &&
        binding == _binding &&
        _available &&
        (_actionTarget?.source.isNotEmpty ?? false);
    _bindMediaActions();
    _bindCoverActions();
    _file = _openFile(_view, _rendererName, ++_fileRevision);
  }

  void _bindMediaActions() {
    final binding = _binding;
    _guardedActions = _WorkspaceFileMediaActions(
      delegate: widget.mediaActions,
      isCurrent: (source) =>
          mounted &&
          _available &&
          binding == _binding &&
          source.source.isNotEmpty &&
          source.name == _name &&
          source == _actionTarget,
    );
  }

  void _bindCoverActions() {
    final binding = _binding;
    final repository = widget.repository;
    final backend = widget.coverBackend;
    _guardedCoverBackend = _WorkspaceFileCoverBackend(
      delegate: backend,
      repository: repository,
      serialize: _serializeViewWrite,
      isCurrent: (view) =>
          mounted &&
          binding == _binding &&
          repository == widget.repository &&
          backend == widget.coverBackend &&
          _canRename &&
          view.id == _view.id &&
          view.cover == _view.cover &&
          view.workspaceItem?.storageUrl == _view.workspaceItem?.storageUrl,
    );
  }

  Future<FlowyResult<void, FlowyError>> _serializeViewWrite(
    Future<FlowyResult<void, FlowyError>> Function() write,
  ) {
    final operation = _viewWrites.then((_) => write());
    _viewWrites = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<File> _openFile(ViewPB view, String name, int revision) async {
    final materialize = widget.materializeFile;
    final source =
        await (widget.resolveStorageUrl ?? _migrator.resolveStorageUrl)(
      view,
    );
    if (!mounted || revision != _fileRevision) {
      throw const FileSystemException('The file source changed while opening.');
    }
    if (source == null || source.isEmpty) {
      throw const FileSystemException(
        'The stored copy of this file could not be found in this workspace.',
      );
    }
    _source = source;
    final file = await materialize(source: source, name: name);
    if (mounted && revision == _fileRevision) {
      unawaited(_readSize(file, revision));
    }
    return file;
  }

  Future<void> _readSize(File file, int revision) async {
    try {
      final size = await file.length();
      if (mounted && revision == _fileRevision && _size != size) {
        setState(() => _size = size);
      }
    } catch (_) {
      // Unknown size is not a reason to refuse an otherwise readable file.
    }
  }

  void _saveMetadata(Map<String, dynamic> value) {
    if (!_canRename) return;
    try {
      ViewCoverCodec.decodeExtra(_view.extra);
    } on FormatException {
      Log.error('Unable to preserve the file view metadata');
      return;
    }
    final binding = _binding;
    final original = _view;
    final repository = widget.repository;
    final writer = widget.writeExtra;
    final settings = Map<String, dynamic>.from(value);
    setState(() {
      metadata = settings;
      _view = ViewPB.fromBuffer(_view.writeToBuffer())
        ..extra = WorkspaceFilePreviewCodec.merge(_view.extra, settings);
      _pendingMetadataWrites++;
    });
    bool current() =>
        mounted &&
        binding == _binding &&
        _canRename &&
        repository == widget.repository &&
        writer == widget.writeExtra;
    unawaited(() async {
      try {
        final result = await _serializeViewWrite(() async {
          if (!current()) return _fileWriteRefused();
          final read = await repository.getView(original.id);
          final live = read.fold<ViewPB?>((view) => view, (_) => null);
          if (!current() ||
              live == null ||
              live.id != original.id ||
              live.isLocked ||
              live.workspaceItem?.storageUrl !=
                  original.workspaceItem?.storageUrl) {
            return _fileWriteRefused();
          }
          // The preview codec is intentionally forgiving while reading. A
          // write must not turn malformed unrelated metadata into an empty map.
          ViewCoverCodec.decodeExtra(live.extra);
          return writer(
            viewId: live.id,
            extra: WorkspaceFilePreviewCodec.merge(live.extra, settings),
          );
        });
        result.onFailure(
          (_) => Log.error('Unable to store the file viewer state'),
        );
      } catch (_) {
        Log.error('Unable to store the file viewer state');
      } finally {
        if (mounted && binding == _binding) _pendingMetadataWrites--;
      }
    }());
  }

  void _toggleSourceEditing() {
    if (!_isEditable) return;
    final editing = metadata[filePreviewEditModeKey] == true;
    _saveMetadata({...metadata, filePreviewEditModeKey: !editing});
  }

  /// A stack trace is not an explanation. Say what went wrong and where.
  static String _describeError(Object error) {
    if (error is FileSystemException) {
      final path = error.path;
      return path == null || path.isEmpty
          ? error.message
          : '${error.message}\n$path';
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    _access = context.watch<PageAccessLevelBloc?>();
    final profile = context.watch<UserWorkspaceBloc?>()?.state.userProfile;
    final canvas = EditorSurfaceStyle.canvasBackgroundFor(
      Theme.of(context).brightness,
      Theme.of(context).scaffoldBackgroundColor,
      isPaper: PaperTheme.isEnabled(context),
    );
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snapshot) {
        // FutureBuilder retains the previous data while a new source loads.
        // Keep the action state (including its in-flight lock), not that target.
        final file = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        final Widget renderer;
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasError) {
          renderer = _WorkspaceFileMessage(
            icon: Icons.error_outline_rounded,
            title: 'This file could not be opened',
            message: _describeError(snapshot.error!),
            action: _WorkspaceFileAction(
              label: 'Try again',
              onPressed: () => setState(_resolveFile),
            ),
          );
        } else if (file == null || _access?.state.isLoadingLockStatus == true) {
          renderer = const Center(child: CircularProgressIndicator());
        } else {
          final editingSource = metadata[filePreviewEditModeKey] == true;
          if (_renderer == null ||
              !identical(file, _renderedFile) ||
              _renderedEditable != _isEditable ||
              _renderedEditingSource != editingSource) {
            _renderedFile = file;
            _renderedEditable = _isEditable;
            _renderedEditingSource = editingSource;
            _renderer = _buildRenderer(context, file);
          }
          renderer = _renderer!;
        }
        final source = MediaActionSource(
          // A cloud download is already local here. Do not fetch it again or
          // attach workspace credentials to a materialized file.
          source: file?.path ?? '',
          name: _name,
          isImage: _isImage,
        );
        _actionTarget = source;
        final body = KeyedSubtree(key: ObjectKey(_file), child: renderer);
        final binding = _binding;
        return PreviewToolbarRegion(
          child: Focus(
            focusNode: _fileFocus,
            canRequestFocus: false,
            skipTraversal: true,
            includeSemantics: false,
            onFocusChange: (_) => _syncFocus(),
            child: StandaloneFileScope(
              canvas: canvas,
              rendererName: _rendererName,
              displayName: _name,
              canEdit: _canEditBinding,
              canRead: _canReadBinding,
              editable: _isEditable,
              available: _available && file != null,
              metadata: metadata,
              chrome: _chrome,
              child: ColoredBox(
                key: const ValueKey('workspace-file-canvas'),
                color: canvas,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<StandaloneFileHeader>(
                      valueListenable: _chrome,
                      builder: (context, controls, _) =>
                          ValueListenableBuilder<bool>(
                        valueListenable: _focused,
                        builder: (context, focused, _) =>
                            WorkspaceFileIdentityRow(
                          key: const ValueKey('workspace-file-identity'),
                          view: _view,
                          binding: binding,
                          summary: [
                            p
                                .extension(_name)
                                .replaceFirst('.', '')
                                .toUpperCase(),
                            if (_size != null) _describeSize(_size!),
                          ].where((part) => part.isNotEmpty).join(' · '),
                          canRename: () => binding == _binding && _canRename,
                          onViewChanged: _accept,
                          repository: widget.repository,
                          coverBackend: _guardedCoverBackend,
                          updateIcon: widget.updateIcon,
                          userProfile: profile,
                          source: source,
                          mediaActions: _guardedActions,
                          fileAvailable: file != null && _available,
                          actionsVisible: focused,
                          controls: controls,
                        ),
                      ),
                    ),
                    // Hover only rebuilds chrome, not the retained renderer.
                    Expanded(child: body),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRenderer(BuildContext context, File file) {
    final binding = _binding;
    final name = _rendererName;
    final viewId = _view.id;
    final editable = _isEditable;
    final rendererMetadata = metadata;
    void saveMetadata(Map<String, dynamic> value) {
      if (mounted && binding == _binding) _saveMetadata(value);
    }

    final mediaKind = _mediaKind;
    if (mediaKind != null) {
      return _WorkspaceMediaStage(
        file: file,
        name: _rendererName,
        kind: mediaKind,
      );
    }

    if (_isImage) {
      return _WorkspaceImageStage(
        file: file,
        name: _rendererName,
        ocrService: widget.ocrService,
        ocrSourceBuilder: widget.ocrSourceBuilder,
      );
    }

    // A stored message is still a message, so it opens in the mail reader
    // rather than as an unreadable attachment.
    if (looksLikeMessageFileName(_rendererName)) {
      return EmailFileView(view: _view, file: file);
    }

    final kind = _previewKind;

    if (isOfficeFile(_rendererName)) {
      return OfficeDocumentView(
        file: file,
        name: _rendererName,
        source: _source ?? file.path,
        editable: _isEditable,
        fallbackBuilder: kind == null
            ? null
            : (context) => LayoutBuilder(
                  builder: (context, constraints) => FilePreview(
                    file: file,
                    name: name,
                    kind: kind,
                    metadata: rendererMetadata,
                    onMetadataChanged: saveMetadata,
                    editable: editable,
                    height: constraints.maxHeight,
                    framed: false,
                  ),
                ),
      );
    }

    if (kind == null) {
      return _WorkspaceFileMessage(
        icon: fileIconForName(_name),
        title: '',
        message: 'AppFlowy has no viewer for this file type yet.',
        action: _WorkspaceFileAction(
          label: 'Open with system app',
          onPressed: () {
            if (mounted && binding == _binding && _available) {
              unawaited(afLaunchUrlString(file.uri.toString()));
            }
          },
        ),
      );
    }

    if (kind == FilePreviewKind.pdf) {
      return PdfPreview(
        key: ValueKey('${widget.view.id}_pdf'),
        file: file,
        name: _rendererName,
        metadata: metadata,
        onMetadataChanged: saveMetadata,
        editable: _isEditable,
        mediaActions: widget.mediaActions,
      );
    }

    if (kind == FilePreviewKind.archive) {
      return ArchiveExplorer(
        key: ValueKey('${widget.view.id}_archive'),
        file: file,
        name: _rendererName,
        editable: _isEditable,
        embedded: false,
        metadata: rendererMetadata,
        onMetadataChanged: saveMetadata,
        mediaActions: widget.mediaActions,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => FilePreview(
        key: ValueKey('${viewId}_${file.path}'),
        file: file,
        name: name,
        kind: kind,
        metadata: rendererMetadata,
        onMetadataChanged: saveMetadata,
        editable: editable,
        height: constraints.maxHeight,
        framed: false,
        toolbarTrailing: kind.supportsSourceEditing && editable
            ? _SourceModeToggle(
                editing: rendererMetadata[filePreviewEditModeKey] == true,
                onPressed: () {
                  if (mounted && binding == _binding) _toggleSourceEditing();
                },
              )
            : null,
      ),
    );
  }
}

class _WorkspaceFileMediaActions extends MediaActionService {
  const _WorkspaceFileMediaActions({
    required this.delegate,
    required this.isCurrent,
  });

  final MediaActionService delegate;
  final bool Function(MediaActionSource) isCurrent;

  @override
  Future<void> copy(MediaActionSource source) async {
    if (!isCurrent(source)) throw StateError('File unavailable');
    await delegate.copy(source);
  }

  @override
  Future<void> share(
    MediaActionSource source, {
    Rect? sharePositionOrigin,
  }) async {
    if (!isCurrent(source)) throw StateError('File unavailable');
    await delegate.share(source, sharePositionOrigin: sharePositionOrigin);
  }
}

FlowyResult<void, FlowyError> _fileWriteRefused() => FlowyResult.failure(
      FlowyError(msg: 'This file is no longer available for editing.'),
    );

/// Uses the existing cover action model and its upload/cleanup ownership. Only
/// the save boundary adds file-binding guards and a fresh-extra preflight.
class _WorkspaceFileCoverBackend extends ViewCoverActionsBackend {
  const _WorkspaceFileCoverBackend({
    required this.delegate,
    required this.repository,
    required this.serialize,
    required this.isCurrent,
  });

  final ViewCoverActionsBackend delegate;
  final WorkspaceItemRepository repository;
  final Future<FlowyResult<void, FlowyError>> Function(
    Future<FlowyResult<void, FlowyError>> Function() write,
  ) serialize;
  final bool Function(ViewPB) isCurrent;

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> currentUser() =>
      delegate.currentUser();

  @override
  Future<ViewCoverUpload?> upload({
    required String path,
    required ViewPB view,
    required UserProfilePB profile,
  }) async =>
      isCurrent(view)
          ? delegate.upload(path: path, view: view, profile: profile)
          : null;

  @override
  Future<FlowyResult<void, FlowyError>> save({
    required ViewPB view,
    required PageStyleCover cover,
  }) =>
      serialize(() async {
        if (!isCurrent(view)) return _fileWriteRefused();
        final read = await repository.getView(view.id);
        final live = read.fold<ViewPB?>((view) => view, (_) => null);
        if (!isCurrent(view) ||
            live == null ||
            live.isLocked ||
            !isCurrent(live) ||
            live.cover != view.cover) {
          return _fileWriteRefused();
        }
        return delegate.save(view: live, cover: cover);
      });

  @override
  Future<void> delete(PageStyleCover cover) => delegate.delete(cover);
}

/// Switches markup files between their rendered preview and the editor.
class _SourceModeToggle extends StatelessWidget {
  const _SourceModeToggle({required this.editing, required this.onPressed});

  final bool editing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: editing ? 'Show preview' : 'Edit source',
      child: TextButton.icon(
        onPressed: onPressed,
        style: WorkspaceChrome.controlStyle(context),
        icon: WorkspaceGlyph(
          editing ? Icons.visibility_rounded : Icons.edit_rounded,
          size: 16,
        ),
        label: Text(editing ? 'Preview' : 'Edit'),
      ),
    );
  }
}

class _WorkspaceMediaStage extends StatelessWidget {
  const _WorkspaceMediaStage({
    required this.file,
    required this.name,
    required this.kind,
  });

  final File file;
  final String name;
  final FileMediaKind kind;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: kind == FileMediaKind.audio ? 560 : 1180,
        ),
        child: FileMediaPlayer(
          url: file.path,
          name: name,
          kind: kind,
        ),
      ),
    );
  }
}

class _WorkspaceImageStage extends StatefulWidget {
  const _WorkspaceImageStage({
    required this.file,
    required this.name,
    this.ocrService,
    this.ocrSourceBuilder,
  });

  final File file;
  final String name;
  final OcrService? ocrService;
  final ImageOcrSourceBuilder? ocrSourceBuilder;

  @override
  State<_WorkspaceImageStage> createState() => _WorkspaceImageStageState();
}

class _WorkspaceImageStageState extends State<_WorkspaceImageStage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformation = TransformationController();
  AnimationController? _fitController;
  AnimationController get _fitAnimation =>
      _fitController ??= (AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 200),
      )..addListener(_animateFit));
  Matrix4Tween? _fitTween;
  int _revision = 0;
  int _fitRevision = 0;
  String? _subtitle;
  StandaloneFileScope? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host = StandaloneFileScope.forName(context, widget.name);
  }

  ImageEditorSource get _source => ImageEditorSource(
        url: widget.file.path,
        type: CustomImageType.local,
      );

  ImageEditorSource get _ocrSource =>
      widget.ocrSourceBuilder?.call(
        ImageBlockData(url: widget.file.path, type: CustomImageType.local),
      ) ??
      _source;

  bool _canRead() => mounted && _host?.canRead() == true;

  @override
  void initState() {
    super.initState();
    unawaited(_readDetails());
  }

  @override
  void dispose() {
    // Closing a picture before using Fit must not create a ticker during
    // teardown, when inherited widget lookups are no longer safe.
    _fitController?.dispose();
    _transformation.dispose();
    super.dispose();
  }

  Future<void> _readDetails() async {
    try {
      final stat = await widget.file.stat();
      if (mounted) {
        setState(() => _subtitle = _describeSize(stat.size));
      }
    } on FileSystemException {
      // The header simply stays quiet when the size is unknown.
    }
  }

  Future<void> _edit() async {
    final host = _host;
    if (!mounted || host == null || !host.canEdit()) return;
    bool current() => mounted && _host?.chrome == host.chrome && host.canEdit();
    final saved = await showImageEditor(
      context,
      source: _source,
      name: host.displayName,
      onSave: (bytes) async {
        if (!current()) return false;
        await widget.file.writeAsBytes(bytes, flush: true);
        return true;
      },
    );
    if (saved == true && current()) {
      // The path is unchanged, so the decoded frame has to be dropped by hand.
      await FileImage(widget.file).evict();
      if (mounted) {
        setState(() => _revision++);
        unawaited(_readDetails());
      }
    }
  }

  void _fitToView() {
    if (!mounted || _host?.canRead() != true) return;
    _fitAnimation.stop();
    // A controller assignment does not stop InteractiveViewer's private pinch
    // inertia. Reset its gesture state, retaining the matrix and cached image,
    // so an earlier fling cannot overwrite the requested fit on a later frame.
    setState(() => _fitRevision++);
    if (_transformation.value.isIdentity()) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _transformation.value = Matrix4.identity();
      return;
    }
    _fitTween = Matrix4Tween(
      begin: _transformation.value.clone(),
      end: Matrix4.identity(),
    );
    unawaited(_fitAnimation.forward(from: 0));
  }

  void _animateFit() {
    final tween = _fitTween;
    if (tween != null) {
      _transformation.value = tween.transform(
        Curves.easeOutCubic.transform(_fitAnimation.value),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final host = _host;
    const extractKey = 'document.plugins.image.extractText';
    final translated = extractKey.tr();
    final extractLabel = translated == extractKey ? 'Extract text' : translated;
    return DocumentViewport(
      framed: false,
      background: Theme.of(context).scaffoldBackgroundColor,
      revealKey: widget.file.path,
      identity: DocumentIdentity(
        title: widget.name,
        icon: Icons.image_rounded,
        subtitle: _subtitle,
      ),
      actions: [
        DocumentViewportButton(
          icon: Icons.tune_rounded,
          tooltip: 'Edit image',
          onPressed: host?.canEdit() == true ? () => unawaited(_edit()) : null,
        ),
        DocumentViewportButton(
          icon: Icons.document_scanner_rounded,
          tooltip: extractLabel,
          onPressed: host?.canRead() == true
              ? () {
                  if (!mounted || host?.canRead() != true) return;
                  unawaited(
                    showImageOcrOverlay(
                      context,
                      source: _ocrSource,
                      name: _host?.displayName ?? widget.name,
                      service: widget.ocrService,
                    ),
                  );
                }
              : null,
        ),
        const DocumentViewportSeparator(),
        DocumentViewportFitButton(
          onPressed: _fitToView,
        ),
      ],
      child: HistorySwipeExclusion(
        child: Listener(
          // A new gesture takes over immediately, rather than fighting a reset.
          onPointerDown: (_) => _fitAnimation.stop(),
          onPointerSignal: (_) => _fitAnimation.stop(),
          child: ClipRect(
            child: InteractiveViewer(
              key: ValueKey(_fitRevision),
              transformationController: _transformation,
              onInteractionStart: (_) => _fitAnimation.stop(),
              minScale: 0.4,
              maxScale: 8,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  // The card hugs the picture instead of filling the window, so
                  // nothing sits behind it but the page.
                  child: ViewerCard(
                    reactsToPointer: false,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ImageOcrFindRegion(
                        source: _ocrSource,
                        name: host?.displayName ?? widget.name,
                        service: widget.ocrService,
                        isAvailable: _canRead,
                        isSelected: _canRead,
                        debugLabel: 'Workspace image',
                        child: Image.file(
                          widget.file,
                          key: ValueKey('${widget.file.path}_$_revision'),
                          errorBuilder: (context, error, stackTrace) => Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              'This picture could not be decoded.',
                              style: TextStyle(
                                color: theme.textColorScheme.secondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _describeSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final rounded = value >= 10 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$rounded ${units[unit]}';
}

class _WorkspaceFileAction extends StatelessWidget {
  const _WorkspaceFileAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.textColorScheme.primary,
        backgroundColor: theme.fillColorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

class _WorkspaceFileMessage extends StatelessWidget {
  const _WorkspaceFileMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The same message has to fit a whole window and a dashboard card.
        final tight = constraints.maxHeight < 260;
        return Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ViewerCard(
                color: theme.fillColorScheme.content,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tight ? 16 : 28,
                    vertical: tight ? 16 : 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: tight ? 24 : 34,
                        color: theme.iconColorScheme.secondary,
                      ),
                      if (title.isNotEmpty) ...[
                        SizedBox(height: tight ? 8 : 14),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: tight ? 13.5 : 15,
                            fontWeight: FontWeight.w600,
                            color: theme.textColorScheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        maxLines: tight ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: tight ? 12 : 13,
                          height: 18 / 13,
                          color: theme.textColorScheme.secondary,
                        ),
                      ),
                      if (action != null) ...[
                        SizedBox(height: tight ? 12 : 18),
                        action!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
