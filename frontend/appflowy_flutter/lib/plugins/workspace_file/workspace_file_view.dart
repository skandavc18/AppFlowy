import 'dart:async';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
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
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_migrator.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/viewer_card.dart';
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
  const WorkspaceFileView({super.key, required this.view});

  final ViewPB view;

  @override
  State<WorkspaceFileView> createState() => _WorkspaceFileViewState();
}

class _WorkspaceFileViewState extends State<WorkspaceFileView> {
  static const _migrator = WorkspaceFileMigrator();

  late Map<String, dynamic> metadata;
  Future<File>? _file;
  String? _source;

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
        oldWidget.view.name != widget.view.name) {
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
    _file = _openFile();
  }

  Future<File> _openFile() async {
    final source = await _migrator.resolveStorageUrl(widget.view);
    if (source == null || source.isEmpty) {
      throw const FileSystemException(
        'The stored copy of this file could not be found in this workspace.',
      );
    }
    _source = source;
    return materializeMediaFile(source: source, name: _name);
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _WorkspaceFileMessage(
            icon: Icons.error_outline_rounded,
            title: 'This file could not be opened',
            message: snapshot.error.toString(),
            action: _WorkspaceFileAction(
              label: 'Try again',
              onPressed: () => setState(_resolveFile),
            ),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildRenderer(context, file);
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
      );
    }

    if (kind == FilePreviewKind.archive) {
      return ArchiveExplorer(
        key: ValueKey('${widget.view.id}_archive'),
        file: file,
        name: _name,
        editable: _isEditable,
        embedded: false,
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
    final theme = AppFlowyTheme.of(context);
    return Tooltip(
      message: editing ? 'Show preview' : 'Edit source',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                editing ? Icons.visibility_rounded : Icons.edit_rounded,
                size: 16,
                color: theme.iconColorScheme.secondary,
              ),
              const SizedBox(width: 6),
              Text(
                editing ? 'Preview' : 'Edit',
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.textColorScheme.secondary,
                ),
              ),
            ],
          ),
        ),
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

class _WorkspaceImageStageState extends State<_WorkspaceImageStage> {
  final TransformationController _transformation = TransformationController();
  int _revision = 0;
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

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return DocumentViewport(
      framed: false,
      background: Colors.transparent,
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
        DocumentViewportButton(
          icon: Icons.fit_screen_rounded,
          tooltip: 'Fit to view',
          onPressed: () => _transformation.value = Matrix4.identity(),
        ),
      ],
      child: ClipRect(
        child: InteractiveViewer(
          transformationController: _transformation,
          minScale: 0.4,
          maxScale: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ViewerCard(
          color: theme.fillColorScheme.content,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34, color: theme.iconColorScheme.secondary),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    color: theme.textColorScheme.secondary,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 18),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
