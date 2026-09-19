import 'dart:async';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
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
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_migrator.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/scrolling/trackpad_history_navigation.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

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
  });

  final ViewPB view;
  final MediaActionService mediaActions;

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

  String get _name => widget.view.name.isEmpty ? 'Untitled' : widget.view.name;

  /// Files kept inside AppFlowy's own storage can be written back in place.
  /// A downloaded copy of a cloud object cannot, so it opens read only.
  bool get _isEditable {
    final source = _source;
    if (source == null || source.isEmpty) {
      return false;
    }
    final scheme = Uri.tryParse(source)?.scheme.toLowerCase() ?? '';
    return scheme != 'http' && scheme != 'https';
  }

  FilePreviewKind? get _previewKind => filePreviewKindFromName(_name);

  FileMediaKind? get _mediaKind => fileMediaKind(_name, _source);

  bool get _isImage => imgExtensionRegex.hasMatch(_name.toLowerCase());

  @override
  void initState() {
    super.initState();
    metadata = _seedMetadata(
      WorkspaceFilePreviewCodec.decode(widget.view.extra),
    );
    _resolveFile();
  }

  @override
  void didUpdateWidget(covariant WorkspaceFileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id ||
        oldWidget.view.name != widget.view.name ||
        oldWidget.view.workspaceItem?.storageUrl !=
            widget.view.workspaceItem?.storageUrl ||
        oldWidget.resolveStorageUrl != widget.resolveStorageUrl ||
        oldWidget.materializeFile != widget.materializeFile) {
      metadata = _seedMetadata(
        WorkspaceFilePreviewCodec.decode(widget.view.extra),
      );
      _resolveFile();
    }
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
    _file = _openFile(widget.view, _name, ++_fileRevision);
  }

  Future<File> _openFile(ViewPB view, String name, int revision) async {
    final materialize = widget.materializeFile;
    final source =
        await (widget.resolveStorageUrl ?? _migrator.resolveStorageUrl)(
      view,
    );
    if (source == null || source.isEmpty) {
      throw const FileSystemException(
        'The stored copy of this file could not be found in this workspace.',
      );
    }
    if (mounted && revision == _fileRevision) _source = source;
    return materialize(source: source, name: name);
  }

  void _saveMetadata(Map<String, dynamic> value) {
    setState(() => metadata = value);
    unawaited(
      ViewBackendService.updateView(
        viewId: widget.view.id,
        extra: WorkspaceFilePreviewCodec.merge(widget.view.extra, value),
      ).then(
        (result) => result.onFailure(
          (error) => Log.error('Unable to store the file viewer state: $error'),
        ),
      ),
    );
  }

  void _toggleSourceEditing() {
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
        } else if (file == null) {
          renderer = const Center(child: CircularProgressIndicator());
        } else {
          renderer = _buildRenderer(context, file);
        }
        final source = MediaActionSource(
          // A cloud download is already local here. Do not fetch it again or
          // attach workspace credentials to a materialized file.
          source: file?.path ?? '',
          name: _name,
          isImage: _isImage,
        );
        final body = KeyedSubtree(key: ObjectKey(_file), child: renderer);
        return MediaHoverRegion(
          builder: (context, visible) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                key: const ValueKey('workspace-file-media-actions'),
                // The shared badge paints above the buttons. Reserve its
                // scaled height, outside renderer menus and scrollbars.
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.textScalerOf(context).scale(10) * 1.2 + 10,
                  16,
                  4,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ExcludeFocus(
                    excluding: file == null,
                    child: Visibility(
                      visible: file != null,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      child: MediaActionReveal(
                        visible: visible,
                        child: MediaActionButtons(
                          source: source,
                          actions: widget.mediaActions,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Capture the renderer outside the hover builder: revealing the
              // controls must not rebuild a player, editor or platform view.
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRenderer(BuildContext context, File file) {
    final mediaKind = _mediaKind;
    if (mediaKind != null) {
      return _WorkspaceMediaStage(
        file: file,
        name: _name,
        kind: mediaKind,
      );
    }

    if (_isImage) {
      return _WorkspaceImageStage(file: file, name: _name);
    }

    // A stored message is still a message, so it opens in the mail reader
    // rather than as an unreadable attachment.
    if (looksLikeMessageFileName(_name)) {
      return EmailFileView(view: widget.view, file: file);
    }

    final kind = _previewKind;

    if (isOfficeFile(_name)) {
      return OfficeDocumentView(
        file: file,
        name: _name,
        source: _source ?? file.path,
        editable: _isEditable,
        fallbackBuilder: kind == null
            ? null
            : (context) => LayoutBuilder(
                  builder: (context, constraints) => FilePreview(
                    file: file,
                    name: _name,
                    kind: kind,
                    metadata: metadata,
                    onMetadataChanged: _saveMetadata,
                    editable: _isEditable,
                    height: constraints.maxHeight,
                    framed: false,
                  ),
                ),
      );
    }

    if (kind == null) {
      return _WorkspaceFileMessage(
        icon: fileIconForName(_name),
        title: _name,
        message: 'AppFlowy has no viewer for this file type yet.',
        action: _WorkspaceFileAction(
          label: 'Open with system app',
          onPressed: () => unawaited(afLaunchUrlString(file.uri.toString())),
        ),
      );
    }

    if (kind == FilePreviewKind.pdf) {
      return PdfPreview(
        key: ValueKey('${widget.view.id}_pdf'),
        file: file,
        name: _name,
        metadata: metadata,
        onMetadataChanged: _saveMetadata,
        editable: _isEditable,
        mediaActions: widget.mediaActions,
      );
    }

    if (kind == FilePreviewKind.archive) {
      return ArchiveExplorer(
        key: ValueKey('${widget.view.id}_archive'),
        file: file,
        name: _name,
        editable: _isEditable,
        embedded: false,
        mediaActions: widget.mediaActions,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => FilePreview(
        key: ValueKey('${widget.view.id}_${file.path}'),
        file: file,
        name: _name,
        kind: kind,
        metadata: metadata,
        onMetadataChanged: _saveMetadata,
        editable: _isEditable,
        height: constraints.maxHeight,
        framed: false,
        toolbarTrailing: kind.supportsSourceEditing
            ? _SourceModeToggle(
                editing: metadata[filePreviewEditModeKey] == true,
                onPressed: _toggleSourceEditing,
              )
            : null,
      ),
    );
  }
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
        icon: Icon(
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
  const _WorkspaceImageStage({required this.file, required this.name});

  final File file;
  final String name;

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

  ImageEditorSource get _source => ImageEditorSource(
        url: widget.file.path,
        type: CustomImageType.local,
      );

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
    final saved = await showImageEditor(
      context,
      source: _source,
      name: widget.name,
      onSave: (bytes) async {
        await widget.file.writeAsBytes(bytes, flush: true);
        return true;
      },
    );
    if (saved == true && mounted) {
      // The path is unchanged, so the decoded frame has to be dropped by hand.
      await FileImage(widget.file).evict();
      if (mounted) {
        setState(() => _revision++);
        unawaited(_readDetails());
      }
    }
  }

  void _fitToView() {
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
          onPressed: () => unawaited(_edit()),
        ),
        DocumentViewportButton(
          icon: Icons.text_fields_rounded,
          tooltip: 'Extract text',
          onPressed: () => unawaited(
            showImageOcrOverlay(
              context,
              source: _source,
              name: widget.name,
            ),
          ),
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
